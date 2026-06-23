use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use regex::Regex;
use std::collections::HashSet;

struct Blocker {
    domains: HashSet<String>,
    patterns: Vec<Regex>,
}

static ENGINE: Lazy<RwLock<Blocker>> = Lazy::new(|| {
    RwLock::new(Blocker {
        domains: HashSet::new(),
        patterns: Vec::new(),
    })
});

#[frb(sync)]
pub fn rust_init_adblocker(rules: Vec<String>) {
    let mut domains = HashSet::new();
    let mut patterns = Vec::new();

    for rule in rules {
        if rule.starts_with("||") && rule.ends_with("^") {
            let domain = rule.trim_start_matches("||").trim_end_matches("^");
            domains.insert(domain.to_string());
        } else if let Ok(re) = Regex::new(&rule.replace("*", ".*")) {
            patterns.push(re);
        }
    }

    let mut engine = ENGINE.write();
    engine.domains = domains;
    engine.patterns = patterns;
}

#[frb(sync)]
pub fn rust_should_block_url(url: String) -> bool {
    let engine = ENGINE.read();

    // 1. فحص النطاق المباشر (سريع جداً)
    if let Ok(parsed_url) = url::Url::parse(&url) {
        if let Some(host) = parsed_url.host_str() {
            if engine.domains.contains(host) {
                return true;
            }
        }
    }

    // 2. فحص الأنماط (Regex)
    for re in &engine.patterns {
        if re.is_match(&url) {
            return true;
        }
    }

    false
}

#[frb(sync)]
pub fn rust_get_default_ad_rules() -> Vec<String> {
    vec![
        "doubleclick.net".to_string(),
        "googleadservices.com".to_string(),
        "googlesyndication.com".to_string(),
        "popads.net".to_string(),
        "popcash.net".to_string(),
        "adservice.google.com".to_string(),
        "*.ads.*".to_string(),
        "*/ads/*".to_string(),
        "analytics.google.com".to_string(),
    ]
}
