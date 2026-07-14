#![allow(dead_code)]
// Reserve YouTube cipher / innertube helpers for future or non-Android paths; many are unused in current pipeline.

use super::debug_log;
use super::models::{
    ExtractionResult, PlaylistItem, PlaylistResult, StreamResult, VideoInfoResult,
};
use ahash::AHashMap;
use anyhow::{anyhow, Result};
use once_cell::sync::OnceCell;
use reqwest::Client;
use serde_json::{json, Value};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};
use std::time::Duration;

static RE_VISITOR_DATA_HTML: LazyLock<regex::Regex> = LazyLock::new(|| {
    regex::Regex::new(r#""visitorData"\s*:\s*"([^"]+)""#).expect("RE_VISITOR_DATA_HTML")
});
static RE_N_QUERY: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"[?&]n=([^&]+)").expect("RE_N_QUERY"));
static RE_N_REPLACE: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"([?&]n=)[^&]+").expect("RE_N_REPLACE"));
static RE_YOUTUBE_ID_IN_URL: LazyLock<regex::Regex> = LazyLock::new(|| {
    regex::Regex::new(r"[?&/](?:v=|shorts/|embed/|live/)([a-zA-Z0-9_-]{11})")
        .expect("RE_YOUTUBE_ID_IN_URL")
});
static RE_CODECS_MIME: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r#"codecs=["']?([^"']+)["']?"#).expect("RE_CODECS_MIME"));
static RE_HEIGHT_QUALITY: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"(\d{3,4})\s*[pP]").expect("RE_HEIGHT_QUALITY"));
static RE_FPS_QUALITY: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"\d+[pP](\d{2,3})").expect("RE_FPS_QUALITY"));
static RE_BITRATE_QUALITY: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"(\d+)\s*kbps").expect("RE_BITRATE_QUALITY"));
static RE_SSSTIK_CDN: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r#"href="([^"]*tiktokcdn[^"]+)""#).expect("RE_SSSTIK_CDN"));
static RE_TIKTOK_VIDEO_ID: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"/video/(\d+)").expect("RE_TIKTOK_VIDEO_ID"));

// ─────────────────────────────────────────────────────────────────────────────
// Player cache — يُخزّن بيانات player.js حسب مسار الإصدار
// ─────────────────────────────────────────────────────────────────────────────

static PLAYER_CACHE: OnceLock<Mutex<AHashMap<String, Arc<PlayerFunctions>>>> = OnceLock::new();

fn player_cache() -> &'static Mutex<AHashMap<String, Arc<PlayerFunctions>>> {
    PLAYER_CACHE.get_or_init(|| Mutex::new(AHashMap::new()))
}

// visitorData مطلوب للعملاء الحديثة لتجاوز حجب po_token
static VISITOR_DATA_CACHE: OnceLock<Mutex<Option<(String, u64)>>> = OnceLock::new();

fn visitor_cache() -> &'static Mutex<Option<(String, u64)>> {
    VISITOR_DATA_CACHE.get_or_init(|| Mutex::new(None))
}

async fn get_visitor_data() -> Option<String> {
    // تحقق من الـ cache (صالح لساعة)
    {
        let cache = visitor_cache().lock().unwrap();
        if let Some((vd, ts)) = cache.as_ref() {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            if now.saturating_sub(*ts) < 3600 {
                return Some(vd.clone());
            }
        }
    }

    let vd = fetch_visitor_data().await?;
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    *visitor_cache().lock().unwrap() = Some((vd.clone(), ts));
    debug_log::log_debug(&format!(
        "visitor_data cached: {}...",
        &vd.chars().take(20).collect::<String>()
    ));
    Some(vd)
}

async fn fetch_visitor_data() -> Option<String> {
    // محاولة 1: من sw.js_data (أسرع)
    let client = browser_client().ok()?;
    if let Ok(resp) = client
        .get("https://www.youtube.com/sw.js_data")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await
    {
        if let Ok(text) = resp.text().await {
            let body = text.trim_start_matches(")]}'").trim();
            if let Ok(v) = serde_json::from_str::<Value>(body) {
                // البنية: [[["USER_ROUTE",...],...,[["visitorData","XXXX"]]]]
                if let Some(s) = find_visitor_data_in_json(&v) {
                    return Some(s);
                }
            }
        }
    }

    // محاولة 2: من صفحة /watch
    if let Ok(resp) = client
        .get("https://www.youtube.com/")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await
    {
        if let Ok(html) = resp.text().await {
            if let Some(c) = RE_VISITOR_DATA_HTML.captures(&html) {
                return Some(c[1].to_string());
            }
        }
    }
    None
}

fn find_visitor_data_in_json(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => None::<String>.or_else(|| {
            if s.len() > 20 && s.starts_with("Cg") {
                Some(s.clone())
            } else {
                None
            }
        }),
        Value::Array(arr) => {
            for (i, item) in arr.iter().enumerate() {
                if let Value::String(k) = item {
                    if k == "visitorData" {
                        if let Some(Value::String(v)) = arr.get(i + 1) {
                            return Some(v.clone());
                        }
                    }
                }
                if let Some(r) = find_visitor_data_in_json(item) {
                    return Some(r);
                }
            }
            None
        }
        Value::Object(m) => {
            if let Some(Value::String(s)) = m.get("visitorData") {
                return Some(s.clone());
            }
            for (_, vv) in m {
                if let Some(r) = find_visitor_data_in_json(vv) {
                    return Some(r);
                }
            }
            None
        }
        _ => None,
    }
}

fn extract_sts_from_player_js(js: &str) -> Option<u32> {
    for pat in &[
        r#"signatureTimestamp\s*:\s*(\d+)"#,
        r#""sts"\s*:\s*(\d+)"#,
        r#"sts\s*:\s*(\d+)"#,
    ] {
        if let Ok(re) = regex::Regex::new(pat) {
            if let Some(c) = re.captures(js) {
                if let Ok(v) = c[1].parse::<u32>() {
                    return Some(v);
                }
            }
        }
    }
    None
}

struct PlayerFunctions {
    decipher_ops: Vec<DecipherOp>, // Rust-native ops (primary)
    decipher_fn_name: String,      // rquickjs fallback
    n_fn_name: String,
    player_js: String,
    sts: Option<u32>, // signatureTimestamp — مطلوب للـ playbackContext
}

#[derive(Debug, Clone)]
enum DecipherOp {
    Reverse,
    Splice(usize),
    Swap(usize),
}

// ─────────────────────────────────────────────────────────────────────────────
// نقطة الدخول
// ─────────────────────────────────────────────────────────────────────────────

pub async fn extract(url: String) -> Result<ExtractionResult, String> {
    let (url, bypass_blocks) = _unpack_bypass(&url);

    // Check if it's a playlist URL
    if url.contains("list=") || url.contains("/playlist") {
        if let Ok(playlist) = extract_playlist(&url).await {
            return Ok(ExtractionResult::Playlist(playlist));
        }
    }

    match extract_with_options(&url, bypass_blocks).await {
        Ok(v) => Ok(ExtractionResult::Video(v)),
        Err(native_err) => {
            // Cascade layer 1: remote rule pack (works on every platform,
            // Android included, because it's pure data + regex — no external
            // binary needed). This is what makes Android self-healing.
            match super::remote_rules::extract_via_rules(&url).await {
                Ok(v) if !v.streams.is_empty() => {
                    debug_log::log_debug(&format!(
                        "Native extractor failed ({}); satisfied by remote rules",
                        native_err
                    ));
                    return Ok(ExtractionResult::Video(v));
                }
                Ok(_) => {
                    debug_log::log_debug(
                        "remote rules produced no streams; trying yt-dlp fallback if available",
                    );
                }
                Err(rules_err) => {
                    debug_log::log_debug(&format!(
                        "remote rules did not match ({}); trying yt-dlp fallback if available",
                        rules_err
                    ));
                }
            }

            // Cascade layer 2: yt-dlp binary (desktop-only). Community-maintained,
            // survives most upstream platform changes (cipher rotations, audio-
            // protection, API deprecations) between our app releases.
            if super::ytdlp_wrapper::is_ytdlp_available() {
                debug_log::log_debug(&format!(
                    "Native extractor failed ({}); falling back to yt-dlp",
                    native_err
                ));
                match super::ytdlp_wrapper::extract_via_ytdlp(&url).await {
                    Ok(v) => Ok(ExtractionResult::Video(v)),
                    Err(ytdlp_err) => Err(format!(
                        "Native: {} | yt-dlp fallback: {}",
                        native_err, ytdlp_err
                    )),
                }
            } else {
                Err(native_err)
            }
        }
    }
}

