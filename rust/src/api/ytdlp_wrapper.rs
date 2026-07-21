// ─────────────────────────────────────────────────────────────────────────────
// yt-dlp fallback wrapper
//
// A last-resort extractor that shells out to the yt-dlp binary bundled with
// the app (or downloaded on first launch). Only activated when every native
// Rust extractor has failed. Because yt-dlp is community-maintained and pushes
// fixes within hours of any site change, this makes the app effectively
// "hot-updateable" without shipping a new release.
//
// The binary path must be configured from Dart via `set_ytdlp_binary_path`.
// If no path is set (or the binary is missing), the wrapper cleanly returns
// `Err` so callers can fall through to their own error handling.
// ─────────────────────────────────────────────────────────────────────────────

use std::process::{Command, Stdio};
use std::sync::RwLock;
use crate::api::process_helper::CommandNoWindow;

use anyhow::{anyhow, Context, Result};
use once_cell::sync::Lazy;
use serde_json::Value;

use super::models::{StreamResult, VideoInfoResult};

static YTDLP_PATH: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));
pub static COOKIES_PATH: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

/// FRB entry — Dart passes the resolved path to the yt-dlp binary on startup.
/// Passing an empty string clears the configured path.
#[flutter_rust_bridge::frb(sync)]
pub fn set_ytdlp_binary_path(path: String) {
    let trimmed = path.trim();
    let mut w = YTDLP_PATH.write().expect("YTDLP_PATH poisoned");
    if trimmed.is_empty() {
        *w = None;
    } else {
        *w = Some(trimmed.to_string());
    }
}

/// FRB entry — configure the cookies.txt path to be used by yt-dlp.
#[flutter_rust_bridge::frb(sync)]
pub fn set_cookies_path(path: String) {
    let trimmed = path.trim();
    let mut w = COOKIES_PATH.write().expect("COOKIES_PATH poisoned");
    if trimmed.is_empty() {
        *w = None;
    } else {
        *w = Some(trimmed.to_string());
    }
}

pub static PROXY_URL: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

/// FRB entry — configure the proxy URL to be used by yt-dlp and reqwest.
#[flutter_rust_bridge::frb(sync)]
pub fn set_proxy_url(url: String) {
    let trimmed = url.trim();
    let mut w = PROXY_URL.write().expect("PROXY_URL poisoned");
    if trimmed.is_empty() {
        *w = None;
    } else {
        *w = Some(trimmed.to_string());
    }
}

/// FRB entry — quick health check (is a binary configured and executable?).
#[flutter_rust_bridge::frb(sync)]
pub fn is_ytdlp_available() -> bool {
    let guard = match YTDLP_PATH.read() {
        Ok(g) => g,
        Err(_) => return false,
    };
    let Some(path) = guard.as_ref() else {
        return false;
    };
    std::path::Path::new(path).exists()
}

pub(crate) fn current_path() -> Option<String> {
    YTDLP_PATH.read().ok().and_then(|g| g.clone())
}

/// Extract media info via the yt-dlp binary. Returns a `VideoInfoResult` shaped
/// exactly like the native extractors so it drops in as a fallback.
pub async fn extract_via_ytdlp(url: &str) -> Result<VideoInfoResult> {
    let binary = current_path().ok_or_else(|| anyhow!("yt-dlp binary path not configured"))?;
    if !std::path::Path::new(&binary).exists() {
        return Err(anyhow!("yt-dlp binary not found at {}", binary));
    }

    let url_owned = url.to_string();

    // Run yt-dlp on a blocking thread so we don't block the tokio reactor with
    // a synchronous process spawn (yt-dlp can take several seconds).
    let output = tokio::task::spawn_blocking(move || {
        let mut cmd = Command::new(&binary).no_window();
        cmd.arg("--dump-single-json")
            .arg("--no-warnings")
            .arg("--no-check-certificate")
            .arg("--no-playlist")
            .arg("--skip-download");

        if let Ok(guard) = COOKIES_PATH.read() {
            if let Some(ref cookie_file) = *guard {
                cmd.arg("--cookies").arg(cookie_file);
            }
        }

        if let Ok(guard) = PROXY_URL.read() {
            if let Some(ref proxy) = *guard {
                cmd.arg("--proxy").arg(proxy);
            }
        }

        cmd.arg("--user-agent")
            .arg("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36")
            .arg("--extractor-args")
            .arg("youtube:player_client=tv,mweb;facebook:skip_webpage")
            .arg("--restrict-filenames")
            .arg(&url_owned)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .context("Failed to spawn yt-dlp process")
    })
    .await
    .context("yt-dlp blocking task join failed")??;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "yt-dlp exited with status {} — stderr: {}",
            output.status,
            stderr.chars().take(400).collect::<String>()
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: Value = serde_json::from_str(&stdout).context("yt-dlp JSON parse failed")?;

    parse_ytdlp_json(&json)
}

