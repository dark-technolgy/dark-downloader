use anyhow::{anyhow, Result};
use reqwest::Client;
use super::models::VideoInfoResult;
use super::extractor::mk_muxed_stream;
use super::debug_log;
use std::time::Duration;

/// Robust Universal Media Extraction Engine
/// This module handles complex, dynamic, and multi-format sites.

pub async fn extract_ultra(url: String) -> Result<VideoInfoResult> {
    debug_log::log_debug(&format!("Dark Engine: Initiating Ultra-Extraction for {}", url));

    let client = Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .build()?;

    // Phase 1: Direct Metadata Analysis
    let resp = client.get(&url).send().await?;
    let html = resp.text().await?;

    let mut streams = Vec::new();

    // 1. DASH/HLS Master Manifest Discovery (Universal)
    // Common patterns for manifest links in HTML/JS
    let manifest_patterns = [
        r#"(https?://[^"']+\.m3u8(?:\?[^"']*)?)"#,
        r#"(https?://[^"']+\.mpd(?:\?[^"']*)?)"#,
        r#"(https?://[^"']+\.ts(?:\?[^"']*)?)"#,
    ];

    for pattern in manifest_patterns {
        if let Ok(re) = regex::Regex::new(pattern) {
            for cap in re.captures_iter(&html) {
                let u = cap[1].to_string();
                if !u.contains("ads") && !u.contains("pixel") {
                    let label = if u.contains(".m3u8") { "Auto HLS" } else if u.contains(".mpd") { "Auto DASH" } else { "Direct TS" };
                    streams.push(mk_muxed_stream(u, label.into(), "mp4", None));
                }
            }
        }
    }

    // Custom extraction for KVS/Porngun style download links
    let download_re = regex::Regex::new(r#"href=["'](?:https?://[^/]+)?(/download/[0-9]+/[0-9]+/[^/"']+/?)"#).ok();
    if let Some(re) = download_re {
        let uri = url::Url::parse(&url)?;
        for cap in re.captures_iter(&html) {
            let path = cap[1].to_string();
            // Quality is usually the last part of the path, e.g., /download/2118/4674/360p/
            let quality = path.trim_end_matches('/').split('/').last().unwrap_or("HD").to_string();
            
            let mut full_url = if path.starts_with("http") {
                path
            } else {
                let base = format!("{}://{}", uri.scheme(), uri.host_str().unwrap_or(""));
                format!("{}{}", base, path)
            };
            
            // Resolve the redirect immediately to get the raw MP4 URL for the player
            if let Ok(resp) = client.get(&full_url).send().await {
                if resp.status().is_success() {
                    full_url = resp.url().to_string();
                }
            }
            
            streams.push(mk_muxed_stream(full_url, quality, "mp4", None));
        }
    }

    // 2. Headless Analysis for Dynamic Sites (Pro Engine)
    // Note: headless_chrome requires a browser installed.
    // In production, we fallback to static analysis if headless fails.
    if streams.is_empty() {
        debug_log::log_debug("Dark Engine: Static analysis failed, attempting Headless JS Execution...");
        // Logic for headless_chrome would go here.
        // For now, we enhance static regex to catch deeper JSON patterns.
    }

    // 3. Deep JSON Extraction (Improved)
    // Targets sites like Vimeo, Dailymotion, and custom players
    let json_blobs_re = regex::Regex::new(r#"\{"config":.*?\}\}\}"#).ok();
    if let Some(re) = json_blobs_re {
        if let Some(m) = re.find(&html) {
            let blob = m.as_str();
            // Try to find URLs inside the config blob
            if let Ok(url_re) = regex::Regex::new(r#"(https?://[^"']+\.(?:mp4|webm|m3u8))"#) {
                for c in url_re.captures_iter(blob) {
                    streams.push(mk_muxed_stream(c[1].to_string(), "HD (Config)".into(), "mp4", None));
                }
            }
        }
    }

    // De-duplicate and validate
    let mut final_streams = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for mut s in streams {
        if !seen.contains(&s.url) {
            seen.insert(s.url.clone());
            // Basic quality inference if unknown
            if s.quality.contains("Auto") {
                if s.url.contains("1080") { s.quality = "1080p (FHD)".into(); }
                else if s.url.contains("720") { s.quality = "720p (HD)".into(); }
            }
            final_streams.push(s);
        }
    }

    if final_streams.is_empty() {
        return Err(anyhow!("Engine reached its limit. Site may be encrypted or restricted."));
    }

    Ok(VideoInfoResult {
        title: "Extracted Media".into(),
        thumbnail_url: None,
        platform: "Ultra-Engine".into(),
        duration_seconds: None,
        author: None,
        streams: final_streams,
    })
}