async fn extract_playlist(url: &str) -> Result<PlaylistResult> {
    let client = browser_client()?;
    let html = client.get(url).send().await?.text().await?;

    // YouTube Playlist Extraction (Basic)
    if url.contains("youtube.com") {
        let title_re = regex::Regex::new(r#""title":"([^"]+)"#).unwrap();
        let title = title_re
            .captures(&html)
            .map(|c| c[1].to_string())
            .unwrap_or_else(|| "YouTube Playlist".to_string());

        let mut items = Vec::new();
        let item_re =
            regex::Regex::new(r#"/watch\?v=([a-zA-Z0-9_-]{11})[^"]*index=(\d+)"#).unwrap();
        let mut seen = std::collections::HashSet::new();

        for cap in item_re.captures_iter(&html) {
            let id = cap[1].to_string();
            if seen.contains(&id) {
                continue;
            }
            seen.insert(id.clone());

            items.push(PlaylistItem {
                url: format!("https://www.youtube.com/watch?v={}", id),
                title: format!("Video #{}", cap[2].to_string()),
                thumbnail_url: Some(format!("https://img.youtube.com/vi/{}/hqdefault.jpg", id)),
                duration_seconds: None,
            });
        }

        if items.is_empty() {
            return Err(anyhow!("No items found in playlist"));
        }

        return Ok(PlaylistResult {
            title,
            author: None,
            items,
        });
    }

    Err(anyhow!("Platform not supported for playlist extraction"))
}

pub async fn extract_with_options(
    url: &str,
    bypass_blocks: bool,
) -> Result<VideoInfoResult, String> {
    let platform = detect_platform(url);
    debug_log::log_debug(&format!(
        "Extractor: url={} platform={} bypass={}",
        url, platform, bypass_blocks
    ));

    let mut result = match platform.as_str() {
        "YouTube" => extract_youtube(url).await,
        "Vimeo" => extract_vimeo(url).await,
        "TikTok" => extract_tiktok(url).await,
        "Instagram" => extract_instagram(url).await,
        "Twitter/X" => extract_twitter(url).await,
        "Dailymotion" => extract_dailymotion(url).await,
        "Reddit" => extract_reddit(url).await,
        "Rumble" => extract_rumble(url).await,
        "SoundCloud" => extract_soundcloud(url).await,
        "Twitch" => extract_twitch(url).await,
        "Eporner" => extract_eporner(url).await,
        _ => {
            if bypass_blocks {
                extract_generic_recursive(url, &platform, 0).await
            } else {
                extract_generic(url, &platform).await
            }
        }
    };

    // محاولة الاستخراج الشامل (Generic) من أي موقع إذا فشل المستخرج المخصص
    if result.is_err() && platform.as_str() != "Unknown" {
        debug_log::log_debug(&format!(
            "Built-in extractor failed for {}, trying generic fallback (bypass={})",
            url, bypass_blocks
        ));

        // محاولة أولى بالوضع المختار
        let generic_res = if bypass_blocks {
            extract_generic_recursive(url, "Unknown", 0).await
        } else {
            extract_generic(url, "Unknown").await
        };

        if let Ok(res) = generic_res {
            result = Ok(res);
        } else if !bypass_blocks {
            debug_log::log_debug("Generic failed, retrying WITH bypass automatically...");
            if let Ok(res) = extract_generic_recursive(url, "Unknown", 0).await {
                result = Ok(res);
            }
        }
    }

    result.map_err(|e| e.to_string())
}

fn _unpack_bypass(packed: &str) -> (String, bool) {
    if packed.contains("|||BYPASS:true") {
        return (packed.replace("|||BYPASS:true", ""), true);
    }
    (packed.to_string(), false)
}

fn detect_platform(url: &str) -> String {
    let lower = url.to_lowercase();
    if lower.contains("youtube.com") || lower.contains("youtu.be") {
        return "YouTube".into();
    }
    if lower.contains("vimeo.com") {
        return "Vimeo".into();
    }
    if lower.contains("tiktok.com") {
        return "TikTok".into();
    }
    if lower.contains("instagram.com") {
        return "Instagram".into();
    }
    if lower.contains("twitter.com") || lower.contains("x.com") {
        return "Twitter/X".into();
    }
    if lower.contains("facebook.com") || lower.contains("fb.watch") {
        return "Facebook".into();
    }
    if lower.contains("dailymotion.com") {
        return "Dailymotion".into();
    }
    if lower.contains("soundcloud.com") {
        return "SoundCloud".into();
    }
    if lower.contains("twitch.tv") {
        return "Twitch".into();
    }
    if lower.contains("reddit.com") {
        return "Reddit".into();
    }
    if lower.contains("rumble.com") {
        return "Rumble".into();
    }
    if lower.contains("pinterest.com") {
        return "Pinterest".into();
    }
    if lower.contains("vk.com") {
        return "VK".into();
    }
    if lower.contains("ok.ru") {
        return "Odnoklassniki".into();
    }
    if lower.contains("bilibili.com") {
        return "Bilibili".into();
    }
    if lower.contains("eporner.com") {
        return "Eporner".into();
    }
    if lower.contains("pornhub.com") {
        return "Pornhub".into();
    }
    if lower.contains("xvideos.com") {
        return "XVideos".into();
    }
    if lower.contains("xhamster.com") {
        return "xHamster".into();
    }
    "Unknown".into()
}

/// عميل HTTP واحد مُعاد استخدامه لكل الاستخراج — تقليل تكلفة TCP/TLS والذاكرة.
static SHARED_BROWSER_CLIENT: OnceCell<Client> = OnceCell::new();

fn browser_client() -> Result<Client> {
    SHARED_BROWSER_CLIENT
        .get_or_try_init(|| {
            Client::builder()
                .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36")
                .timeout(Duration::from_secs(20))
                .danger_accept_invalid_certs(true) // لتجاوز مشاكل البروكسي وبعض جدران الحماية
                .pool_max_idle_per_host(8)
                .build()
                .map_err(|e| anyhow!("reqwest browser_client: {e}"))
        })
        .map(|c| c.clone())
}

fn browser_client_with_proxy(proxy_url: Option<&str>) -> Result<Client> {
    if proxy_url.is_none() {
        return browser_client();
    }
    let mut builder = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36")
        .timeout(Duration::from_secs(20))
        .danger_accept_invalid_certs(true)
        .pool_max_idle_per_host(8);

    if let Some(proxy) = proxy_url {
        match reqwest::Proxy::https(proxy) {
            Ok(p) => {
                builder = builder.proxy(p);
            }
            Err(e) => {
                debug_log::log_debug(&format!("proxy error: {}", e));
            }
        }
    }

    Ok(builder.build()?)
}

static EXTRACTION_PROXIES: &[&str] = &[
    "https://api.codetabs.com/v1/proxy?quest=",
    "https://api.allorigins.win/get?url=",
    "https://thingproxy.freeboard.io/fetch/",
    "https://corsproxy.io/?",
    "https://proxy.zerobytes.site/?url=",
];

async fn fetch_html_with_bypass(url: &str) -> Result<String> {
    let client = browser_client()?;

    // محاولة 1: طلب مباشر
    match client
        .get(url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            return Ok(resp.text().await?);
        }
        _ => {
            debug_log::log_debug(&format!(
                "Direct fetch failed for {}, trying bypass proxies...",
                url
            ));
        }
    }

    // محاولة 2: استخدام البروكسيات العامة (Web Proxy Bridge)
    for proxy_base in EXTRACTION_PROXIES {
        let proxy_url = format!("{}{}", proxy_base, urlencoding::encode(url));
        if let Ok(resp) = client.get(&proxy_url).send().await {
            if resp.status().is_success() {
                let text = resp.text().await?;
                // AllOrigins يُرجع JSON يحتوي على الحقل "contents"
                if proxy_base.contains("allorigins") {
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                        if let Some(c) = json["contents"].as_str() {
                            debug_log::log_debug("Bypass success via AllOrigins");
                            return Ok(c.to_string());
                        }
                    }
                } else {
                    debug_log::log_debug(&format!("Bypass success via {}", proxy_base));
                    return Ok(text);
                }
            }
        }
    }

    Err(anyhow::anyhow!("فشل الوصول للموقع حتى مع استخدام البروكسي. قد يكون الموقع محمياً بشكل متقدم أو الرابط غير صحيح."))
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure-Rust decipher — أسرع وأكثر موثوقية من rquickjs لهذا الغرض
// ─────────────────────────────────────────────────────────────────────────────

fn extract_fn_body(js: &str, fn_name: &str) -> Option<String> {
    let p1 = format!(r"(?:var\s+)?{}\s*=\s*function\s*\(", regex::escape(fn_name));
    let p2 = format!(r"{}\s*:\s*function\s*\(", regex::escape(fn_name));
    for pat in &[p1, p2] {
        if let Ok(re) = regex::Regex::new(pat) {
            if let Some(m) = re.find(js) {
                let rest = &js[m.start()..];
                if let Some(brace_pos) = rest.find('{') {
                    if let Some(body) = extract_balanced_braces(&rest[brace_pos..]) {
                        return Some(body.to_string());
                    }
                }
            }
        }
    }
    None
}

fn parse_decipher_ops(js: &str, fn_name: &str) -> Vec<DecipherOp> {
    let fn_body = match extract_fn_body(js, fn_name) {
        Some(b) => b,
        None => {
            debug_log::log_debug(&format!("decipher: fn_body not found for {}", fn_name));
            return vec![];
        }
    };
    // اسم الـ helper قد يكون أطول في إصدارات حديثة
    let helper_re = match regex::Regex::new(r"(?:^|[^\w$])([a-zA-Z$_][\w$]{0,10})\.[\w$]+\(a\b") {
        Ok(r) => r,
        Err(_) => return vec![],
    };
    let helper_name = match helper_re.captures(&fn_body) {
        Some(c) => c[1].to_string(),
        None => {
            debug_log::log_debug("decipher: helper name not found");
            return vec![];
        }
    };
    debug_log::log_debug(&format!("decipher: helper_name={}", helper_name));

    // الـ helper قد يكون var أو داخل object حرفياً بدون var
    let helper_pat = format!(r"(?:var\s+)?{}\s*=\s*\{{", regex::escape(&helper_name));
    let helper_obj_re = match regex::Regex::new(&helper_pat) {
        Ok(r) => r,
        Err(_) => return vec![],
    };
    let helper_body = match helper_obj_re
        .find(js)
        .and_then(|m| extract_balanced_braces(&js[m.end() - 1..]))
    {
        Some(b) => b.to_string(),
        None => {
            debug_log::log_debug("decipher: helper body not found");
            return vec![];
        }
    };

    // أنماط تطابق التعريفات بأكثر من صيغة
    let rev_re =
        regex::Regex::new(r"([\w$]+)\s*:\s*function\s*\([^)]*\)\s*\{[^}]*\.reverse\s*\(").ok();
    let spl_re =
        regex::Regex::new(r"([\w$]+)\s*:\s*function\s*\([^)]*,[^)]+\)\s*\{[^}]*\.splice\s*\(").ok();
    // swap يُكتب إما بـ var أو بالتبديل المباشر
    let swp1 = regex::Regex::new(
        r"([\w$]+)\s*:\s*function\s*\([^)]*,[^)]+\)\s*\{\s*var\s+[\w$]+\s*=\s*a\[0\]",
    )
    .ok();
    let swp2 =
        regex::Regex::new(r"([\w$]+)\s*:\s*function\s*\([^)]*,[^)]+\)\s*\{\s*a\[0\]\s*=").ok();

    let reverse_fn = rev_re
        .as_ref()
        .and_then(|r| r.captures(&helper_body))
        .map(|c| c[1].to_string());
    let splice_fn = spl_re
        .as_ref()
        .and_then(|r| r.captures(&helper_body))
        .map(|c| c[1].to_string());
    let swap_fn = swp1
        .as_ref()
        .and_then(|r| r.captures(&helper_body))
        .or_else(|| swp2.as_ref().and_then(|r| r.captures(&helper_body)))
        .map(|c| c[1].to_string());

    debug_log::log_debug(&format!(
        "decipher: rev={:?} spl={:?} swp={:?}",
        reverse_fn, splice_fn, swap_fn
    ));

    let call_pat = format!(
        r"{}\.([\w$]+)\(a\s*(?:,\s*(\d+))?\)",
        regex::escape(&helper_name)
    );
    let call_re = match regex::Regex::new(&call_pat) {
        Ok(r) => r,
        Err(_) => return vec![],
    };

    let mut ops = Vec::new();
    for cap in call_re.captures_iter(&fn_body) {
        let method = cap[1].to_string();
        let n: usize = cap
            .get(2)
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(0);
        if Some(&method) == reverse_fn.as_ref() {
            ops.push(DecipherOp::Reverse);
        } else if Some(&method) == splice_fn.as_ref() {
            ops.push(DecipherOp::Splice(n));
        } else if Some(&method) == swap_fn.as_ref() {
            ops.push(DecipherOp::Swap(n));
        }
    }
    debug_log::log_debug(&format!("decipher: parsed {} ops", ops.len()));
    ops
}

fn apply_decipher_ops(sig: &str, ops: &[DecipherOp]) -> String {
    let mut chars: Vec<char> = sig.chars().collect();
    for op in ops {
        match op {
            DecipherOp::Reverse => chars.reverse(),
            DecipherOp::Splice(n) => {
                chars.drain(..*n);
            }
            DecipherOp::Swap(n) => {
                let len = chars.len();
                if len > 0 {
                    chars.swap(0, n % len);
                }
            }
        }
    }
    chars.iter().collect()
}

// ─────────────────────────────────────────────────────────────────────────────
// Stream metadata helpers
//
// Centralise the construction of `StreamResult` so every extractor produces
// the richest possible metadata (resolution, fps, codec, bitrate, container)
// instead of dropping fields. Downstream UIs rely on these to present a
// premium quality picker (sorted lists, codec badges, filter chips).
// ─────────────────────────────────────────────────────────────────────────────

enum CodecKind {
    Video(String),
    Audio(String),
    Unknown,
}

fn classify_codec(c: &str) -> CodecKind {
    let l = c.trim().to_lowercase();
    if l.starts_with("avc") || l.starts_with("h264") {
        return CodecKind::Video("avc1".into());
    }
    if l.starts_with("hev") || l.starts_with("hvc") || l.starts_with("h265") {
        return CodecKind::Video("hevc".into());
    }
    if l.starts_with("vp9") {
        return CodecKind::Video("vp9".into());
    }
    if l.starts_with("vp8") {
        return CodecKind::Video("vp8".into());
    }
    if l.starts_with("av01") || l.starts_with("av1") {
        return CodecKind::Video("av01".into());
    }
    if l.starts_with("mp4a") {
        return CodecKind::Audio("aac".into());
    }
    if l.starts_with("opus") {
        return CodecKind::Audio("opus".into());
    }
    if l.starts_with("mp3") {
        return CodecKind::Audio("mp3".into());
    }
    if l.starts_with("ac-3") || l.starts_with("ac3") {
        return CodecKind::Audio("ac3".into());
    }
    if l.starts_with("ec-3") || l.starts_with("ec3") {
        return CodecKind::Audio("eac3".into());
    }
    if l.starts_with("vorbis") {
        return CodecKind::Audio("vorbis".into());
    }
    CodecKind::Unknown
}

fn parse_mime_container(mime: &str) -> Option<String> {
    let l = mime.to_lowercase();
    if l.contains("webm") {
        Some("webm".into())
    } else if l.contains("mp4") {
        Some("mp4".into())
    } else if l.contains("3gpp") {
        Some("3gp".into())
    } else if l.contains("mpegurl") {
        Some("m3u8".into())
    } else {
        None
    }
}

fn parse_codecs_from_mime(mime: &str) -> (Option<String>, Option<String>) {
    let codecs = match RE_CODECS_MIME.captures(mime) {
        Some(c) => c[1].to_string(),
        None => return (None, None),
    };
    let mut video_codec = None;
    let mut audio_codec = None;
    for part in codecs.split(',') {
        match classify_codec(part) {
            CodecKind::Video(name) if video_codec.is_none() => {
                video_codec = Some(name);
            }
            CodecKind::Audio(name) if audio_codec.is_none() => {
                audio_codec = Some(name);
            }
            _ => {}
        }
    }
    (video_codec, audio_codec)
}

fn parse_height_from_quality(q: &str) -> Option<u32> {
    RE_HEIGHT_QUALITY.captures(q)?.get(1)?.as_str().parse().ok()
}

fn parse_fps_from_quality(q: &str) -> Option<f32> {
    RE_FPS_QUALITY.captures(q)?.get(1)?.as_str().parse().ok()
}

fn parse_bitrate_from_quality(q: &str) -> Option<u32> {
    RE_BITRATE_QUALITY
        .captures(q)?
        .get(1)?
        .as_str()
        .parse()
        .ok()
}

fn infer_width(height: Option<u32>) -> Option<u32> {
    height.map(|h| ((h as f32) * 16.0 / 9.0).round() as u32)
}

fn default_audio_codec_for(container: &str) -> Option<String> {
    match container.to_lowercase().as_str() {
        "mp3" => Some("mp3".into()),
        "m4a" | "aac" | "mp4" => Some("aac".into()),
        "opus" => Some("opus".into()),
        "webm" => Some("opus".into()),
        _ => None,
    }
}

pub(crate) fn mk_muxed_stream(
    url: String,
    quality: String,
    container: &str,
    file_size: Option<u64>,
) -> StreamResult {
    let height = parse_height_from_quality(&quality);
    let fps = parse_fps_from_quality(&quality);
    let bitrate = parse_bitrate_from_quality(&quality);
    StreamResult {
        url,
        quality: quality.clone(),
        format: container.to_uppercase(),
        container: Some(container.to_lowercase()),
        width: infer_width(height),
        height,
        fps,
        video_codec: None,
        audio_codec: default_audio_codec_for(container),
        bitrate_kbps: bitrate,
        file_size_bytes: file_size,
        has_video: true,
        has_audio: true,
        is_audio_only: false,
        is_hdr: quality.to_uppercase().contains("HDR"),
    }
}

fn mk_audio_only_stream(
    url: String,
    quality: String,
    container: &str,
    bitrate_kbps: Option<u32>,
    file_size: Option<u64>,
) -> StreamResult {
    let br = bitrate_kbps.or_else(|| parse_bitrate_from_quality(&quality));
    StreamResult {
        url,
        quality,
        format: container.to_uppercase(),
        container: Some(container.to_lowercase()),
        width: None,
        height: None,
        fps: None,
        video_codec: None,
        audio_codec: default_audio_codec_for(container),
        bitrate_kbps: br,
        file_size_bytes: file_size,
        has_video: false,
        has_audio: true,
        is_audio_only: true,
        is_hdr: false,
    }
}

fn mk_yt_stream(f: &Value, url_str: String) -> StreamResult {
    let mime = f["mimeType"].as_str().unwrap_or("");
    let container = parse_mime_container(mime);
    let (video_codec, audio_codec) = parse_codecs_from_mime(mime);
    let is_audio = mime.starts_with("audio/");
    let has_video = !is_audio;
    let has_audio = is_audio || audio_codec.is_some();

    let width = f["width"].as_u64().map(|v| v as u32);
    let height = f["height"].as_u64().map(|v| v as u32);
    let fps = f["fps"]
        .as_u64()
        .map(|v| v as f32)
        .or_else(|| f["fps"].as_f64().map(|v| v as f32));
    let bitrate_kbps = f["averageBitrate"]
        .as_u64()
        .or_else(|| f["bitrate"].as_u64())
        .map(|v| (v / 1000) as u32);
    let file_size_bytes = f["contentLength"]
        .as_str()
        .and_then(|s| s.parse::<u64>().ok())
        .or_else(|| f["contentLength"].as_u64());

    let quality = if is_audio {
        match bitrate_kbps {
            Some(b) => format!("{}kbps", b),
            None => "audio".to_string(),
        }
    } else {
        f["qualityLabel"]
            .as_str()
            .or_else(|| f["quality"].as_str())
            .map(|s| s.to_string())
            .or_else(|| height.map(|h| format!("{}p", h)))
            .unwrap_or_else(|| "SD".to_string())
    };

    let format = container
        .clone()
        .map(|c| c.to_uppercase())
        .unwrap_or_else(|| "MP4".into());

    let is_hdr = f["qualityLabel"]
        .as_str()
        .map(|s| s.to_uppercase().contains("HDR"))
        .unwrap_or(false)
        || mime.to_uppercase().contains("HDR");

    StreamResult {
        url: url_str,
        quality,
        format,
        container,
        width,
        height,
        fps,
        video_codec,
        audio_codec,
        bitrate_kbps,
        file_size_bytes,
        has_video,
        has_audio,
        is_audio_only: is_audio,
        is_hdr,
    }
}

// 0 = muxed (audio + video), 1 = video-only, 2 = audio-only
fn stream_kind_priority(s: &StreamResult) -> u8 {
    if s.is_audio_only || (!s.has_video && s.has_audio) {
        2
    } else if s.has_video && s.has_audio {
        0
    } else {
        1
    }
}

fn final_sort(streams: &mut [StreamResult]) {
    streams.sort_by(|a, b| {
        stream_kind_priority(a)
            .cmp(&stream_kind_priority(b))
            .then_with(|| b.height.unwrap_or(0).cmp(&a.height.unwrap_or(0)))
            .then_with(|| {
                let fa = (a.fps.unwrap_or(0.0) * 100.0) as u32;
                let fb = (b.fps.unwrap_or(0.0) * 100.0) as u32;
                fb.cmp(&fa)
            })
            .then_with(|| {
                b.bitrate_kbps
                    .unwrap_or(0)
                    .cmp(&a.bitrate_kbps.unwrap_or(0))
            })
            .then_with(|| {
                b.file_size_bytes
                    .unwrap_or(0)
                    .cmp(&a.file_size_bytes.unwrap_or(0))
            })
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTube
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_youtube(url: &str) -> Result<VideoInfoResult> {
    let id = parse_youtube_id(url).ok_or_else(|| anyhow!("لم يتعرف على معرف الفيديو في الرابط"))?;
    debug_log::log_debug(&format!("==== extract_youtube id={} ====", id));

    // ─── STRATEGY 1: Android VR client (PRIMARY — direct URLs بدون N-transform) ──
    debug_log::log_debug("=== PRIMARY: Android VR innertube (no N-transform needed) ===");
    if let Ok(resp) = innertube_android_vr(&id).await {
        if youtube_has_direct_urls(&resp) {
            if let Ok(result) = youtube_build_result(&id, resp, None).await {
                if !result.streams.is_empty() {
                    debug_log::log_debug(&format!(
                        "✓ Android VR succeeded with {} streams",
                        result.streams.len()
                    ));
                    return Ok(result);
                }
            }
        } else {
            debug_log::log_debug("Android VR: no direct URLs");
        }
    }

    // ─── STRATEGY 2: iOS client (reliable, no N-transform) ──────────────
    debug_log::log_debug("=== FALLBACK 1: iOS innertube ===");
    if let Ok(resp) = innertube_ios(&id).await {
        if youtube_has_direct_urls(&resp) {
            if let Ok(result) = youtube_build_result(&id, resp, None).await {
                if !result.streams.is_empty() {
                    debug_log::log_debug(&format!(
                        "✓ iOS succeeded with {} streams",
                        result.streams.len()
                    ));
                    return Ok(result);
                }
            }
        }
    }

    // ─── STRATEGY 3: Android client ──────────────
    debug_log::log_debug("=== FALLBACK 2: Android innertube ===");
    if let Ok(resp) = innertube_android(&id).await {
        if youtube_has_direct_urls(&resp) {
            if let Ok(result) = youtube_build_result(&id, resp, None).await {
                if !result.streams.is_empty() {
                    debug_log::log_debug(&format!(
                        "✓ Android succeeded with {} streams",
                        result.streams.len()
                    ));
                    return Ok(result);
                }
            }
        }
    }

    // ─── STRATEGY 4: TV embedded client ──────────────
    debug_log::log_debug("=== FALLBACK 3: TV embedded innertube ===");
    if let Ok(resp) = innertube_tv_embedded(&id).await {
        if youtube_has_direct_urls(&resp) {
            if let Ok(result) = youtube_build_result(&id, resp, None).await {
                if !result.streams.is_empty() {
                    debug_log::log_debug(&format!(
                        "✓ TV embedded succeeded with {} streams",
                        result.streams.len()
                    ));
                    return Ok(result);
                }
            }
        }
    }

    // ─── STRATEGY 5: Piped (external proxy fallback) ──────────────
    debug_log::log_debug("=== FALLBACK 4: Piped external ===");
    if let Ok(result) = extract_via_piped_with_retry(&id, 2).await {
        if !result.streams.is_empty() {
            debug_log::log_debug(&format!(
                "✓ Piped succeeded with {} streams",
                result.streams.len()
            ));
            return Ok(result);
        }
    }

    // ─── STRATEGY 6: Invidious (external proxy fallback) ──────────────
    debug_log::log_debug("=== FALLBACK 5: Invidious external ===");
    if let Ok(result) = extract_via_invidious_with_retry(&id, 2).await {
        if !result.streams.is_empty() {
            debug_log::log_debug(&format!(
                "✓ Invidious succeeded with {} streams",
                result.streams.len()
            ));
            return Ok(result);
        }
    }

    debug_log::log_debug("✗ All 6 extraction strategies failed");
    Err(anyhow!(
        "تعذر استخراج الفيديو — قد يكون خاصاً أو محذوفاً أو مقيداً"
    ))
}

// وظائف مساعدة مع retry logic (أكثر موثوقية)
async fn extract_via_piped_with_retry(
    video_id: &str,
    max_attempts: usize,
) -> Result<VideoInfoResult> {
    for attempt in 0..max_attempts {
        debug_log::log_debug(&format!(
            "piped: attempt {} of {}",
            attempt + 1,
            max_attempts
        ));
        match extract_via_piped(video_id).await {
            Ok(result) if !result.streams.is_empty() => return Ok(result),
            Err(e) => {
                if attempt < max_attempts - 1 {
                    let delay = std::time::Duration::from_millis(500 + (attempt as u64) * 300);
                    debug_log::log_debug(&format!("piped: retry after {:?}: {}", delay, e));
                    tokio::time::sleep(delay).await;
                }
            }
            Ok(_) => debug_log::log_debug("piped: got result but streams empty"),
        }
    }
    Err(anyhow!("piped: all attempts failed"))
}

async fn extract_via_invidious_with_retry(
    video_id: &str,
    max_attempts: usize,
) -> Result<VideoInfoResult> {
    for attempt in 0..max_attempts {
        debug_log::log_debug(&format!(
            "invidious: attempt {} of {}",
            attempt + 1,
            max_attempts
        ));
        match extract_via_invidious(video_id).await {
            Ok(result) if !result.streams.is_empty() => return Ok(result),
            Err(e) => {
                if attempt < max_attempts - 1 {
                    let delay = std::time::Duration::from_millis(500 + (attempt as u64) * 300);
                    debug_log::log_debug(&format!("invidious: retry after {:?}: {}", delay, e));
                    tokio::time::sleep(delay).await;
                }
            }
            Ok(_) => debug_log::log_debug("invidious: got result but streams empty"),
        }
    }
    Err(anyhow!("invidious: all attempts failed"))
}

// يستخدم Piped API — instances مفتوحة تُرجع روابط مباشرة
async fn extract_via_piped(video_id: &str) -> Result<VideoInfoResult> {
    let instances = [
        "https://api.piped.private.coffee",
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.adminforge.de",
        "https://api.piped.yt",
        "https://pipedapi.leptons.xyz",
        "https://pipedapi.reallyaweso.me",
        "https://pipedapi.r4fo.com",
        "https://pipedapi-libre.kavin.rocks",
        "https://api.piped.privacydev.net",
    ];
    let client = browser_client()?;
    let mut last_err = anyhow!("no piped instance reachable");

    for inst in &instances {
        let url = format!("{}/streams/{}", inst, video_id);
        debug_log::log_debug(&format!("piped: trying {}", inst));
        match client
            .get(&url)
            .timeout(std::time::Duration::from_secs(12))
            .send()
            .await
        {
            Ok(r) if !r.status().is_success() => {
                debug_log::log_debug(&format!("piped {} -> HTTP {}", inst, r.status()));
                last_err = anyhow!("HTTP {}", r.status());
                continue;
            }
            Err(e) => {
                debug_log::log_debug(&format!("piped {} -> network: {}", inst, e));
                last_err = anyhow!("network: {}", e);
                continue;
            }
            Ok(r) => match r.json::<Value>().await {
                Ok(data) => {
                    let title = data["title"]
                        .as_str()
                        .unwrap_or("YouTube Video")
                        .to_string();
                    let thumbnail = data["thumbnailUrl"]
                        .as_str()
                        .map(|s| s.to_string())
                        .or_else(|| {
                            Some(format!(
                                "https://img.youtube.com/vi/{}/hqdefault.jpg",
                                video_id
                            ))
                        });
                    let author = data["uploader"].as_str().map(|s| s.to_string());
                    let duration = data["duration"].as_u64().map(|d| d as u32);

                    // When Piped omits `videoOnly`, defaulting to `false` marks many adaptive
                    // (DASH) video-only URLs as "muxed" (`has_audio: true`). Downstream then
                    // skips merging separate audio for sub-480p runs — user gets silent video.
                    // If the API exposes separate `audioStreams`, assume missing `videoOnly` means
                    // DASH video-only; if there are no separate audio tracks, keep the old default
                    // (`false`) so lone progressive entries in `videoStreams` stay muxed.
                    let separate_audio_tracks = data["audioStreams"]
                        .as_array()
                        .map(|a| !a.is_empty())
                        .unwrap_or(false);

                    let mut streams = Vec::new();
                    if let Some(arr) = data["videoStreams"].as_array() {
                        for s in arr {
                            if let Some(u) = s["url"].as_str() {
                                let quality = s["quality"].as_str().unwrap_or("SD").to_string();
                                let mime = s["mimeType"].as_str().unwrap_or("");
                                let container =
                                    parse_mime_container(mime).unwrap_or_else(|| "mp4".into());
                                let (vcodec, acodec) = parse_codecs_from_mime(mime);
                                let width = s["width"].as_u64().map(|v| v as u32);
                                let height = s["height"]
                                    .as_u64()
                                    .map(|v| v as u32)
                                    .or_else(|| parse_height_from_quality(&quality));
                                let fps = s["fps"]
                                    .as_u64()
                                    .map(|v| v as f32)
                                    .or_else(|| parse_fps_from_quality(&quality));
                                let bitrate = s["bitrate"].as_u64().map(|v| (v / 1000) as u32);
                                let is_video_only =
                                    s["videoOnly"].as_bool().unwrap_or(separate_audio_tracks);
                                streams.push(StreamResult {
                                    url: u.to_string(),
                                    quality,
                                    format: container.to_uppercase(),
                                    container: Some(container),
                                    width,
                                    height,
                                    fps,
                                    video_codec: vcodec,
                                    audio_codec: if is_video_only {
                                        None
                                    } else {
                                        acodec.or_else(|| Some("aac".into()))
                                    },
                                    bitrate_kbps: bitrate,
                                    file_size_bytes: None,
                                    has_video: true,
                                    has_audio: !is_video_only,
                                    is_audio_only: false,
                                    is_hdr: false,
                                });
                            }
                        }
                    }
                    if let Some(arr) = data["audioStreams"].as_array() {
                        for s in arr {
                            if let Some(u) = s["url"].as_str() {
                                let bitrate_kbps =
                                    (s["bitrate"].as_u64().unwrap_or(0) / 1000) as u32;
                                let mime = s["mimeType"].as_str().unwrap_or("");
                                let container = parse_mime_container(mime).unwrap_or_else(|| {
                                    if mime.contains("opus") {
                                        "webm".into()
                                    } else {
                                        "m4a".into()
                                    }
                                });
                                streams.push(mk_audio_only_stream(
                                    u.to_string(),
                                    format!("{}kbps", bitrate_kbps),
                                    &container,
                                    if bitrate_kbps > 0 {
                                        Some(bitrate_kbps)
                                    } else {
                                        None
                                    },
                                    None,
                                ));
                            }
                        }
                    }

                    final_sort(&mut streams);

                    if !streams.is_empty() {
                        debug_log::log_debug(&format!(
                            "piped: success via {} ({} streams)",
                            inst,
                            streams.len()
                        ));
                        return Ok(VideoInfoResult {
                            title,
                            thumbnail_url: thumbnail,
                            platform: "YouTube".into(),
                            duration_seconds: duration,
                            author,
                            streams,
                        });
                    }
                }
                Err(e) => {
                    debug_log::log_debug(&format!("piped {} -> json error: {}", inst, e));
                    last_err = anyhow!("json: {}", e);
                }
            },
        }
    }
    Err(last_err)
}

// Invidious API — مستخرج بديل، يُرجع formatStreams + adaptiveFormats مع روابط مباشرة
async fn extract_via_invidious(video_id: &str) -> Result<VideoInfoResult> {
    let instances = [
        "https://inv.thepixora.com",
        "https://invidious.jing.rocks",
        "https://yewtu.be",
        "https://invidious.reallyaweso.me",
        "https://inv.nadeko.net",
        "https://invidious.privacyredirect.com",
        "https://iv.ggtyler.dev",
        "https://invidious.materialio.us",
        "https://invidious.io",
    ];
    let client = browser_client()?;
    let mut last_err = anyhow!("no invidious instance reachable");

    for inst in &instances {
        let url = format!("{}/api/v1/videos/{}", inst, video_id);
        debug_log::log_debug(&format!("invidious: trying {}", inst));
        let resp = match client
            .get(&url)
            .timeout(std::time::Duration::from_secs(12))
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            Ok(r) => {
                debug_log::log_debug(&format!("invidious {} -> HTTP {}", inst, r.status()));
                last_err = anyhow!("HTTP {}", r.status());
                continue;
            }
            Err(e) => {
                debug_log::log_debug(&format!("invidious {} -> network: {}", inst, e));
                last_err = anyhow!("network: {}", e);
                continue;
            }
        };
        let data: Value = match resp.json().await {
            Ok(d) => d,
            Err(e) => {
                debug_log::log_debug(&format!("invidious {} -> json: {}", inst, e));
                last_err = anyhow!("json: {}", e);
                continue;
            }
        };

        let title = data["title"]
            .as_str()
            .unwrap_or("YouTube Video")
            .to_string();
        let thumbnail = data["videoThumbnails"]
            .as_array()
            .and_then(|a| a.iter().max_by_key(|t| t["width"].as_u64().unwrap_or(0)))
            .and_then(|t| t["url"].as_str())
            .map(|s| s.to_string())
            .or_else(|| {
                Some(format!(
                    "https://img.youtube.com/vi/{}/hqdefault.jpg",
                    video_id
                ))
            });
        let author = data["author"].as_str().map(|s| s.to_string());
        let duration = data["lengthSeconds"].as_u64().map(|d| d as u32);

        let mut streams = Vec::new();
        if let Some(arr) = data["formatStreams"].as_array() {
            for s in arr {
                if let Some(u) = s["url"].as_str() {
                    let quality = s["qualityLabel"]
                        .as_str()
                        .or_else(|| s["quality"].as_str())
                        .unwrap_or("SD")
                        .to_string();
                    let container = s["container"].as_str().unwrap_or("mp4").to_string();
                    let size = s["size"]
                        .as_str()
                        .and_then(|v| v.parse::<u64>().ok())
                        .or_else(|| s["size"].as_u64());
                    streams.push(mk_muxed_stream(u.to_string(), quality, &container, size));
                }
            }
        }
        if let Some(arr) = data["adaptiveFormats"].as_array() {
            for s in arr {
                if let Some(u) = s["url"].as_str() {
                    let mime = s["type"].as_str().unwrap_or("");
                    let is_audio = mime.starts_with("audio/");
                    if !is_audio && !mime.starts_with("video/") {
                        continue;
                    }
                    let (vcodec, acodec) = parse_codecs_from_mime(mime);
                    let bitrate_raw = s["bitrate"]
                        .as_str()
                        .and_then(|v| v.parse::<u64>().ok())
                        .or_else(|| s["bitrate"].as_u64())
                        .unwrap_or(0);
                    let bitrate_kbps = if bitrate_raw > 0 {
                        Some((bitrate_raw / 1000) as u32)
                    } else {
                        None
                    };
                    let quality = if is_audio {
                        format!("{}kbps", bitrate_kbps.unwrap_or(0))
                    } else {
                        s["qualityLabel"]
                            .as_str()
                            .or_else(|| s["resolution"].as_str())
                            .unwrap_or("SD")
                            .to_string()
                    };
                    let container = s["container"]
                        .as_str()
                        .map(|s| s.to_string())
                        .or_else(|| parse_mime_container(mime))
                        .unwrap_or_else(|| if is_audio { "m4a".into() } else { "mp4".into() });
                    let width = s["width"].as_u64().map(|v| v as u32);
                    let height = s["height"]
                        .as_u64()
                        .map(|v| v as u32)
                        .or_else(|| parse_height_from_quality(&quality));
                    let fps = s["fps"]
                        .as_u64()
                        .map(|v| v as f32)
                        .or_else(|| parse_fps_from_quality(&quality));
                    let size = s["clen"].as_str().and_then(|v| v.parse::<u64>().ok());

                    streams.push(StreamResult {
                        url: u.to_string(),
                        quality,
                        format: container.to_uppercase(),
                        container: Some(container.clone()),
                        width,
                        height,
                        fps,
                        video_codec: if is_audio { None } else { vcodec },
                        audio_codec: if is_audio {
                            acodec.or_else(|| default_audio_codec_for(&container))
                        } else {
                            None
                        },
                        bitrate_kbps,
                        file_size_bytes: size,
                        has_video: !is_audio,
                        has_audio: is_audio,
                        is_audio_only: is_audio,
                        is_hdr: false,
                    });
                }
            }
        }

        final_sort(&mut streams);
        if !streams.is_empty() {
            debug_log::log_debug(&format!(
                "invidious: success via {} ({} streams)",
                inst,
                streams.len()
            ));
            return Ok(VideoInfoResult {
                title,
                thumbnail_url: thumbnail,
                platform: "YouTube".into(),
                duration_seconds: duration,
                author,
                streams,
            });
        }
    }
    Err(last_err)
}

// يجلب ytInitialPlayerResponse من صفحة HTML ورابط player.js
async fn fetch_initial_player_response(video_id: &str) -> Result<(Value, Option<String>)> {
    let client = browser_client()?;
    let html = client
        .get(format!("https://www.youtube.com/watch?v={}&hl=en&bpctr=9999999999&has_verified=1", video_id))
        .header("Accept-Language", "en-US,en;q=0.9")
        .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")
        .header("Accept-Encoding", "gzip, deflate, br")
        .header("Upgrade-Insecure-Requests", "1")
        .header("Sec-Fetch-Dest", "document")
        .header("Sec-Fetch-Mode", "navigate")
        .header("Sec-Fetch-Site", "none")
        .header("Sec-Fetch-User", "?1")
        .header("Cookie", "CONSENT=YES+cb; VISITOR_INFO1_LIVE=; YSC=; SOCS=CAISNQgDEitib3FfaWRlbnRpdHlfdmVyc2lvbj0xNDExMjg0NTQzNzE1Nzg2NDg5OTIxNTk=")
        .send().await?
        .text().await?;

    let resp = extract_yt_initial_player_response(&html)
        .ok_or_else(|| anyhow!("ytInitialPlayerResponse غير موجود"))?;

    // نحاول أولاً من صفحة Watch، ثم Embed كبديل
    let player_path = extract_player_js_url(&html).or_else(|| None); // Embed fallback handled separately

    Ok((resp, player_path))
}

// يجلب مسار player.js من صفحة Embed — أقل عرضة لحجب bot
async fn fetch_player_js_path_from_embed(video_id: &str) -> Option<String> {
    let html = browser_client()
        .ok()?
        .get(format!("https://www.youtube.com/embed/{}", video_id))
        .header("Accept-Language", "en-US,en;q=0.9")
        .header("Referer", "https://www.youtube.com/")
        .send()
        .await
        .ok()?
        .text()
        .await
        .ok()?;
    extract_player_js_url(&html)
}

fn extract_yt_initial_player_response(html: &str) -> Option<Value> {
    // نبحث عن ytInitialPlayerResponse في عدة مواضع محتملة
    for marker in &[
        "ytInitialPlayerResponse=",
        "ytInitialPlayerResponse =",
        r#"var ytInitialPlayerResponse ="#,
        r#"window["ytInitialPlayerResponse"]="#,
    ] {
        if let Some(start) = html.find(marker) {
            let after = &html[start + marker.len()..];
            // نتجاهل الفراغات
            let trimmed = after.trim_start();
            if trimmed.starts_with('{') {
                if let Some(json_str) = extract_balanced_braces(trimmed) {
                    if let Ok(v) = serde_json::from_str::<Value>(json_str) {
                        return Some(v);
                    }
                }
            }
        }
    }
    None
}

// يستخرج JSON متوازن الأقواس
fn extract_balanced_braces(s: &str) -> Option<&str> {
    let mut depth: i32 = 0;
    let mut in_string = false;
    let mut escape = false;
    let bytes = s.as_bytes();

    for (i, &b) in bytes.iter().enumerate() {
        if escape {
            escape = false;
            continue;
        }
        if b == b'\\' && in_string {
            escape = true;
            continue;
        }
        if b == b'"' {
            in_string = !in_string;
            continue;
        }
        if in_string {
            continue;
        }
        match b {
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(&s[..=i]);
                }
            }
            _ => {}
        }
    }
    None
}

fn youtube_has_any_streams(resp: &Value) -> bool {
    youtube_has_direct_urls(resp) || youtube_has_cipher_streams(resp)
}

fn youtube_has_direct_urls(resp: &Value) -> bool {
    for key in &["formats", "adaptiveFormats"] {
        if let Some(arr) = resp["streamingData"][key].as_array() {
            if arr.iter().any(|f| f["url"].is_string()) {
                return true;
            }
        }
    }
    false
}

fn youtube_has_cipher_streams(resp: &Value) -> bool {
    for key in &["formats", "adaptiveFormats"] {
        if let Some(arr) = resp["streamingData"][key].as_array() {
            if arr
                .iter()
                .any(|f| f["signatureCipher"].is_string() || f["cipher"].is_string())
            {
                return true;
            }
        }
    }
    false
}

async fn youtube_build_result(
    video_id: &str,
    resp: Value,
    pf: Option<&PlayerFunctions>,
) -> Result<VideoInfoResult> {
    let details = &resp["videoDetails"];
    let title = details["title"]
        .as_str()
        .unwrap_or("YouTube Video")
        .to_string();
    let author = details["author"].as_str().map(|s| s.to_string());
    let duration = details["lengthSeconds"]
        .as_str()
        .and_then(|s| s.parse::<u32>().ok());
    let thumbnail = details["thumbnail"]["thumbnails"]
        .as_array()
        .and_then(|a| a.last())
        .and_then(|t| t["url"].as_str())
        .map(|s| s.split('?').next().unwrap_or(s).to_string())
        .or_else(|| {
            Some(format!(
                "https://img.youtube.com/vi/{}/hqdefault.jpg",
                video_id
            ))
        });

    let mut streams: Vec<StreamResult> = Vec::new();

    for key in &["formats", "adaptiveFormats"] {
        if let Some(fmts) = resp["streamingData"][key].as_array() {
            for f in fmts {
                let mime = f["mimeType"].as_str().unwrap_or("");
                if !mime.starts_with("audio/") && !mime.starts_with("video/") {
                    continue;
                }

                // ── YouTube PoToken protection bypass ──
                // YouTube enforces PoToken on ALL video/mp4 (H.264) streams.
                // Without a valid PoToken, the server silently closes the
                // connection after ~2 MB, producing a truncated 10-second file.
                // WebM/VP9 and audio/mp4 (m4a) streams are NOT affected.
                // Skip video/mp4 entirely so only VP9/AV1 video appears.
                if mime.starts_with("video/mp4") {
                    continue;
                }
                // Also skip legacy progressive muxed MP4 (formats key, itag 18/22)
                if *key == "formats" && mime.starts_with("video/") {
                    continue;
                }

                let url_str = match resolve_stream_url(f, pf) {
                    Some(u) => u,
                    None => continue,
                };

                let mut s = mk_yt_stream(f, url_str.clone());
                if *key == "formats" && !s.is_audio_only {
                    s.has_audio = true;
                    if s.audio_codec.is_none() {
                        s.audio_codec = Some("aac".into());
                    }
                }
                // `adaptiveFormats` video rows are always video-only URLs; never treat as muxed
                // or Dart will skip downloading the separate audio track.
                if *key == "adaptiveFormats" && mime.starts_with("video/") && !s.is_audio_only {
                    s.has_audio = false;
                    s.audio_codec = None;
                }
                
                // If it's a WEBM video stream, we duplicate it and mark the duplicate as MP4.
                // This tells the UI to offer an MP4 transcode option.
                let mut mp4_transcode = None;
                if s.has_video && !s.is_audio_only && s.format.to_uppercase() == "WEBM" {
                    let mut mp4_s = mk_yt_stream(f, url_str.clone());
                    mp4_s.format = "MP4".to_string();
                    mp4_s.container = Some("mp4".to_string());
                    mp4_s.video_codec = Some("h264".to_string());
                    if *key == "formats" && !mp4_s.is_audio_only {
                        mp4_s.has_audio = true;
                        if mp4_s.audio_codec.is_none() { mp4_s.audio_codec = Some("aac".into()); }
                    }
                    if *key == "adaptiveFormats" && mime.starts_with("video/") && !mp4_s.is_audio_only {
                        mp4_s.has_audio = false;
                        mp4_s.audio_codec = None;
                    }
                    mp4_transcode = Some(mp4_s);
                }

                streams.push(s);
                if let Some(mp4_s) = mp4_transcode {
                    streams.push(mp4_s);
                }
            }
        }
    }

    final_sort(&mut streams);

    if streams.is_empty() {
        return Err(anyhow!("لم يتم العثور على روابط قابلة للتحميل"));
    }

    Ok(VideoInfoResult {
        title,
        thumbnail_url: thumbnail,
        platform: "YouTube".into(),
        duration_seconds: duration,
        author,
        streams,
    })
}

fn resolve_stream_url(f: &Value, pf: Option<&PlayerFunctions>) -> Option<String> {
    // رابط مباشر
    if let Some(u) = f["url"].as_str() {
        let n_before = extract_n_value(u);
        let mut url = u.to_string();
        let mut n_transformed = false;

        // إذا كان هناك معامل n، يجب تحويله
        if !n_before.is_empty() {
            if let Some(pf) = pf {
                match apply_n_transform_to_url(u, pf) {
                    Ok(transformed) => {
                        url = transformed;
                        n_transformed = true;
                    }
                    Err(e) => {
                        debug_log::log_debug(&format!(
                            "direct url: itag={} n_transform FAILED: {} — skipping this stream",
                            f["itag"].as_u64().unwrap_or(0),
                            e
                        ));
                        return None;
                    }
                }
            } else {
                debug_log::log_debug(&format!(
                    "direct url: itag={} has n parameter but no player.js — skipping",
                    f["itag"].as_u64().unwrap_or(0)
                ));
                return None;
            }
        }

        let n_after = extract_n_value(&url);
        debug_log::log_debug(&format!(
            "direct url: itag={} n_before={} n_after={} transformed={}",
            f["itag"].as_u64().unwrap_or(0),
            &n_before.chars().take(12).collect::<String>(),
            &n_after.chars().take(12).collect::<String>(),
            n_transformed
        ));
        return Some(url);
    }

    // signatureCipher — نفكّ تشفيره
    let cipher = f["signatureCipher"]
        .as_str()
        .or_else(|| f["cipher"].as_str())?;
    debug_log::log_debug(&format!(
        "cipher url for itag={}",
        f["itag"].as_u64().unwrap_or(0)
    ));
    let mut base_url = String::new();
    let mut sig = String::new();
    let mut sp = "signature".to_string();

    for part in cipher.split('&') {
        if let Some(eq) = part.find('=') {
            let key = &part[..eq];
            let val = urlencoding::decode(&part[eq + 1..]).ok()?.to_string();
            match key {
                "url" => base_url = val,
                "s" => sig = val,
                "sp" => sp = val,
                _ => {}
            }
        }
    }

    if base_url.is_empty() || sig.is_empty() {
        return None;
    }

    let n_val = extract_n_value(&base_url);

    // بدون pf لا يمكن فكّ تشفير cipher — نتجاهل هذا الرابط
    let pf = pf?;

    let decoded_sig = match decipher_signature(pf, &sig) {
        Some(s) => {
            debug_log::log_debug(&format!(
                "cipher decoded: {} ops, sig_len {}→{}",
                pf.decipher_ops.len(),
                sig.len(),
                s.len()
            ));
            s
        }
        None => {
            debug_log::log_debug("cipher decode FAILED — skipping stream");
            return None;
        }
    };

    let new_n = if !pf.n_fn_name.is_empty() && !n_val.is_empty() {
        match run_js_fn(&pf.player_js, &pf.n_fn_name, &n_val) {
            Ok(v) => {
                debug_log::log_debug(&format!(
                    "n transformed OK ({}→{})",
                    &n_val[..n_val.len().min(10)],
                    &v[..v.len().min(10)]
                ));
                v
            }
            Err(e) => {
                debug_log::log_debug(&format!("n transform FAILED: {}", e));
                n_val.clone()
            }
        }
    } else {
        n_val.clone()
    };

    let url_with_sig = format!("{}&{}={}", base_url, sp, urlencoding::encode(&decoded_sig));
    let final_url = replace_n_value(&url_with_sig, &new_n);

    Some(final_url)
}

fn extract_n_value(url: &str) -> String {
    RE_N_QUERY
        .captures(url)
        .map(|c| c[1].to_string())
        .unwrap_or_default()
}

fn replace_n_value(url: &str, new_n: &str) -> String {
    if new_n.is_empty() {
        return url.to_string();
    }
    let s = RE_N_REPLACE.replace(
        url,
        format!("${{1}}{}", urlencoding::encode(new_n)).as_str(),
    );
    s.to_string()
}

// يفكّ تشفير التوقيع بثلاث استراتيجيات متتالية
fn decipher_signature(pf: &PlayerFunctions, sig: &str) -> Option<String> {
    // استراتيجية 1: Rust خالص (أسرع)
    if !pf.decipher_ops.is_empty() {
        return Some(apply_decipher_ops(sig, &pf.decipher_ops));
    }
    if pf.decipher_fn_name.is_empty() {
        return None;
    }

    #[cfg(not(target_os = "android"))]
    {
        // استراتيجية 2: حقن IIFE ثم استدعاء
        let injected = inject_iife_capture(&pf.player_js, &pf.decipher_fn_name);
        if let Ok(r) = eval_captured(&injected, sig) {
            return Some(r);
        }

        // استراتيجية 3: استخلاص الدالة كـ standalone
        if let Some(script) = extract_n_fn_as_global(&pf.player_js, &pf.decipher_fn_name) {
            use rquickjs::{Context, Runtime};
            if let (Ok(rt), _) = (Runtime::new(), ()) {
                if let Ok(ctx) = Context::full(&rt) {
                    let res: Result<String> = ctx.with(|ctx| {
                        ctx.eval::<(), _>(script.as_bytes())
                            .map_err(|e| anyhow!("{:?}", e))?;
                        let esc = sig.replace('\\', "\\\\").replace('\'', "\\'");
                        ctx.eval::<String, _>(
                            format!("{}('{}')", pf.decipher_fn_name, esc).as_bytes(),
                        )
                        .map_err(|e| anyhow!("{:?}", e))
                    });
                    if let Ok(r) = res {
                        return Some(r);
                    }
                }
            }
        }
    }

    None
}

fn apply_n_transform_to_url(url: &str, pf: &PlayerFunctions) -> Result<String> {
    let n_val = extract_n_value(url);
    if n_val.is_empty() || pf.n_fn_name.is_empty() {
        return Ok(url.to_string());
    }
    let new_n = run_js_fn(&pf.player_js, &pf.n_fn_name, &n_val)
        .map_err(|e| anyhow!("n_fn '{}' failed: {}", pf.n_fn_name, e))?;
    Ok(replace_n_value(url, &new_n))
}

// ─────────────────────────────────────────────────────────────────────────────
// player.js — جلب + تحليل + cache
// ─────────────────────────────────────────────────────────────────────────────

// يُحمّل player.js بمساره المباشر (مع cache)
async fn load_player_functions(player_path: String) -> Result<Arc<PlayerFunctions>> {
    {
        let cache = player_cache().lock().unwrap();
        if let Some(pf) = cache.get(&player_path) {
            return Ok(Arc::clone(pf));
        }
    }

    let js = browser_client()?
        .get(format!("https://www.youtube.com{}", player_path))
        .send()
        .await?
        .text()
        .await?;

    let decipher_fn_name = parse_decipher_fn_name(&js).unwrap_or_default();
    let decipher_ops = if !decipher_fn_name.is_empty() {
        parse_decipher_ops(&js, &decipher_fn_name)
    } else {
        vec![]
    };
    let n_fn_name = parse_n_fn_name(&js).unwrap_or_default();
    let sts = extract_sts_from_player_js(&js);
    debug_log::log_debug(&format!("player.js sts={:?}", sts));
    let pf = Arc::new(PlayerFunctions {
        decipher_ops,
        decipher_fn_name,
        n_fn_name,
        player_js: js,
        sts,
    });

    {
        let mut cache = player_cache().lock().unwrap();
        cache.insert(player_path, Arc::clone(&pf));
        if cache.len() > 2 {
            if let Some(oldest) = cache.keys().next().map(|k| k.clone()) {
                cache.remove(&oldest);
            }
        }
    }

    Ok(pf)
}

fn extract_player_js_url(html: &str) -> Option<String> {
    for pat in &[
        r#""jsUrl"\s*:\s*"(/s/player/[^"]+\.js)""#,
        r#"(/s/player/[a-zA-Z0-9]{8}/(?:player_ias\.vflset/[^"']+/)?base\.js)"#,
        r#"src="(/s/player/[^"]+\.js)""#,
    ] {
        if let Ok(re) = regex::Regex::new(pat) {
            if let Some(cap) = re.captures(html) {
                return Some(cap[1].to_string());
            }
        }
    }
    None
}

// ─────────────────────────────────────────────────────────────────────────────
// Decipher + n-param — كلاهما عبر rquickjs (تنفيذ player.js مرة واحدة)
// ─────────────────────────────────────────────────────────────────────────────

// يُعيد اسم دالة فكّ التشفير من player.js (الأكثر تحديداً أولاً)
fn parse_decipher_fn_name(js: &str) -> Option<String> {
    for pattern in &[
        // إصدارات حديثة (2024+): تعريف مباشر function X(a){a=a.split("")
        r#"\bfunction\s+([a-zA-Z$_][\w$]{1,9})\s*\(\s*[a-zA-Z]\s*\)\s*\{\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\(\s*""\s*\)"#,
        // var/let/const name = function(a){a=a.split("")
        r#"(?:var|let|const)\s+([a-zA-Z$_][\w$]{1,9})\s*=\s*function\s*\(\s*[a-zA-Z]\s*\)\s*\{\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\(\s*""\s*\)"#,
        // name = function(a){a=a.split("")
        r#"([a-zA-Z$_][\w$]{1,9})\s*=\s*function\s*\(\s*[a-zA-Z]\s*\)\s*\{\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\(\s*""\s*\)"#,
        // استدعاء مباشر: a.set("signature", FN(…))
        r#"["\']signature["\']\s*,\s*([a-zA-Z0-9$_]{2,10})\s*\("#,
        r#"\.sig\s*\|\|\s*([a-zA-Z\d$_]{2,10})\s*\("#,
        r#"a\.set\s*\(\s*["\']sig["\']\s*,\s*([a-zA-Z0-9$_]{2,10})\s*\("#,
        r#"&&\([a-z]=([a-zA-Z0-9$_]{2,10})\(decodeURIComponent"#,
        // بديل قصير
        r#"(?:^|[^$\w])([a-zA-Z\d$_]{2,5})\s*=\s*function\(\s*[a-zA-Z]\s*\)\s*\{\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\("#,
    ] {
        if let Ok(re) = regex::Regex::new(pattern) {
            if let Some(cap) = re.captures(js) {
                let name = cap
                    .get(cap.len() - 1)
                    .map(|m| m.as_str().to_string())
                    .unwrap_or_default();
                if !name.is_empty()
                    && name.len() > 1
                    && !matches!(
                        name.as_str(),
                        "a" | "b" | "c" | "function" | "var" | "let" | "const"
                    )
                {
                    debug_log::log_debug(&format!(
                        "decipher_fn_name matched via pattern: {}",
                        name
                    ));
                    return Some(name);
                }
            }
        }
    }
    debug_log::log_debug("decipher_fn_name: no pattern matched");
    None
}

// يُعيد اسم دالة تحويل n-param
fn parse_n_fn_name(js: &str) -> Option<String> {
    for pattern in &[
        // 2025+: مصفوفة functions في متغيّر (YouTube حديثة جداً)
        r#"var\s+([a-zA-Z$_][\w$]{1,9})\s*=\s*\[\s*function\s*\(\s*[a-zA-Z]\s*\)\s*\{[^}]*split"#,
        // 2024+: استدعاء مباشر ثم .set("n",…)
        r#"\.get\(\s*["']n["']\s*\)\s*\)\s*&&\s*\(\s*[a-zA-Z]\s*=\s*([a-zA-Z0-9$_]{2,10})(?:\[(\d+)\])?\s*\("#,
        r#"[a-zA-Z]\s*=\s*String\.fromCharCode\(110\)\s*,\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.get\([a-zA-Z]\)\)\s*&&\s*\(\s*[a-zA-Z]\s*=\s*([a-zA-Z0-9$_]{2,10})(?:\[(\d+)\])?\s*\("#,
        r#"\.get\(\s*["']n["']\s*\)\s*\)\s*&&\s*\([a-zA-Z]\s*=\s*([a-zA-Z0-9$_]{2,10})(?:\[(\d+)\])?\s*\("#,
        r#"([a-zA-Z0-9$_]{2,10})\s*=\s*([a-zA-Z0-9$_]{2,10})\s*\([a-zA-Z]\)\s*;\s*[a-zA-Z]\.set\(\s*["']n["']"#,
        r#"\.set\(\s*["']n["']\s*,\s*([a-zA-Z0-9$_]{2,10})\([a-zA-Z]\)\s*\)"#,
        // إصدارات حديثة بتعريف مباشر: function FN(a){var b=a.split(…,/null/) … return b.join("")}
        r#"function\s+([a-zA-Z$_][\w$]{1,9})\s*\(\s*[a-zA-Z]\s*\)\s*\{\s*(?:var|let|const)\s+[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\(\s*["'][^"']*["']\s*,\s*null\s*\)"#,
    ] {
        let re = match regex::Regex::new(pattern) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Some(cap) = re.captures(js) {
            let raw_name = cap[1].to_string();
            debug_log::log_debug(&format!(
                "n_fn_name: matched pattern, raw_name={}",
                raw_name
            ));
            // إذا كان مصفوفة: var XX=[fn1,fn2]; → نأخذ الاسم الفعلي
            if let Some(idx_m) = cap.get(2) {
                let idx: usize = idx_m.as_str().parse().unwrap_or(0);
                let arr_re = regex::Regex::new(&format!(
                    r#"var\s+{}\s*=\s*\[([^\]]+)\]"#,
                    regex::escape(&raw_name)
                ))
                .ok()?;
                if let Some(arr_cap) = arr_re.captures(js) {
                    let names: Vec<&str> = arr_cap[1].split(',').collect();
                    if let Some(n) = names.get(idx) {
                        debug_log::log_debug(&format!(
                            "n_fn_name: array index {} → {}",
                            idx,
                            n.trim()
                        ));
                        return Some(n.trim().to_string());
                    }
                }
            }
            return Some(raw_name);
        }
    }
    debug_log::log_debug("n_fn_name: no pattern matched — YouTube player.js may have changed");
    None
}

#[cfg(not(target_os = "android"))]
fn apply_js_transforms(
    player_js: &str,
    decipher_fn: &str,
    sig: &str,
    n_fn: &str,
    n_val: &str,
) -> Result<(String, String)> {
    use rquickjs::{Context, Runtime};

    let rt = Runtime::new().map_err(|e| anyhow!("{:?}", e))?;
    let ctx = Context::full(&rt).map_err(|e| anyhow!("{:?}", e))?;

    ctx.with(|ctx| {
        // نُقيّم player.js — نتجاهل أي خطأ في التحميل
        let _ = ctx.eval::<(), _>(player_js.as_bytes());

        // فكّ التشفير — إذا فشل نُعيد خطأ (لا نستخدم sig الأصلي المشفّر)
        let new_sig: String = if !decipher_fn.is_empty() && !sig.is_empty() {
            let esc = sig.replace('\\', "\\\\").replace('\'', "\\'");
            ctx.eval::<String, _>(format!("{}('{}')", decipher_fn, esc).as_bytes())
                .map_err(|e| anyhow!("decipher failed: {:?}", e))?
        } else {
            sig.to_string()
        };

        // تحويل n
        let new_n: String = if !n_fn.is_empty() && !n_val.is_empty() {
            let esc = n_val.replace('\\', "\\\\").replace('\'', "\\'");
            ctx.eval::<String, _>(format!("{}('{}')", n_fn, esc).as_bytes())
                .unwrap_or_else(|_| n_val.to_string())
        } else {
            n_val.to_string()
        };

        Ok((new_sig, new_n))
    })
}

#[cfg(target_os = "android")]
fn apply_js_transforms(
    _player_js: &str,
    _decipher_fn: &str,
    _sig: &str,
    _n_fn: &str,
    _n_val: &str,
) -> Result<(String, String)> {
    Err(anyhow!(
        "apply_js_transforms requires QuickJS; not built for Android"
    ))
}

#[cfg(not(target_os = "android"))]
fn eval_captured(js: &str, arg: &str) -> Result<String> {
    use rquickjs::{Context, Runtime};
    let rt = Runtime::new().map_err(|e| anyhow!("{:?}", e))?;
    let ctx = Context::full(&rt).map_err(|e| anyhow!("{:?}", e))?;
    ctx.with(|ctx| {
        let _ = ctx.eval::<(), _>(js.as_bytes());
        let esc = arg.replace('\\', "\\\\").replace('\'', "\\'");
        ctx.eval::<String, _>(format!("globalThis.__YT_FN__('{}')", esc).as_bytes())
            .map_err(|e| anyhow!("captured eval: {:?}", e))
    })
}

#[cfg(target_os = "android")]
fn eval_captured(_js: &str, _arg: &str) -> Result<String> {
    Err(anyhow!(
        "eval_captured requires QuickJS; not built for Android"
    ))
}

// يحقن نقطة التقاط داخل IIFE لإخراج الدالة للسياق العام
fn inject_iife_capture(js: &str, fn_name: &str) -> String {
    let injection = format!(
        ";try{{if(typeof {fn}!=='undefined')globalThis.__YT_FN__={fn};}}catch(e){{}}",
        fn = fn_name
    );
    // آخر `})(` في الملف هو نهاية IIFE الرئيسي
    if let Some(pos) = js.rfind("})(") {
        let mut result = String::with_capacity(js.len() + injection.len());
        result.push_str(&js[..pos]);
        result.push_str(&injection);
        result.push_str(&js[pos..]);
        return result;
    }
    // بديل: قبل آخر `}()`
    if let Some(pos) = js.rfind("}()") {
        let mut result = String::with_capacity(js.len() + injection.len());
        result.push_str(&js[..pos]);
        result.push_str(&injection);
        result.push_str(&js[pos..]);
        return result;
    }
    format!("{}{}", js, injection)
}

// يستخرج دالة n-transform كـ standalone بعيداً عن IIFE player.js
fn extract_n_fn_as_global(js: &str, fn_name: &str) -> Option<String> {
    // Case 1: var FN = function(a) {...}
    let p1 = format!(
        r"(?:var|let|const)\s+{}\s*=\s*function",
        regex::escape(fn_name)
    );
    if let Ok(re) = regex::Regex::new(&p1) {
        if let Some(m) = re.find(js) {
            let rest = &js[m.start()..];
            if let Some(fn_pos) = rest.find("function") {
                let fn_part = &rest[fn_pos..];
                if let Some(brace_pos) = fn_part.find('{') {
                    if let Some(body) = extract_balanced_braces(&fn_part[brace_pos..]) {
                        let params = regex::Regex::new(r"function\s*\(([^)]*)\)")
                            .ok()
                            .and_then(|r| r.captures(fn_part))
                            .map(|c| c[1].to_string())
                            .unwrap_or_default();
                        return Some(format!("function {}({}) {}", fn_name, params, body));
                    }
                }
            }
        }
    }

    // Case 2: var FN = [function(a){...}, ...]  — modern YT wraps n-fn in array
    let p2 = format!(r"(?:var|let|const)\s+{}\s*=\s*\[", regex::escape(fn_name));
    if let Ok(re) = regex::Regex::new(&p2) {
        if let Some(m) = re.find(js) {
            let rest = &js[m.end() - 1..];
            let mut depth: i32 = 0;
            let mut in_str = false;
            let mut escape = false;
            let mut fn_start: Option<usize> = None;

            for (i, &b) in rest.as_bytes().iter().enumerate() {
                if escape {
                    escape = false;
                    continue;
                }
                if b == b'\\' && in_str {
                    escape = true;
                    continue;
                }
                if b == b'"' || b == b'\'' {
                    in_str = !in_str;
                    continue;
                }
                if in_str {
                    continue;
                }
                match b {
                    b'[' => depth += 1,
                    b']' => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    _ => {}
                }
                if depth == 1 && fn_start.is_none() && rest[i..].starts_with("function") {
                    fn_start = Some(i);
                }
            }

            if let Some(start) = fn_start {
                let fn_part = &rest[start..];
                if let Some(brace_pos) = fn_part.find('{') {
                    if let Some(body) = extract_balanced_braces(&fn_part[brace_pos..]) {
                        let params = regex::Regex::new(r"function\s*\(([^)]*)\)")
                            .ok()
                            .and_then(|r| r.captures(fn_part))
                            .map(|c| c[1].to_string())
                            .unwrap_or_default();
                        return Some(format!("function {}({}) {}", fn_name, params, body));
                    }
                }
            }
        }
    }

    None
}

#[cfg(not(target_os = "android"))]
fn run_js_fn(player_js: &str, fn_name: &str, arg: &str) -> Result<String> {
    use rquickjs::{Context, Runtime};

    // استراتيجية 1: استخلاص الدالة كـ standalone (الأسرع)
    if let Some(script) = extract_n_fn_as_global(player_js, fn_name) {
        let rt = Runtime::new().map_err(|e| anyhow!("{:?}", e))?;
        let ctx = Context::full(&rt).map_err(|e| anyhow!("{:?}", e))?;
        let res: Result<String> = ctx.with(|ctx| {
            ctx.eval::<(), _>(script.as_bytes())
                .map_err(|e| anyhow!("eval: {:?}", e))?;
            let esc = arg.replace('\\', "\\\\").replace('\'', "\\'");
            ctx.eval::<String, _>(format!("{}('{}')", fn_name, esc).as_bytes())
                .map_err(|e| anyhow!("{:?}", e))
        });
        if let Ok(r) = res {
            return Ok(r);
        }
    }

    // استراتيجية 2: حقن نقطة التقاط داخل IIFE
    let injected = inject_iife_capture(player_js, fn_name);
    if let Ok(r) = eval_captured(&injected, arg) {
        return Ok(r);
    }

    // استراتيجية 3: تقييم player.js بالكامل والاستدعاء المباشر (احتياطي)
    let rt = Runtime::new().map_err(|e| anyhow!("{:?}", e))?;
    let ctx = Context::full(&rt).map_err(|e| anyhow!("{:?}", e))?;
    ctx.with(|ctx| {
        let _ = ctx.eval::<(), _>(player_js.as_bytes());
        let esc = arg.replace('\\', "\\\\").replace('\'', "\\'");
        ctx.eval::<String, _>(format!("{}('{}')", fn_name, esc).as_bytes())
            .map_err(|e| anyhow!("all strategies failed: {:?}", e))
    })
}

#[cfg(target_os = "android")]
fn run_js_fn(_player_js: &str, _fn_name: &str, _arg: &str) -> Result<String> {
    Err(anyhow!("run_js_fn requires QuickJS; not built for Android"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Innertube Player API — طلبات محسّنة لكل عميل
// ─────────────────────────────────────────────────────────────────────────────

async fn innertube_mweb(video_id: &str) -> Result<Value> {
    // MWEB يُعيد روابط مباشرة (بدون cipher) لمعظم الفيديوهات
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "MWEB",
                "clientVersion": "2.20250101.01.00",
                "hl": "en",
                "gl": "US"
            }
        },
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(video_id,
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        body,
        &[("X-YouTube-Client-Name","2"),("X-YouTube-Client-Version","2.20250101.01.00")]).await
}

async fn innertube_tv_embedded(video_id: &str) -> Result<Value> {
    // أكثر العملاء موثوقية — يعمل بدون poToken مع embedUrl
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                "clientVersion": "2.0",
                "hl": "en",
                "gl": "US",
                "clientScreen": "EMBED"
            },
            "thirdParty": {
                "embedUrl": format!("https://www.youtube.com/embed/{}", video_id)
            }
        },
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(
        video_id,
        "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/538.1",
        body,
        &[
            ("X-YouTube-Client-Name", "85"),
            ("X-YouTube-Client-Version", "2.0"),
        ],
    )
    .await
}

