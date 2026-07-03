//! Remote extractor rule engine.
//!
//! Two responsibilities:
//!
//! 1. **Storage** — a versioned JSON registry, cached to disk, hot-swapped
//!    when a newer rule pack is downloaded (see [`rust_sync_remote_rules`]).
//! 2. **Execution** — a tiny, safe extraction VM that turns a JSON rule into
//!    an actual [`VideoInfoResult`]. Because rules are pure data (no code
//!    injection), we can ship updates without publishing a new app version.
//!    This is what gives Android the same self-healing property as desktop.
//!
//! The VM supports four operations:
//! - `fetch`          — HTTP GET a URL, store the body under a variable name.
//! - `regex_extract`  — capture group #1 from `input`, store as a string.
//! - `regex_find_all` — every capture group #1 from `input`, store as a list.
//! - `build_stream`   — emit a [`StreamResult`] with URL/quality/container
//!                       drawn from literals or variables.
//!
//! Variables are interpolated with `{{name}}` or `{{name[0]}}` inside literal
//! strings (including URLs and the input to `fetch`). The extractor
//! substitutes `{{url}}` with the incoming request URL before the first step
//! runs. Unknown or empty variables cause the rule to be skipped so we can
//! move on to the next candidate (fallback-friendly by design).
//!
//! Backward compatibility: the pre-existing `patterns: HashMap<String,String>`
//! field is preserved on [`PlatformRule`] and remains queryable via
//! [`get_remote_pattern`], but new packs are expected to use `url_patterns +
//! steps`.

use anyhow::Result;
use flutter_rust_bridge::frb;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use super::debug_log;
use super::models::{StreamResult, VideoInfoResult};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PlatformRule {
    pub platform: String,
    pub version: u32,
    /// Legacy free-form key/value store. New rules should prefer `steps`.
    #[serde(default)]
    pub patterns: HashMap<String, String>,
    /// Regex list matched against the incoming URL. If empty, the rule is
    /// considered a *legacy* rule and is skipped by the executor.
    #[serde(default)]
    pub url_patterns: Vec<String>,
    /// Optional custom User-Agent for fetches inside this rule.
    #[serde(default)]
    pub user_agent: Option<String>,
    /// Optional relative priority (higher wins). Rules with the same
    /// priority are tried in registry order.
    #[serde(default)]
    pub priority: i32,
    /// Execution program.
    #[serde(default)]
    pub steps: Vec<RuleStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum RuleStep {
    Fetch {
        url: String,
        #[serde(default = "default_body_var", rename = "as")]
        as_var: String,
    },
    RegexExtract {
        input: String,
        pattern: String,
        #[serde(rename = "as")]
        as_var: String,
    },
    RegexFindAll {
        input: String,
        pattern: String,
        #[serde(rename = "as")]
        as_var: String,
    },
    BuildStream {
        url: String,
        #[serde(default = "default_quality")]
        quality: String,
        #[serde(default = "default_container")]
        container: String,
        #[serde(default)]
        is_audio_only: bool,
    },
    SetTitle { value: String },
    SetThumbnail { value: String },
    SetAuthor { value: String },
}

fn default_body_var() -> String { "html".into() }
fn default_quality() -> String { "Auto".into() }
fn default_container() -> String { "mp4".into() }

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RulesRegistry {
    pub rules: Vec<PlatformRule>,
    pub last_updated: u64,
}

static REGISTRY: OnceLock<Arc<Mutex<RulesRegistry>>> = OnceLock::new();

fn registry() -> &'static Arc<Mutex<RulesRegistry>> {
    REGISTRY.get_or_init(|| {
        let r = load_local_rules().unwrap_or_default();
        Arc::new(Mutex::new(r))
    })
}

fn get_cache_path() -> PathBuf {
    let mut p = PathBuf::from(super::downloader::get_downloads_dir().unwrap_or_else(|_| ".".into()));
    p.push(".rules_cache.json");
    p
}

fn load_local_rules() -> Result<RulesRegistry> {
    let path = get_cache_path();
    if path.exists() {
        let content = fs::read_to_string(path)?;
        Ok(serde_json::from_str(&content)?)
    } else {
        Ok(RulesRegistry::default())
    }
}

fn save_local_rules(r: &RulesRegistry) -> Result<()> {
    let path = get_cache_path();
    let content = serde_json::to_string_pretty(r)?;
    fs::write(path, content)?;
    Ok(())
}

// ────────────────────────────────────────────────────────────────────────
// Public FRB surface — sync + inspect
// ────────────────────────────────────────────────────────────────────────