/// Public helper so Dart can request an audio-only stream URL cleanly.
pub async fn extract_audio_via_ytdlp(url: &str) -> Result<VideoInfoResult> {
    let mut info = extract_via_ytdlp(url).await?;
    info.streams.retain(|s| s.is_audio_only || s.has_audio);
    if info.streams.is_empty() {
        return Err(anyhow!("yt-dlp returned no audio streams"));
    }
    Ok(info)
}

pub async fn extract_playlist_via_ytdlp(url: &str) -> Result<super::models::PlaylistResult> {
    let binary = current_path().ok_or_else(|| anyhow!("yt-dlp binary path not configured"))?;
    if !std::path::Path::new(&binary).exists() {
        return Err(anyhow!("yt-dlp binary not found at {}", binary));
    }

    let url_owned = url.to_string();

    let output = tokio::task::spawn_blocking(move || {
        let mut cmd = Command::new(&binary).no_window();
        cmd.arg("--dump-single-json")
            .arg("--no-warnings")
            .arg("--no-check-certificate")
            .arg("--yes-playlist")
            .arg("--flat-playlist")
            .arg("--skip-download");

        if let Ok(guard) = COOKIES_PATH.read() {
            if let Some(ref cookie_file) = *guard {
                cmd.arg("--cookies").arg(cookie_file);
            }
        }

        if let Ok(guard) = PROXY_URL.read() {
            if let Some(ref proxy) = *guard {
                cmd.arg("--proxy").arg(proxy);
            }
        }

        cmd.arg(&url_owned)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .context("Failed to spawn yt-dlp process")
    })
    .await
    .context("yt-dlp blocking task join failed")??;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "yt-dlp exited with status {} — stderr: {}",
            output.status,
            stderr.chars().take(400).collect::<String>()
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: Value = serde_json::from_str(&stdout).context("yt-dlp JSON parse failed")?;

    parse_ytdlp_playlist_json(&json)
}

fn parse_ytdlp_playlist_json(json: &Value) -> Result<super::models::PlaylistResult> {
    let _type = json.get("_type").and_then(|v| v.as_str());
    if _type != Some("playlist") && _type != Some("multi_video") {
        return Err(anyhow!("URL is not a playlist"));
    }

    let title = json
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown Playlist")
        .to_string();

    let author = json
        .get("uploader")
        .or_else(|| json.get("channel"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let mut items = Vec::new();
    if let Some(entries) = json.get("entries").and_then(|v| v.as_array()) {
        for entry in entries {
            // In flat-playlist, the URL might be in "url" or we might need to construct it from "id" and "url" depending on the extractor. 
            // yt-dlp usually provides "url". If missing, we fallback to id for youtube.
            let v_url = entry.get("url").and_then(|v| v.as_str()).map(|s| s.to_string()).or_else(|| {
                entry.get("id").and_then(|v| v.as_str()).map(|id| format!("https://www.youtube.com/watch?v={}", id))
            });

            if let Some(url) = v_url {
                let v_title = entry
                    .get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Untitled")
                    .to_string();
                
                let thumbnail_url = entry.get("thumbnails").and_then(|v| v.as_array()).and_then(|arr| arr.last()).and_then(|t| t.get("url")).and_then(|u| u.as_str()).map(|s| s.to_string());
                let duration = entry.get("duration").and_then(|v| v.as_f64()).map(|d| d.round() as u32);

                items.push(super::models::PlaylistItem {
                    url,
                    title: v_title,
                    thumbnail_url,
                    duration_seconds: duration,
                });
            }
        }
    }

    if items.is_empty() {
        return Err(anyhow!("Playlist is empty"));
    }

    Ok(super::models::PlaylistResult {
        title,
        author,
        items,
    })
}

fn parse_ytdlp_json(json: &Value) -> Result<VideoInfoResult> {
    let title = json
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("Untitled")
        .to_string();

    let thumbnail_url = json
        .get("thumbnail")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            // Fall back to the highest-resolution entry in `thumbnails`.
            json.get("thumbnails")
                .and_then(|v| v.as_array())
                .and_then(|arr| arr.last())
                .and_then(|t| t.get("url"))
                .and_then(|u| u.as_str())
                .map(|s| s.to_string())
        });

    let platform = json
        .get("extractor_key")
        .and_then(|v| v.as_str())
        .or_else(|| json.get("extractor").and_then(|v| v.as_str()))
        .unwrap_or("Unknown")
        .to_string();

    let duration_seconds = json
        .get("duration")
        .and_then(|v| v.as_f64())
        .map(|d| d.round() as u32);

    let author = json
        .get("uploader")
        .and_then(|v| v.as_str())
        .or_else(|| json.get("channel").and_then(|v| v.as_str()))
        .map(|s| s.to_string());

    // yt-dlp exposes streams under `formats` (progressive + DASH).
    // Some sites (e.g. direct URLs) put the stream at the top level.
    let mut streams: Vec<StreamResult> = Vec::new();

    if let Some(formats) = json.get("formats").and_then(|v| v.as_array()) {
        for f in formats {
            if let Some(s) = format_to_stream(f) {
                // Ignore progressive MP4 formats for YouTube (often trigger bot verification videos)
                let container_lower = s.container.as_deref().unwrap_or("").to_lowercase();
                if platform.to_lowercase() == "youtube" && s.has_video && container_lower == "mp4" {
                    continue;
                }
                streams.push(s);
            }
        }
    }

    if streams.is_empty() {
        if let Some(s) = format_to_stream(json) {
            streams.push(s);
        }
    }

    if streams.is_empty() {
        return Err(anyhow!("yt-dlp returned no usable streams"));
    }

    // Sort: highest-resolution first, prefer muxed streams over separate video/audio.
    streams.sort_by(|a, b| {
        let a_score = stream_score(a);
        let b_score = stream_score(b);
        b_score.cmp(&a_score)
    });

    Ok(VideoInfoResult {
        title,
        thumbnail_url,
        platform,
        duration_seconds,
        author,
        streams,
    })
}