async fn innertube_web_embedded(video_id: &str) -> Result<Value> {
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "WEB_EMBEDDED_PLAYER",
                "clientVersion": "1.20250115.01.01",
                "hl": "en",
                "gl": "US",
                "clientScreen": "EMBED"
            },
            "thirdParty": {
                "embedUrl": format!("https://www.youtube.com/embed/{}", video_id)
            }
        },
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(video_id,
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
        body,
        &[("X-YouTube-Client-Name","56"),("X-YouTube-Client-Version","1.20250115.01.01")]).await
}

async fn innertube_android_vr(video_id: &str) -> Result<Value> {
    // ANDROID_VR: client خاص يتجاوز القيود ولا يتطلب n-transform
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "ANDROID_VR",
                "clientVersion": "1.60.19",
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "androidSdkVersion": 32,
                "osName": "Android",
                "osVersion": "12L",
                "hl": "en",
                "gl": "US"
            }
        },
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(video_id,
        "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        body,
        &[("X-YouTube-Client-Name","28"),("X-YouTube-Client-Version","1.60.19")]).await
}

async fn innertube_android(video_id: &str) -> Result<Value> {
    // Android مع params لجلب adaptive formats
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "ANDROID",
                "clientVersion": "19.49.37",
                "androidSdkVersion": 31,
                "osName": "Android",
                "osVersion": "12",
                "hl": "en",
                "gl": "US"
            },
            "request": { "useSsl": true },
            "user": { "lockedSafetyMode": false }
        },
        "params": "2AMBCgIQBg==",
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(
        video_id,
        "com.google.android.youtube/19.49.37 (Linux; U; Android 12) gzip",
        body,
        &[
            ("X-YouTube-Client-Name", "3"),
            ("X-YouTube-Client-Version", "19.49.37"),
        ],
    )
    .await
}