/// Install a rule pack loaded from disk / bundled asset. Called at startup
/// with the seed pack shipped inside the app. Merges with newer rules only.
#[frb]
pub fn rust_install_bundled_rules(json: String) -> Result<u32, String> {
    let new_registry: RulesRegistry = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let mut reg = registry().lock();
    merge_registry(&mut reg, new_registry);
    save_local_rules(&reg).map_err(|e| e.to_string())?;
    Ok(reg.rules.len() as u32)
}

/// Fetch rules from a remote URL. Only newer versions per platform are kept.
#[frb]
pub async fn rust_sync_remote_rules(url: String) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| e.to_string())?;

    let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
    let status = resp.status();
    if !status.is_success() {
        return Err(format!(
            "rules URL returned HTTP {} (body is not JSON)",
            status.as_u16()
        ));
    }
    let new_registry: RulesRegistry = resp.json().await.map_err(|e| e.to_string())?;

    let mut reg = registry().lock();
    merge_registry(&mut reg, new_registry);
    save_local_rules(&reg).map_err(|e| e.to_string())?;
    Ok(())
}

fn merge_registry(target: &mut RulesRegistry, incoming: RulesRegistry) {
    for new_rule in incoming.rules {
        if let Some(old_rule) = target
            .rules
            .iter_mut()
            .find(|r| r.platform == new_rule.platform)
        {
            if new_rule.version > old_rule.version {
                *old_rule = new_rule;
            }
        } else {
            target.rules.push(new_rule);
        }
    }
    target.last_updated = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
}

/// Legacy lookup, kept for callers that just want a raw pattern string.
pub fn get_remote_pattern(platform: &str, key: &str) -> Option<String> {
    let reg = registry().lock();
    reg.rules
        .iter()
        .find(|r| r.platform == platform)?
        .patterns
        .get(key)
        .cloned()
}

#[frb(sync)]
pub fn rust_get_rules_status() -> String {
    let reg = registry().lock();
    let executable = reg.rules.iter().filter(|r| !r.steps.is_empty()).count();
    format!(
        "Total: {} (executable: {}), Last Sync: {}",
        reg.rules.len(),
        executable,
        reg.last_updated
    )
}

// ────────────────────────────────────────────────────────────────────────
// Rule execution VM
// ────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
enum RuleValue {
    Text(String),
    List(Vec<String>),
}

impl RuleValue {
    fn as_text(&self) -> String {
        match self {
            RuleValue::Text(t) => t.clone(),
            RuleValue::List(l) => l.first().cloned().unwrap_or_default(),
        }
    }
    fn indexed(&self, idx: usize) -> Option<String> {
        match self {
            RuleValue::List(l) => l.get(idx).cloned(),
            RuleValue::Text(t) if idx == 0 => Some(t.clone()),
            _ => None,
        }
    }
}

/// Public async entry: try the rule registry against `url`. Returns the first
/// rule that produces at least one stream.
pub async fn extract_via_rules(url: &str) -> Result<VideoInfoResult, String> {
    // Snapshot rules so we release the mutex before doing HTTP.
    let candidates: Vec<PlatformRule> = {
        let reg = registry().lock();
        let mut v: Vec<PlatformRule> = reg
            .rules
            .iter()
            .filter(|r| !r.steps.is_empty() && !r.url_patterns.is_empty())
            .cloned()
            .collect();
        v.sort_by(|a, b| b.priority.cmp(&a.priority));
        v
    };

    if candidates.is_empty() {
        return Err("no executable rules loaded".into());
    }

    let mut last_err = String::new();

    for rule in candidates.iter() {
        if !rule_matches(rule, url) {
            continue;
        }

        match execute_rule(rule, url).await {
            Ok(v) if !v.streams.is_empty() => {
                debug_log::log_debug(&format!(
                    "remote_rules: '{}' v{} matched and produced {} stream(s)",
                    rule.platform,
                    rule.version,
                    v.streams.len()
                ));
                return Ok(v);
            }
            Ok(_) => {
                last_err = format!("rule '{}' matched but produced no streams", rule.platform);
            }
            Err(e) => {
                last_err = format!("rule '{}': {}", rule.platform, e);
                debug_log::log_debug(&format!("remote_rules: {}", last_err));
            }
        }
    }

    Err(if last_err.is_empty() {
        "no rule matched".into()
    } else {
        last_err
    })
}

fn rule_matches(rule: &PlatformRule, url: &str) -> bool {
    rule.url_patterns.iter().any(|p| {
        regex::Regex::new(p)
            .map(|re| re.is_match(url))
            .unwrap_or(false)
    })
}

