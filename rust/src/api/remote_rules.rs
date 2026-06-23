use anyhow::Result;
use flutter_rust_bridge::frb;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformRule {
    pub platform: String,
    pub version: u32,
    pub patterns: HashMap<String, String>,
}

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
    // نستخدم مجلد التحميلات أو مجلد بيانات التطبيق لتخزين القواعد
    let mut p =
        PathBuf::from(super::downloader::get_downloads_dir().unwrap_or_else(|_| ".".into()));
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

/// تحديث القواعد من رابط خارجي (GitHub Gist مثلاً)
#[frb]
pub async fn rust_sync_remote_rules(url: String) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| e.to_string())?;

    let resp = client.get(url).send().await.map_err(|e| e.to_string())?;
    let status = resp.status();
    if !status.is_success() {
        return Err(format!(
            "rules URL returned HTTP {} (body is not JSON)",
            status.as_u16()
        ));
    }
    let new_registry: RulesRegistry = resp.json().await.map_err(|e| e.to_string())?;

    {
        let mut reg = registry().lock();
        // تحديث القواعد التي تملك إصداراً أحدث فقط
        for new_rule in new_registry.rules {
            if let Some(old_rule) = reg
                .rules
                .iter_mut()
                .find(|r| r.platform == new_rule.platform)
            {
                if new_rule.version > old_rule.version {
                    *old_rule = new_rule;
                }
            } else {
                reg.rules.push(new_rule);
            }
        }
        reg.last_updated = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        save_local_rules(&reg).map_err(|e| e.to_string())?;
    }

    Ok(())
}

/// جلب قيمة قاعدة معينة لمنصة محددة
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
    format!(
        "Total Rules: {}, Last Sync: {}",
        reg.rules.len(),
        reg.last_updated
    )
}