async fn innertube_ios(video_id: &str) -> Result<Value> {
    let body = json!({
        "videoId": video_id,
        "context": {
            "client": {
                "clientName": "IOS",
                "clientVersion": "20.03.02",
                "deviceModel": "iPhone16,2",
                "osName": "iPhone",
                "osVersion": "18.2.0",
                "hl": "en",
                "gl": "US"
            },
            "user": { "lockedSafetyMode": false }
        },
        "contentCheckOk": true,
        "racyCheckOk": true
    });
    innertube_post(
        video_id,
        "com.google.ios.youtube/20.03.02 (iPhone16,2; U; CPU iOS 18_2_0 like Mac OS X)",
        body,
        &[
            ("X-YouTube-Client-Name", "5"),
            ("X-YouTube-Client-Version", "20.03.02"),
        ],
    )
    .await
}

async fn innertube_post(
    _video_id: &str,
    user_agent: &str,
    mut body: Value,
    extra_headers: &[(&str, &str)],
) -> Result<Value> {
    // نحقن visitorData + sts — **إجباريان** لتجاوز po_token و rate limiting
    let visitor_data = get_visitor_data().await;
    let sts = {
        let cache = player_cache().lock().unwrap();
        cache.values().next().and_then(|pf| pf.sts)
    };

    // visitorData: إذا فشل الحصول عليه، استخدم قيمة افتراضية
    let final_vd = visitor_data.unwrap_or_else(|| {
        // قيمة افتراضية قوية (تتغير بناءً على التاريخ)
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        format!("CgtHUkU0TlROdm5FNkY={}", (ts % 1000000))
    });

    if let Some(client) = body
        .get_mut("context")
        .and_then(|c| c.get_mut("client"))
        .and_then(|c| c.as_object_mut())
    {
        client.insert("visitorData".to_string(), json!(final_vd));
        debug_log::log_debug(&format!("innertube: visitorData injected"));
    }

    // signatureTimestamp: إجباري لـ TV/WEB
    let final_sts = sts.unwrap_or_else(|| {
        // قيمة افتراضية محدثة (رقم كبير يشبه timestamp حقيقي)
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as u32)
            .unwrap_or(1700000000);
        ts
    });

    if let Some(obj) = body.as_object_mut() {
        obj.entry("playbackContext").or_insert_with(|| json!({}));
        if let Some(pc) = obj
            .get_mut("playbackContext")
            .and_then(|v| v.as_object_mut())
        {
            pc.entry("contentPlaybackContext")
                .or_insert_with(|| json!({}));
            if let Some(cpc) = pc
                .get_mut("contentPlaybackContext")
                .and_then(|v| v.as_object_mut())
            {
                cpc.insert("signatureTimestamp".to_string(), json!(final_sts));
                cpc.insert("html5Preference".to_string(), json!("HTML5_PREF_WANTS"));
                debug_log::log_debug(&format!("innertube: signatureTimestamp={}", final_sts));
            }
        }
    }

    let mut req = reqwest::Client::builder()
        .user_agent(user_agent)
        .timeout(std::time::Duration::from_secs(30))
        .build()?
        .post("https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
        .header("Content-Type", "application/json")
        .header("Origin", "https://www.youtube.com")
        .header("Referer", "https://www.youtube.com/")
        .header("X-Goog-Api-Format-Version", "2")
        .header("X-Youtube-Bootstrap-Logged-In", "false");

    req = req.header("X-Goog-Visitor-Id", final_vd);

    for (k, v) in extra_headers {
        req = req.header(*k, *v);
    }

    Ok(req.json(&body).send().await?.json().await?)
}