fn stream_score(s: &StreamResult) -> i64 {
    let height = s.height.unwrap_or(0) as i64;
    let bitrate = s.bitrate_kbps.unwrap_or(0) as i64;
    let muxed = if s.has_video && s.has_audio {
        100_000
    } else {
        0
    };
    let hdr = if s.is_hdr { 500 } else { 0 };
    height * 100 + bitrate + muxed + hdr
}

fn format_to_stream(f: &Value) -> Option<StreamResult> {
    let url = f.get("url").and_then(|v| v.as_str())?.to_string();
    if url.is_empty() {
        return None;
    }

    let width = f.get("width").and_then(|v| v.as_u64()).map(|n| n as u32);
    let height = f.get("height").and_then(|v| v.as_u64()).map(|n| n as u32);
    let fps = f.get("fps").and_then(|v| v.as_f64()).map(|f| f as f32);
    let vbr = f.get("vbr").and_then(|v| v.as_f64());
    let abr = f.get("abr").and_then(|v| v.as_f64());
    let tbr = f.get("tbr").and_then(|v| v.as_f64());
    let bitrate_kbps = vbr.or(tbr).or(abr).map(|b| b.round() as u32);

    let file_size_bytes = f
        .get("filesize")
        .and_then(|v| v.as_u64())
        .or_else(|| f.get("filesize_approx").and_then(|v| v.as_u64()));

    let container = f.get("ext").and_then(|v| v.as_str()).map(|s| s.to_string());

    let vcodec = f
        .get("vcodec")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let acodec = f
        .get("acodec")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let has_video = vcodec
        .as_deref()
        .map(|c| !c.is_empty() && c != "none")
        .unwrap_or(false);
    let has_audio = acodec
        .as_deref()
        .map(|c| !c.is_empty() && c != "none")
        .unwrap_or(false);
    let is_audio_only = has_audio && !has_video;

    let quality = f
        .get("format_note")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| height.map(|h| format!("{}p", h)))
        .unwrap_or_else(|| "auto".to_string());

    let format = f
        .get("format")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .unwrap_or_else(|| container.clone().unwrap_or_else(|| "unknown".into()));

    let is_hdr = f
        .get("dynamic_range")
        .and_then(|v| v.as_str())
        .map(|s| s.to_uppercase().contains("HDR"))
        .unwrap_or(false);

    Some(StreamResult {
        url,
        quality,
        format,
        container,
        width,
        height,
        fps,
        video_codec: vcodec.filter(|c| c != "none"),
        audio_codec: acodec.filter(|c| c != "none"),
        bitrate_kbps,
        file_size_bytes,
        has_video,
        has_audio,
        is_audio_only,
        is_hdr,
    })
}