async fn execute_rule(rule: &PlatformRule, url: &str) -> Result<VideoInfoResult, String> {
    let ua = rule.user_agent.clone().unwrap_or_else(|| {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36".into()
    });

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .user_agent(ua)
        .build()
        .map_err(|e| e.to_string())?;

    let mut vars: HashMap<String, RuleValue> = HashMap::new();
    vars.insert("url".into(), RuleValue::Text(url.to_string()));

    let mut title: Option<String> = None;
    let mut thumbnail: Option<String> = None;
    let mut author: Option<String> = None;
    let mut streams: Vec<StreamResult> = Vec::new();

    for step in rule.steps.iter() {
        match step {
            RuleStep::Fetch { url: target, as_var } => {
                let resolved = interpolate(target, &vars);
                if resolved.is_empty() {
                    return Err(format!("fetch: url is empty (template: {})", target));
                }
                let body = client
                    .get(&resolved)
                    .send()
                    .await
                    .map_err(|e| format!("fetch {}: {}", resolved, e))?
                    .text()
                    .await
                    .map_err(|e| format!("fetch body {}: {}", resolved, e))?;
                vars.insert(as_var.clone(), RuleValue::Text(body));
            }
            RuleStep::RegexExtract { input, pattern, as_var } => {
                let re = regex::Regex::new(pattern)
                    .map_err(|e| format!("bad regex {:?}: {}", pattern, e))?;
                let text = vars.get(input).map(|v| v.as_text()).unwrap_or_default();
                if let Some(c) = re.captures(&text) {
                    if let Some(m) = c.get(1) {
                        vars.insert(as_var.clone(), RuleValue::Text(m.as_str().to_string()));
                    }
                }
            }
            RuleStep::RegexFindAll { input, pattern, as_var } => {
                let re = regex::Regex::new(pattern)
                    .map_err(|e| format!("bad regex {:?}: {}", pattern, e))?;
                let text = vars.get(input).map(|v| v.as_text()).unwrap_or_default();
                let mut found = Vec::new();
                for c in re.captures_iter(&text) {
                    if let Some(m) = c.get(1) {
                        let s = m.as_str().to_string();
                        if !found.contains(&s) {
                            found.push(s);
                        }
                    }
                }
                vars.insert(as_var.clone(), RuleValue::List(found));
            }
            RuleStep::BuildStream {
                url: url_tmpl,
                quality,
                container,
                is_audio_only,
            } => {
                let resolved_url = interpolate(url_tmpl, &vars);
                if resolved_url.is_empty() {
                    continue; // skip silently — variable not populated
                }
                let stream = if *is_audio_only {
                    mk_audio_stream(resolved_url, quality.clone(), container)
                } else {
                    super::extractor::mk_muxed_stream(
                        resolved_url,
                        quality.clone(),
                        container,
                        None,
                    )
                };
                streams.push(stream);
            }
            RuleStep::SetTitle { value } => {
                let v = interpolate(value, &vars);
                if !v.is_empty() { title = Some(v); }
            }
            RuleStep::SetThumbnail { value } => {
                let v = interpolate(value, &vars);
                if !v.is_empty() { thumbnail = Some(v); }
            }
            RuleStep::SetAuthor { value } => {
                let v = interpolate(value, &vars);
                if !v.is_empty() { author = Some(v); }
            }
        }
    }

    Ok(VideoInfoResult {
        title: title.unwrap_or_else(|| rule.platform.clone()),
        thumbnail_url: thumbnail,
        platform: rule.platform.clone(),
        duration_seconds: None,
        author,
        streams,
    })
}

/// Replace `{{name}}` and `{{name[i]}}` occurrences in `template` with
/// values from `vars`. Unknown vars collapse to an empty string.
fn interpolate(template: &str, vars: &HashMap<String, RuleValue>) -> String {
    let re = regex::Regex::new(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)(?:\[(\d+)\])?\s*\}\}")
        .expect("interpolation regex");
    let mut out = String::with_capacity(template.len());
    let mut last = 0usize;
    for m in re.captures_iter(template) {
        let full = m.get(0).unwrap();
        out.push_str(&template[last..full.start()]);
        let name = m.get(1).unwrap().as_str();
        let idx = m.get(2).and_then(|g| g.as_str().parse::<usize>().ok());
        let replacement = match (vars.get(name), idx) {
            (Some(v), Some(i)) => v.indexed(i).unwrap_or_default(),
            (Some(v), None) => v.as_text(),
            _ => String::new(),
        };
        out.push_str(&replacement);
        last = full.end();
    }
    out.push_str(&template[last..]);
    out
}

fn mk_audio_stream(url: String, quality: String, container: &str) -> StreamResult {
    StreamResult {
        url,
        quality,
        format: container.to_uppercase(),
        container: Some(container.to_lowercase()),
        width: None,
        height: None,
        fps: None,
        video_codec: None,
        audio_codec: Some(container.to_lowercase()),
        bitrate_kbps: None,
        file_size_bytes: None,
        has_video: false,
        has_audio: true,
        is_audio_only: true,
        is_hdr: false,
    }
}