fn parse_youtube_id(url: &str) -> Option<String> {
    if let Ok(u) = url::Url::parse(url) {
        if u.host_str() == Some("youtu.be") {
            return u.path_segments()?.next().map(|s| s.to_string());
        }
        if let Some(v) = u.query_pairs().find(|(k, _)| k == "v") {
            return Some(v.1.to_string());
        }
        let segs: Vec<&str> = u.path_segments()?.collect();
        for (i, seg) in segs.iter().enumerate() {
            if ["shorts", "embed", "v", "e", "live"].contains(seg) {
                if let Some(id) = segs.get(i + 1) {
                    return Some(id.to_string());
                }
            }
        }
    }
    RE_YOUTUBE_ID_IN_URL
        .captures(url)?
        .get(1)
        .map(|m| m.as_str().to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Vimeo
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_vimeo(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let data: Value = client
        .get(format!(
            "https://vimeo.com/api/oembed.json?url={}",
            urlencoding::encode(url)
        ))
        .send()
        .await?
        .json()
        .await?;

    let title = data["title"].as_str().unwrap_or("Vimeo Video").to_string();
    let thumbnail = data["thumbnail_url"].as_str().map(|s| s.to_string());
    let duration = data["duration"].as_u64().map(|d| d as u32);
    let author = data["author_name"].as_str().map(|s| s.to_string());
    let video_id = data["video_id"]
        .as_u64()
        .map(|id| id.to_string())
        .or_else(|| {
            url::Url::parse(url)
                .ok()?
                .path_segments()?
                .last()
                .map(|s| s.to_string())
        });

    let mut streams = Vec::new();
    if let Some(id) = video_id.as_deref() {
        if let Ok(resp) = client
            .get(format!("https://player.vimeo.com/video/{}/config", id))
            .send()
            .await
        {
            if let Ok(cfg) = resp.json::<Value>().await {
                if let Some(files) = cfg["request"]["files"]["progressive"].as_array() {
                    for f in files {
                        if let Some(file_url) = f["url"].as_str() {
                            let quality = f["quality"].as_str().unwrap_or("HD").to_string();
                            let width = f["width"].as_u64().map(|v| v as u32);
                            let height = f["height"]
                                .as_u64()
                                .map(|v| v as u32)
                                .or_else(|| parse_height_from_quality(&quality));
                            let fps = f["fps"]
                                .as_u64()
                                .map(|v| v as f32)
                                .or_else(|| f["fps"].as_f64().map(|v| v as f32));
                            streams.push(StreamResult {
                                url: file_url.to_string(),
                                quality,
                                format: "MP4".into(),
                                container: Some("mp4".into()),
                                width: width.or_else(|| infer_width(height)),
                                height,
                                fps,
                                video_codec: Some("avc1".into()),
                                audio_codec: Some("aac".into()),
                                bitrate_kbps: None,
                                file_size_bytes: None,
                                has_video: true,
                                has_audio: true,
                                is_audio_only: false,
                                is_hdr: false,
                            });
                        }
                    }
                }
            }
        }
    }

    if streams.is_empty() {
        return Err(anyhow!("هذا الفيديو خاص أو محمي بكلمة مرور"));
    }

    final_sort(&mut streams);
    Ok(VideoInfoResult {
        title,
        thumbnail_url: thumbnail,
        platform: "Vimeo".into(),
        duration_seconds: duration,
        author,
        streams,
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// TikTok
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_tiktok(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    debug_log::log_debug(&format!("==== extract_tiktok url={} ====", url));

    // ─── PRIMARY: TikWM API (الأكثر موثوقية — بدون watermark، روابط مباشرة) ──
    debug_log::log_debug("=== PRIMARY: TikWM API (direct download, no watermark) ===");
    let tikwm_url = format!(
        "https://tikwm.com/api/?url={}&hd=1",
        urlencoding::encode(url)
    );
    if let Ok(resp) = client
        .get(&tikwm_url)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
    {
        if let Ok(data) = resp.json::<Value>().await {
            let d = &data["data"];
            if let Some(video_url) = d["hdplay"].as_str().or_else(|| d["play"].as_str()) {
                let title = d["title"].as_str().unwrap_or("TikTok Video").to_string();
                let thumbnail = d["cover"]
                    .as_str()
                    .or_else(|| d["origin_cover"].as_str())
                    .map(|s| s.to_string());
                let author = d["author"]["unique_id"]
                    .as_str()
                    .or_else(|| d["author"]["nickname"].as_str())
                    .map(|s| s.to_string());
                let duration = d["duration"].as_u64().map(|d| d as u32);

                let mut streams = vec![];
                let is_hd = d["hdplay"].is_string();
                let quality = if is_hd {
                    "HD (1080p)".to_string()
                } else {
                    "SD (720p)".to_string()
                };
                // TikTok TikWM returns muxed MP4 with H.264+AAC by contract.
                let mut muxed =
                    mk_muxed_stream(video_url.to_string(), quality, "mp4", d["size"].as_u64());
                muxed.height = Some(if is_hd { 1080 } else { 720 });
                muxed.width = infer_width(muxed.height);
                muxed.video_codec = Some("avc1".into());
                muxed.audio_codec = Some("aac".into());
                streams.push(muxed);

                if let Some(audio_url) = d["music"].as_str() {
                    streams.push(mk_audio_only_stream(
                        audio_url.to_string(),
                        "128kbps".into(),
                        "mp3",
                        Some(128),
                        None,
                    ));
                }

                final_sort(&mut streams);
                debug_log::log_debug(&format!("✓ TikWM succeeded ({} streams)", streams.len()));
                return Ok(VideoInfoResult {
                    title,
                    thumbnail_url: thumbnail,
                    platform: "TikTok".into(),
                    duration_seconds: duration,
                    author,
                    streams,
                });
            }
        }
    }

    // ─── FALLBACK 1: SSSTik API ──
    debug_log::log_debug("=== FALLBACK 1: SSSTik direct ===");
    let ssstik_url = format!(
        "https://ssstik.io/abc?url=dl&url={}",
        urlencoding::encode(url)
    );
    if let Ok(resp) = client
        .post(&ssstik_url)
        .header("HX-Request", "true")
        .header("HX-Target", "target")
        .header("Origin", "https://ssstik.io")
        .header("Referer", "https://ssstik.io/en")
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
    {
        if let Ok(html) = resp.text().await {
            if let Some(c) = RE_SSSTIK_CDN.captures(&html) {
                let video_url = c[1].replace("&amp;", "&");
                debug_log::log_debug("✓ SSSTik succeeded");
                return Ok(VideoInfoResult {
                    title: "TikTok Video".into(),
                    thumbnail_url: None,
                    platform: "TikTok".into(),
                    duration_seconds: None,
                    author: None,
                    streams: vec![mk_muxed_stream(video_url, "HD".into(), "mp4", None)],
                });
            }
        }
    }

    // ─── FALLBACK 2: TikTok's own API (rare success but try) ──
    debug_log::log_debug("=== FALLBACK 2: TikTok direct API ===");
    let api_url = format!(
        "https://api.tiktokv.com/aweme/v1/feed/?aweme_id={}",
        extract_tiktok_id(url).unwrap_or_default()
    );
    if let Ok(resp) = client.get(&api_url)
        .header("User-Agent", "com.ss.android.ugc.trill/2613 (Linux; U; Android 10; en_US; Pixel 4; Build/QQ3A.200805.001; Cronet/58.0.2991.0)")
        .timeout(std::time::Duration::from_secs(12))
        .send().await
    {
        if let Ok(data) = resp.json::<Value>().await {
            if let Some(aweme) = data["aweme_list"].as_array().and_then(|a| a.first()) {
                let title     = aweme["desc"].as_str().unwrap_or("TikTok Video").to_string();
                let thumbnail = aweme["video"]["cover"]["url_list"]
                    .as_array().and_then(|a| a.first()).and_then(|u| u.as_str()).map(|s| s.to_string());
                let play_url  = aweme["video"]["play_addr"]["url_list"]
                    .as_array().and_then(|a| a.first()).and_then(|u| u.as_str());

                if let Some(pu) = play_url {
                    return Ok(VideoInfoResult {
                        title, thumbnail_url: thumbnail, platform: "TikTok".into(),
                        duration_seconds: None, author: None,
                        streams: vec![mk_muxed_stream(pu.to_string(), "HD".into(), "mp4", None)],
                    });
                }
            }
        }
    }

    Err(anyhow!(
        "تعذر جلب رابط التحميل المباشر من TikTok — حاول لاحقاً"
    ))
}

fn extract_tiktok_id(url: &str) -> Option<String> {
    RE_TIKTOK_VIDEO_ID.captures(url).map(|c| c[1].to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Instagram
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_instagram(url: &str) -> Result<VideoInfoResult> {
    debug_log::log_debug(&format!("==== extract_instagram url={} ====", url));

    // ─── STRATEGY 1: facebookexternalhit crawler (يعود OG meta) ──
    let client = reqwest::Client::builder()
        .user_agent("facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)")
        .timeout(std::time::Duration::from_secs(20))
        .build()?;

    if let Ok(resp) = client
        .get(url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await
    {
        if let Ok(html) = resp.text().await {
            let video_url = extract_meta_property(&html, "og:video:secure_url")
                .or_else(|| extract_meta_property(&html, "og:video"));
            let title = extract_meta_property(&html, "og:title")
                .unwrap_or_else(|| "Instagram Video".to_string());
            let thumbnail = extract_meta_property(&html, "og:image");

            if let Some(vu) = video_url {
                debug_log::log_debug("✓ Instagram: OG crawler succeeded");
                return Ok(VideoInfoResult {
                    title,
                    thumbnail_url: thumbnail,
                    platform: "Instagram".into(),
                    duration_seconds: None,
                    author: None,
                    streams: vec![mk_muxed_stream(vu, "HD".into(), "mp4", None)],
                });
            }
        }
    }

    // ─── STRATEGY 2: Instagram embed API ──
    debug_log::log_debug("=== FALLBACK: Instagram embed API ===");
    let shortcode =
        extract_instagram_shortcode(url).ok_or_else(|| anyhow!("لم يتعرف على معرف المنشور"))?;

    let embed_url = format!("https://www.instagram.com/p/{}/embed/captioned/", shortcode);
    let c2 = browser_client()?;
    if let Ok(resp) = c2
        .get(&embed_url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await
    {
        if let Ok(html) = resp.text().await {
            // استخراج video_url من JSON embedded
            if let Ok(re) = regex::Regex::new(r#""video_url":"([^"]+)""#) {
                if let Some(c) = re.captures(&html) {
                    let vu = c[1].replace(r"&", "&").replace("\\/", "/");
                    let title = extract_meta_property(&html, "og:title")
                        .unwrap_or_else(|| "Instagram Video".to_string());
                    let thumbnail = extract_meta_property(&html, "og:image");
                    debug_log::log_debug("✓ Instagram: embed API succeeded");
                    return Ok(VideoInfoResult {
                        title,
                        thumbnail_url: thumbnail,
                        platform: "Instagram".into(),
                        duration_seconds: None,
                        author: None,
                        streams: vec![mk_muxed_stream(vu, "HD".into(), "mp4", None)],
                    });
                }
            }
        }
    }

    Err(anyhow!("هذا المنشور خاص أو لا يحتوي على فيديو"))
}

fn extract_instagram_shortcode(url: &str) -> Option<String> {
    let re = regex::Regex::new(r"/(p|reel|reels|tv)/([A-Za-z0-9_-]+)").ok()?;
    re.captures(url).map(|c| c[2].to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Twitter / X
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_twitter(url: &str) -> Result<VideoInfoResult> {
    let tweet_id = extract_tweet_id(url).ok_or_else(|| anyhow!("لم يتعرف على معرف التغريدة"))?;

    let client = browser_client()?;
    let token = twitter_guest_token(&client).await.unwrap_or_default();
    let syndi_url = format!(
        "https://cdn.syndication.twimg.com/tweet-result?id={}&lang=en&token={}",
        tweet_id, token
    );

    if let Ok(resp) = client.get(&syndi_url).send().await {
        if let Ok(data) = resp.json::<Value>().await {
            let title = data["text"].as_str().unwrap_or("Twitter Video").to_string();
            let thumbnail = data["mediaDetails"]
                .as_array()
                .and_then(|m| m.first())
                .and_then(|m| m["media_url_https"].as_str())
                .map(|s| s.to_string());

            let mut streams = Vec::new();
            if let Some(media) = data["mediaDetails"].as_array() {
                for m in media {
                    if let Some(variants) = m["video_info"]["variants"].as_array() {
                        let mut sorted = variants.to_vec();
                        sorted.sort_by_key(|v| v["bitrate"].as_u64().unwrap_or(0));
                        for v in sorted.iter().rev() {
                            if let Some(vu) = v["url"].as_str() {
                                if vu.contains(".m3u8") {
                                    continue;
                                }
                                let bitrate = v["bitrate"].as_u64().unwrap_or(0);
                                let quality = match bitrate {
                                    b if b >= 2176000 => "1080p",
                                    b if b >= 832000 => "720p",
                                    b if b >= 400000 => "480p",
                                    _ => "360p",
                                };
                                let height = parse_height_from_quality(quality);
                                let kbps = if bitrate > 0 {
                                    Some((bitrate / 1000) as u32)
                                } else {
                                    None
                                };
                                streams.push(StreamResult {
                                    url: vu.to_string(),
                                    quality: quality.to_string(),
                                    format: "MP4".into(),
                                    container: Some("mp4".into()),
                                    width: infer_width(height),
                                    height,
                                    fps: Some(30.0),
                                    video_codec: Some("avc1".into()),
                                    audio_codec: Some("aac".into()),
                                    bitrate_kbps: kbps,
                                    file_size_bytes: None,
                                    has_video: true,
                                    has_audio: true,
                                    is_audio_only: false,
                                    is_hdr: false,
                                });
                            }
                        }
                    }
                }
            }

            if !streams.is_empty() {
                final_sort(&mut streams);
                return Ok(VideoInfoResult {
                    title,
                    thumbnail_url: thumbnail,
                    platform: "Twitter/X".into(),
                    duration_seconds: None,
                    author: None,
                    streams,
                });
            }
        }
    }

    Err(anyhow!("لم يتم العثور على فيديو في هذه التغريدة"))
}

fn extract_tweet_id(url: &str) -> Option<String> {
    let re = regex::Regex::new(r"/status(?:es)?/(\d+)").ok()?;
    re.captures(url).map(|c| c[1].to_string())
}

async fn twitter_guest_token(client: &reqwest::Client) -> Result<String> {
    let resp: Value = client
        .post("https://api.twitter.com/1.1/guest/activate.json")
        .header("Authorization", "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA")
        .send().await?
        .json().await?;
    Ok(resp["guest_token"].as_str().unwrap_or("0").to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Facebook
// ─────────────────────────────────────────────────────────────────────────────

// Facebook native extractor removed (broken upstream, delegates to yt-dlp)

// ─────────────────────────────────────────────────────────────────────────────
// Dailymotion
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_dailymotion(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let video_id = url::Url::parse(url)
        .ok()
        .and_then(|u| {
            u.path_segments()
                .map(|s| s.last().unwrap_or("").to_string())
        })
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("معرف الفيديو غير صحيح"))?;

    let data: Value = client
        .get(format!("https://api.dailymotion.com/video/{}?fields=title,thumbnail_480_url,duration,embed_url", video_id))
        .send().await?.json().await?;

    let embed_url = data["embed_url"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| format!("https://www.dailymotion.com/embed/video/{}", video_id));

    Ok(VideoInfoResult {
        title: data["title"]
            .as_str()
            .unwrap_or("Dailymotion Video")
            .to_string(),
        thumbnail_url: data["thumbnail_480_url"].as_str().map(|s| s.to_string()),
        platform: "Dailymotion".into(),
        duration_seconds: data["duration"].as_u64().map(|d| d as u32),
        author: None,
        streams: vec![mk_muxed_stream(embed_url, "HD".into(), "mp4", None)],
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reddit
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_reddit(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let api_url = if url.ends_with('/') {
        format!("{}.json", url)
    } else {
        format!("{}.json", url)
    };

    let data: Value = client
        .get(&api_url)
        .header("Accept", "application/json")
        .send()
        .await?
        .json()
        .await?;

    let post = data
        .as_array()
        .and_then(|a| a.first())
        .and_then(|d| d["data"]["children"].as_array())
        .and_then(|c| c.first())
        .map(|p| &p["data"])
        .ok_or_else(|| anyhow!("لم يتم العثور على البيانات"))?;

    let title = post["title"].as_str().unwrap_or("Reddit Video").to_string();
    let thumbnail = post["thumbnail"]
        .as_str()
        .filter(|s| s.starts_with("http"))
        .map(|s| s.to_string());

    let video_url = post["media"]["reddit_video"]["hls_url"]
        .as_str()
        .or_else(|| post["media"]["reddit_video"]["fallback_url"].as_str())
        .or_else(|| post["url"].as_str())
        .ok_or_else(|| anyhow!("لم يتم العثور على رابط الفيديو"))?
        .to_string();

    let format = if video_url.contains(".m3u8") {
        "m3u8"
    } else {
        "mp4"
    };

    Ok(VideoInfoResult {
        title,
        thumbnail_url: thumbnail,
        platform: "Reddit".into(),
        duration_seconds: None,
        author: post["author"].as_str().map(|s| s.to_string()),
        streams: vec![mk_muxed_stream(video_url, "HD".into(), format, None)],
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// Rumble
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_rumble(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let html = client.get(url).send().await?.text().await?;

    let title =
        extract_meta_property(&html, "og:title").unwrap_or_else(|| "Rumble Video".to_string());
    let thumbnail = extract_meta_property(&html, "og:image");

    // نبحث عن Rumble embed URL
    let embed_re = regex::Regex::new(r#"<iframe[^>]+src="(https://rumble\.com/embed/[^"]+)""#).ok();
    let embed_url = embed_re
        .as_ref()
        .and_then(|re| re.captures(&html))
        .map(|c| c[1].to_string());

    if let Some(embed) = embed_url {
        if let Ok(embed_resp) = client.get(&embed).send().await {
            if let Ok(embed_html) = embed_resp.text().await {
                if let Some(vu) = extract_json_value(&embed_html, "\"url\"") {
                    return Ok(VideoInfoResult {
                        title,
                        thumbnail_url: thumbnail,
                        platform: "Rumble".into(),
                        duration_seconds: None,
                        author: None,
                        streams: vec![mk_muxed_stream(vu, "HD".into(), "mp4", None)],
                    });
                }
            }
        }
    }

    // Fallback: og:video
    let video_url = extract_meta_property(&html, "og:video:secure_url")
        .or_else(|| extract_meta_property(&html, "og:video"))
        .ok_or_else(|| anyhow!("لم يتم العثور على رابط الفيديو"))?;

    Ok(VideoInfoResult {
        title,
        thumbnail_url: thumbnail,
        platform: "Rumble".into(),
        duration_seconds: None,
        author: None,
        streams: vec![mk_muxed_stream(video_url, "HD".into(), "mp4", None)],
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// SoundCloud
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_soundcloud(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let data: Value = client
        .get(format!(
            "https://soundcloud.com/oembed?format=json&url={}",
            urlencoding::encode(url)
        ))
        .send()
        .await?
        .json()
        .await?;

    Ok(VideoInfoResult {
        title: data["title"]
            .as_str()
            .unwrap_or("SoundCloud Track")
            .to_string(),
        thumbnail_url: data["thumbnail_url"].as_str().map(|s| s.to_string()),
        platform: "SoundCloud".into(),
        duration_seconds: None,
        author: data["author_name"].as_str().map(|s| s.to_string()),
        streams: vec![mk_audio_only_stream(
            url.to_string(),
            "128kbps".into(),
            "mp3",
            Some(128),
            None,
        )],
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// Twitch
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_twitch(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;

    // للكليبات: استخرج اسم الكليب
    let clip_re = regex::Regex::new(r"twitch\.tv/\w+/clip/([^?/]+)").ok();
    let clip_slug = clip_re
        .as_ref()
        .and_then(|re| re.captures(url))
        .map(|c| c[1].to_string());

    if let Some(slug) = clip_slug {
        // GQL لاستخراج روابط الكليب
        let gql_body = json!([{
            "operationName": "VideoAccessToken_Clip",
            "variables": { "slug": slug },
            "extensions": { "persistedQuery": {
                "version": 1,
                "sha256Hash": "36b89d2507fce29e5ca551df756d27c1cfe079e2609642b4390aa4c35796eb11"
            }}
        }]);

        let resp: Value = client
            .post("https://gql.twitch.tv/gql")
            .header("Client-Id", "kimne78kx3ncx6brgo4mv6wki5h1ko")
            .json(&gql_body)
            .send()
            .await?
            .json()
            .await?;

        let clip = &resp[0]["data"]["clip"];
        let title = clip["title"].as_str().unwrap_or("Twitch Clip").to_string();
        let thumbnail = clip["thumbnailURL"].as_str().map(|s| s.to_string());

        let mut streams = Vec::new();
        if let Some(qualities) = clip["videoQualities"].as_array() {
            for q in qualities {
                if let (Some(quality), Some(source_url)) =
                    (q["quality"].as_str(), q["sourceURL"].as_str())
                {
                    let q_label = format!("{}p", quality);
                    let fr = q["frameRate"]
                        .as_u64()
                        .map(|v| v as f32)
                        .or_else(|| q["frameRate"].as_f64().map(|v| v as f32));
                    let mut s = mk_muxed_stream(source_url.to_string(), q_label, "mp4", None);
                    s.fps = fr.or(s.fps);
                    s.video_codec = Some("avc1".into());
                    s.is_hdr = false;
                    streams.push(s);
                }
            }
        }

        if !streams.is_empty() {
            final_sort(&mut streams);
            return Ok(VideoInfoResult {
                title,
                thumbnail_url: thumbnail,
                platform: "Twitch".into(),
                duration_seconds: None,
                author: None,
                streams,
            });
        }
    }

    Err(anyhow!(
        "يدعم Twitch الكليبات فقط حالياً — يمكنك لصق رابط كليب (clip)"
    ))
}

// ─────────────────────────────────────────────────────────────────────────────
// Eporner & Specialized adult sites
// ─────────────────────────────────────────────────────────────────────────────

use super::remote_rules;

// دالة مساعدة لجلب Regex سواء من السحاب أو الكود
fn get_regex(platform: &str, key: &str, default: &str) -> regex::Regex {
    let pattern =
        remote_rules::get_remote_pattern(platform, key).unwrap_or_else(|| default.to_string());
    regex::Regex::new(&pattern).unwrap_or_else(|_| regex::Regex::new(default).unwrap())
}

async fn extract_eporner(url: &str) -> Result<VideoInfoResult> {
    let id_re = get_regex("Eporner", "id_re", r"video-([a-zA-Z0-9]+)");
    let video_id = id_re
        .captures(url)
        .map(|c| c[1].to_string())
        .ok_or_else(|| anyhow!("لم يتم العثور على معرف الفيديو"))?;

    // محاولة جلب البيانات باستخدام نظام التجاوز (Bypass) لضمان عدم حدوث Error Sending Request
    let api_url = format!("https://www.eporner.com/api/v2/video/id/{}", video_id);
    let html = match fetch_html_with_bypass(&api_url).await {
        Ok(h) => h,
        Err(_) => fetch_html_with_bypass(url).await?, // إذا فشل الـ API نجرب الصفحة نفسها
    };

    // إذا كان الناتج JSON (من الـ API)
    if html.trim().starts_with('{') {
        if let Ok(data) = serde_json::from_str::<Value>(&html) {
            let title = data["title"]
                .as_str()
                .unwrap_or("Eporner Video")
                .to_string();
            let thumbnail = data["default_thumb"]["src"].as_str().map(|s| s.to_string());

            // للحصول على روابط الفيديو الحقيقية، نحتاج لقراءة الصفحة الأصلية
            if let Ok(page_html) = fetch_html_with_bypass(url).await {
                let mut streams = Vec::new();
                if let Ok(vid_data_re) = regex::Regex::new(r"var\s+vid_data\s*=\s*(\{.*?\});") {
                    if let Some(cap) = vid_data_re.captures(&page_html) {
                        if let Ok(v) = serde_json::from_str::<Value>(&cap[1]) {
                            if let Some(obj) = v.as_object() {
                                for (q, info) in obj {
                                    if let Some(src) = info["src"].as_str() {
                                        streams.push(mk_muxed_stream(
                                            src.to_string(),
                                            q.clone(),
                                            "mp4",
                                            None,
                                        ));
                                    }
                                }
                            }
                        }
                    }
                }
                if !streams.is_empty() {
                    final_sort(&mut streams);
                    return Ok(VideoInfoResult {
                        title,
                        thumbnail_url: thumbnail,
                        platform: "Eporner".into(),
                        duration_seconds: None,
                        author: None,
                        streams,
                    });
                }
            }
        }
    }

    // إذا فشل كل ما سبق، ننتقل للمستخرج العام
    extract_generic(url, "Eporner").await
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic fallback — noembed
// ─────────────────────────────────────────────────────────────────────────────

async fn extract_generic(url: &str, platform: &str) -> Result<VideoInfoResult> {
    extract_generic_recursive(url, platform, 0).await
}

async fn extract_generic_recursive(
    url: &str,
    platform: &str,
    depth: u8,
) -> Result<VideoInfoResult> {
    if depth > 2 {
        return Err(anyhow::anyhow!("Recursion depth limit reached"));
    }

    let uri = url::Url::parse(url)?;
    let host = uri.host_str().unwrap_or("");

    // 1. رابط مباشر لملف فيديو
    let lower_url = url.to_lowercase();
    let video_exts = [
        ".mp4", ".m3u8", ".webm", ".mkv", ".mpd", ".flv", ".m4v", ".avi", ".mov", ".ts",
    ];
    if video_exts.iter().any(|ext| lower_url.ends_with(ext)) {
        let ext = url
            .split('.')
            .last()
            .unwrap_or("mp4")
            .split('?')
            .next()
            .unwrap_or("mp4");
        return Ok(VideoInfoResult {
            title: format!("Direct Video ({})", host),
            thumbnail_url: None,
            platform: "Direct".to_string(),
            duration_seconds: None,
            author: None,
            streams: vec![mk_muxed_stream(url.to_string(), "HD".into(), ext, None)],
        });
    }

    // 2. سحب الصفحة مع نظام تجاوز الحجب التلقائي
    let html = fetch_html_with_bypass(url).await?;

    let title = extract_meta_property(&html, "og:title")
        .or_else(|| extract_meta_property(&html, "twitter:title"))
        .or_else(|| {
            let re = regex::Regex::new(r"(?i)<title>([^<]+)</title>").ok()?;
            re.captures(&html).map(|c| c[1].trim().to_string())
        })
        .unwrap_or_else(|| "Web Video".to_string());

    let thumbnail = extract_meta_property(&html, "og:image")
        .or_else(|| extract_meta_property(&html, "twitter:image"));

    let mut streams = Vec::new();

    // فحص JSON-LD (Schema.org VideoObject)
    if let Ok(json_ld_re) = regex::Regex::new(r#"(?i)@type["']\s*:\s*["']VideoObject["']"#) {
        if json_ld_re.is_match(&html) {
            if let Ok(content_re) =
                regex::Regex::new(r#"(?i)contentUrl["']\s*:\s*["']([^"']+)["']"#)
            {
                for cap in content_re.captures_iter(&html) {
                    streams.push(mk_muxed_stream(
                        cap[1].to_string(),
                        "Full HD".into(),
                        "mp4",
                        None,
                    ));
                }
            }
        }
    }

    // فحص خاص لـ Eporner والمواقع المشابهة (vid_data)
    if let Ok(vid_data_re) = regex::Regex::new(
        r#"(?i)["']src["']\s*:\s*["']((?:https?:)?//[^"']+\.mp4(?:\?[^"']*)?)["']"#,
    ) {
        for cap in vid_data_re.captures_iter(&html) {
            let mut u = cap[1].to_string().replace("\\/", "/");
            if u.starts_with("//") {
                u = format!("https:{}", u);
            }
            streams.push(mk_muxed_stream(u, "HD".into(), "mp4", None));
        }
    }

    // فحص خاص لروابط hls/m3u8 المباشرة
    if let Ok(m3u8_re) =
        regex::Regex::new(r#"(?i)["']((?:https?:)?//[^"']+\.m3u8(?:\?[^"']*)?)["']"#)
    {
        for cap in m3u8_re.captures_iter(&html) {
            let mut u = cap[1].to_string().replace("\\/", "/");
            if u.starts_with("//") {
                u = format!("https:{}", u);
            }
            streams.push(mk_muxed_stream(u, "Auto".into(), "mp4", None));
        }
    }

    // فحص وسوم الميتا
    let meta_patterns = [
        "og:video:secure_url",
        "og:video",
        "twitter:player:stream",
        "twitter:player",
        "og:video:url",
    ];
    for prop in meta_patterns {
        if let Some(vid_url) = extract_meta_property(&html, prop) {
            if vid_url.contains("http")
                && (vid_url.contains(".mp4")
                    || vid_url.contains(".m3u8")
                    || vid_url.contains(".mpd")
                    || vid_url.contains("video"))
            {
                streams.push(mk_muxed_stream(vid_url, "HD (Meta)".into(), "mp4", None));
            }
        }
    }

    // فحص وسوم <video> و <source>
    if let Ok(video_re) = regex::Regex::new(r#"(?i)<video[^>]*\bsrc\s*=\s*["']([^"']+)["']"#) {
        for cap in video_re.captures_iter(&html) {
            streams.push(mk_muxed_stream(
                cap[1].to_string(),
                "SD (Video Tag)".into(),
                "mp4",
                None,
            ));
        }
    }
    if let Ok(source_re) = regex::Regex::new(r#"(?i)<source[^>]*\bsrc\s*=\s*["']([^"']+)["']"#) {
        for cap in source_re.captures_iter(&html) {
            let u = cap[1].to_string();
            streams.push(mk_muxed_stream(u, "SD (Source Tag)".into(), "mp4", None));
        }
    }

    // فحص الروابط داخل الـ Scripts
    if let Ok(script_re) =
        regex::Regex::new(r#"["'](https?://[^"']+\.(?:mp4|m3u8|mpd|webm|m4v)(?:\?[^"']*)?)["']"#)
    {
        for cap in script_re.captures_iter(&html) {
            let u = cap[1].to_string().replace("\\/", "/");
            if !u.contains("ads") && !u.contains("pixel") && !u.contains("analytics") {
                streams.push(mk_muxed_stream(u, "Auto (Script)".into(), "mp4", None));
            }
        }
    }

    // فحص Iframes (الاستخراج المتداخل - Recursive Extraction)
    if let Ok(iframe_re) = regex::Regex::new(r#"(?i)<iframe[^>]*\bsrc\s*=\s*["']([^"']+)["']"#) {
        for cap in iframe_re.captures_iter(&html) {
            let mut iframe_url = cap[1].to_string();
            if iframe_url.starts_with("//") {
                iframe_url = format!("https:{}", iframe_url);
            } else if iframe_url.starts_with('/') {
                if let Ok(abs) = uri.join(&iframe_url) {
                    iframe_url = abs.to_string();
                }
            }

            if iframe_url.starts_with("http")
                && !iframe_url.contains("facebook.com/plugins")
                && !iframe_url.contains("platform.twitter.com")
            {
                debug_log::log_debug(&format!("Deep extraction in iframe: {}", iframe_url));
                if let Ok(nested) =
                    Box::pin(extract_generic_recursive(&iframe_url, platform, depth + 1)).await
                {
                    streams.extend(nested.streams);
                }
            }
        }
    }

    // فحص مفاتيح JSON الشائعة
    let json_keys = [
        "video_url",
        "media_url",
        "url_low",
        "url_high",
        "file_url",
        "stream_url",
        "videoUrl",
        "imageUrl",
        "src",
        "file",
        "url",
    ];
    for key in json_keys {
        let pattern = format!(r#"(?i)["']{}["']\s*[:=]\s*["'](https?://[^"']+)["']"#, key);
        if let Ok(re) = regex::Regex::new(&pattern) {
            for cap in re.captures_iter(&html) {
                let u = cap[1].to_string().replace("\\/", "/");
                if u.contains(".mp4")
                    || u.contains(".m3u8")
                    || u.contains("video")
                    || u.contains("get_file")
                    || u.contains(".mpd")
                {
                    streams.push(mk_muxed_stream(
                        u,
                        format!("Quality ({})", key),
                        "mp4",
                        None,
                    ));
                }
            }
        }
    }

    // فحص شامل لأي رابط فيديو مباشر داخل الصفحة (Universal Scan)
    if let Ok(universal_re) = regex::Regex::new(
        r#"(?i)["']((?:https?:)?//[^"']+\.(?:mp4|m3u8|mpd|webm|m4v)(?:\?[^"']*)?)["']"#,
    ) {
        for cap in universal_re.captures_iter(&html) {
            let mut u = cap[1].to_string().replace("\\/", "/");
            if u.starts_with("//") {
                u = format!("https:{}", u);
            }
            if !u.contains("ads") && !u.contains("pixel") && !u.contains("analytics") {
                streams.push(mk_muxed_stream(u, "Auto Detected".into(), "mp4", None));
            }
        }
    }

    // فحص خاص لمواقع البث التي تضع الجودة في كائن JSON (مثل Eporner)
    // يدعم الصيغ: "1080p": "url" أو "1080p": {"src": "url"}
    if let Ok(qual_json_re) = regex::Regex::new(
        r#"(?i)["'](2160p|1080p|720p|480p|360p|240p|144p|HD|SD)["']\s*[:=]\s*(?:\{[^}]*["']src["']\s*:\s*)?["']((?:https?:)?//[^"']+)["']"#,
    ) {
        for cap in qual_json_re.captures_iter(&html) {
            let q = cap[1].to_string();
            let mut u = cap[2].to_string().replace("\\/", "/");
            if u.starts_with("//") {
                u = format!("https:{}", u);
            }
            streams.push(mk_muxed_stream(u, q, "mp4", None));
        }
    }

    // تنظيف الروابط وتكملتها
    let mut final_streams = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for mut s in streams {
        // تحويل الروابط النسبية إلى مطلقة
        if s.url.starts_with("//") {
            s.url = format!("https:{}", s.url);
        } else if s.url.starts_with('/') {
            if let Ok(abs_url) = uri.join(&s.url) {
                s.url = abs_url.to_string();
            }
        }

        // إزالة الروابط غير الصالحة أو المكررة
        if !s.url.starts_with("http") || seen.contains(&s.url) {
            continue;
        }

        // تصفية روابط الإعلانات المعروفة
        let u_low = s.url.to_lowercase();
        if u_low.contains("ads.") || u_low.contains("/ads/") || u_low.contains("doubleclick") {
            continue;
        }

        seen.insert(s.url.clone());
        final_streams.push(s);
    }

    if final_streams.is_empty() {
        // Fallback to Ultra Engine
        debug_log::log_debug("Static generic failed, falling back to Universal Engine");
        match super::universal_extractor::extract_ultra(url.to_string()).await {
            Ok(ultra_res) => return Ok(ultra_res),
            Err(_) => {
                return Err(anyhow::anyhow!(
                    "لا يمكن استخراج فيديو من هذا الرابط. قد يكون الموقع محمياً أو يستخدم تقنية بث معقدة."
                ));
            }
        }
    }

    final_sort(&mut final_streams);

    Ok(VideoInfoResult {
        title,
        thumbnail_url: thumbnail,
        platform: if platform == "Unknown" {
            "Web".to_string()
        } else {
            platform.to_string()
        },
        duration_seconds: None,
        author: None,
        streams: final_streams,
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// أدوات مشتركة
// ─────────────────────────────────────────────────────────────────────────────

fn extract_meta_property(html: &str, property: &str) -> Option<String> {
    let pattern = format!(
        r#"<meta[^>]+property=["']{property}["'][^>]+content=["']([^"']+)["']|<meta[^>]+content=["']([^"']+)["'][^>]+property=["']{property}["']"#,
        property = regex::escape(property)
    );
    let re = regex::Regex::new(&pattern).ok()?;
    let cap = re.captures(html)?;
    cap.get(1)
        .or_else(|| cap.get(2))
        .map(|m| m.as_str().to_string())
}

fn extract_json_value(text: &str, key: &str) -> Option<String> {
    let pattern = format!(r#""{key}"\s*:\s*"([^"]+)""#, key = regex::escape(key));
    let re = regex::Regex::new(&pattern).ok()?;
    re.captures(text).map(|c| {
        // فكّ ترميز JSON escape sequences
        c[1].replace("\\u0025", "%")
            .replace("\\u0026", "&")
            .replace("\\/", "/")
    })
}

async fn extract_cobalt(url: &str) -> Result<VideoInfoResult> {
    let client = browser_client()?;
    let payload = json!({
        "url": url,
        "vQuality": "max",
        "filenamePattern": "basic"
    });

    let req = client
        .post("https://api.cobalt.tools/api/json")
        .header("Accept", "application/json")
        .header("Content-Type", "application/json")
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36")
        .json(&payload);

    let resp = req.send().await?;
    let status_code = resp.status();
    let text = resp.text().await?;

    if !status_code.is_success() {
        return Err(anyhow!(
            "Cobalt API returned status {}: {}",
            status_code,
            text
        ));
    }

    let data: Value = serde_json::from_str(&text)?;
    let status = data["status"].as_str().unwrap_or("error");

    if status == "error" {
        let text_err = data["text"].as_str().unwrap_or("Cobalt generic error");
        return Err(anyhow!("{}", text_err));
    }

    let mut streams = vec![];

    if status == "stream" || status == "redirect" {
        if let Some(stream_url) = data["url"].as_str() {
            streams.push(mk_muxed_stream(
                stream_url.to_string(),
                "Best".to_string(),
                "mp4",
                None,
            ));
        }
    } else if status == "picker" {
        if let Some(picker) = data["picker"].as_array() {
            for item in picker {
                if let Some(s_url) = item["url"].as_str() {
                    let type_str = item["type"].as_str().unwrap_or("video");
                    if type_str != "video" {
                        continue;
                    }
                    let q = item["quality"].as_str().unwrap_or("Unknown");
                    streams.push(mk_muxed_stream(
                        s_url.to_string(),
                        q.to_string(),
                        "mp4",
                        None,
                    ));
                }
            }
        }
    }

    if streams.is_empty() {
        return Err(anyhow!("No streams found by Cobalt"));
    }

    Ok(VideoInfoResult {
        title: "Cobalt Download".to_string(),
        thumbnail_url: None,
        platform: "Cobalt API".to_string(),
        duration_seconds: None,
        author: None,
        streams,
    })
}
