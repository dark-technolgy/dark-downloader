use super::debug_log;
use super::download_checkpoint::{invalidate_ckpt, prefilled_bytes, ChunkCkptHandle};
use super::models::DownloadResult;
use ahash::AHashMap;
use anyhow::{anyhow, Result};
use futures_util::StreamExt;
use parking_lot::RwLock;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, RANGE, REFERER, USER_AGENT};
use reqwest::Client;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use tokio::io::AsyncWriteExt;

// ─────────────────────────────────────────────────────────────────────────────
// Job registry — لمتابعة التقدم والإلغاء لكل مهمة من Flutter
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone)]
struct JobState {
    downloaded: Arc<AtomicU64>,
    total: Arc<AtomicU64>,
    speed: Arc<AtomicU64>,
    eta: Arc<AtomicU64>,
    phase: Arc<Mutex<String>>,
    cancel: Arc<AtomicBool>,
    start_time: std::time::Instant,
}

impl JobState {
    fn new() -> Self {
        JobState {
            downloaded: Arc::new(AtomicU64::new(0)),
            total: Arc::new(AtomicU64::new(0)),
            speed: Arc::new(AtomicU64::new(0)),
            eta: Arc::new(AtomicU64::new(0)),
            phase: Arc::new(Mutex::new("preparing".into())),
            cancel: Arc::new(AtomicBool::new(false)),
            start_time: std::time::Instant::now(),
        }
    }

    fn set_phase(&self, p: &str) {
        *self.phase.lock().unwrap() = p.to_string();
    }
}

static JOB_REGISTRY: OnceLock<Mutex<AHashMap<String, JobState>>> = OnceLock::new();

fn registry() -> &'static Mutex<AHashMap<String, JobState>> {
    JOB_REGISTRY.get_or_init(|| Mutex::new(AHashMap::new()))
}

fn register_job(job_id: &str) -> JobState {
    let state = JobState::new();
    registry()
        .lock()
        .unwrap()
        .insert(job_id.to_string(), state.clone());
    state
}

fn unregister_job(job_id: &str) {
    registry().lock().unwrap().remove(job_id);
}

pub fn get_job_progress(job_id: String) -> Option<DownloadProgressSnapshot> {
    let reg = registry().lock().unwrap();
    let state = reg.get(&job_id)?;
    let downloaded = state.downloaded.load(Ordering::SeqCst);
    let total = state.total.load(Ordering::SeqCst);
    let speed = state.speed.load(Ordering::SeqCst);
    let eta = state.eta.load(Ordering::SeqCst);
    let phase = state.phase.lock().unwrap().clone();
    let percent = if total > 0 {
        (downloaded as f64 / total as f64 * 100.0).min(100.0)
    } else {
        0.0
    };

    Some(DownloadProgressSnapshot {
        downloaded_bytes: downloaded,
        total_bytes: total,
        speed_bytes_sec: speed,
        eta_seconds: eta,
        percent,
        phase,
    })
}

pub fn cancel_job(job_id: String) {
    if let Some(state) = registry().lock().unwrap().get(&job_id) {
        state.cancel.store(true, Ordering::SeqCst);
    }
}

pub struct DownloadProgressSnapshot {
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub speed_bytes_sec: u64,
    pub eta_seconds: u64,
    pub percent: f64,
    pub phase: String,
}

// ─────────────────────────────────────────────────────────────────────────────
// User-Agent / Referer — حسب مصدر الرابط
// ─────────────────────────────────────────────────────────────────────────────

fn user_agent_for(url: &str) -> String {
    if url.contains("googlevideo.com") || url.contains("youtube.com") {
        "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L) gzip".to_string()
    } else if url.contains("tiktokcdn") || url.contains("tiktok.com") {
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36".to_string()
    } else {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36".to_string()
    }
}

fn referer_for(url: &str) -> String {
    if let Ok(parsed) = url::Url::parse(url) {
        if let Some(host) = parsed.host_str() {
            // استخراج النطاق الأساسي (Domain) لاستخدامه كـ Referer
            if host.contains("googlevideo.com") {
                return "https://www.youtube.com/".to_string();
            }
            if host.contains("tiktokcdn.com") {
                return "https://www.tiktok.com/".to_string();
            }

            // للحالات العامة، نستخدم نفس النطاق كـ Referer
            let scheme = parsed.scheme();
            return format!("{}://{}/", scheme, host);
        }
    }
    "https://www.google.com/".to_string()
}

fn build_client(timeout_secs: u64) -> Result<Client> {
    let mut builder = Client::builder()
        .timeout(std::time::Duration::from_secs(timeout_secs))
        .connect_timeout(std::time::Duration::from_secs(20))
        .pool_idle_timeout(std::time::Duration::from_secs(90))
        // Moderate pool size — fewer idle sockets on low-RAM devices.
        .pool_max_idle_per_host(8)
        .tcp_keepalive(std::time::Duration::from_secs(30));

    // إضافة دعم البروكسي العالمي إذا كان مفعلاً للتحميل
    if let Some(Some(proxy)) = DOWNLOAD_PROXY.get() {
        if let Ok(p) = reqwest::Proxy::all(proxy) {
            builder = builder.proxy(p);
        }
    }

    Ok(builder.build()?)
}

// قائمة وكلاء للتحميل (Chunks) — اختيارية وتحتاج أن تكون سريعة
static DOWNLOAD_PROXY: OnceLock<Option<String>> = OnceLock::new();

pub fn set_download_proxy(proxy_url: Option<String>) {
    let _ = DOWNLOAD_PROXY.set(proxy_url);
    *SHARED_DOWNLOAD_CLIENT.write() = None;
}

fn download_proxy_key() -> Option<String> {
    DOWNLOAD_PROXY.get().and_then(|o| o.clone())
}

struct SharedDlClient {
    proxy_key: Option<String>,
    client: Client,
}

static SHARED_DOWNLOAD_CLIENT: RwLock<Option<SharedDlClient>> = RwLock::new(None);

fn shared_download_client() -> Result<Client> {
    let key = download_proxy_key();
    {
        let guard = SHARED_DOWNLOAD_CLIENT.read();
        if let Some(entry) = guard.as_ref() {
            if entry.proxy_key == key {
                return Ok(entry.client.clone());
            }
        }
    }
    let client = build_client(600)?;
    *SHARED_DOWNLOAD_CLIENT.write() = Some(SharedDlClient {
        proxy_key: key.clone(),
        client: client.clone(),
    });
    Ok(client)
}

fn default_headers(url: &str) -> HeaderMap {
    let mut h = HeaderMap::new();
    let ua = user_agent_for(url);
    let rf = referer_for(url);

    if let Ok(v) = HeaderValue::from_str(&ua) {
        h.insert(USER_AGENT, v);
    }
    if let Ok(v) = HeaderValue::from_str(&rf) {
        h.insert(REFERER, v.clone());
        if let Ok(origin) = HeaderValue::from_str(rf.trim_end_matches('/')) {
            h.insert(HeaderName::from_static("origin"), origin);
        }
    }

    h.insert(
        HeaderName::from_static("accept"),
        HeaderValue::from_static("*/*"),
    );
    h.insert(
        HeaderName::from_static("accept-language"),
        HeaderValue::from_static("en-US,en;q=0.9"),
    );
    h.insert(
        HeaderName::from_static("accept-encoding"),
        HeaderValue::from_static("identity"),
    );
    h
}

// ─────────────────────────────────────────────────────────────────────────────
// HEAD / GET-range probe — يكتشف الحجم ودعم Range
// ─────────────────────────────────────────────────────────────────────────────

async fn probe_url(client: &Client, url: &str) -> Result<(u64, bool)> {
    let mut headers = default_headers(url);
    headers.insert(RANGE, HeaderValue::from_static("bytes=0-0"));

    let r = client.get(url).headers(headers).send().await?;
    let status = r.status();
    let content_range = r
        .headers()
        .get("content-range")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let accept_ranges = r
        .headers()
        .get("accept-ranges")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let content_len = r
        .headers()
        .get("content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok());

    let parsed = if status == reqwest::StatusCode::PARTIAL_CONTENT {
        if let Some(cr) = content_range {
            if let Some(total) = cr.split('/').nth(1).and_then(|s| s.parse::<u64>().ok()) {
                Ok((total, true))
            } else {
                let supports_ranges = accept_ranges
                    .as_ref()
                    .map(|s| s.to_lowercase().contains("bytes"))
                    .unwrap_or(false);
                Ok((content_len.unwrap_or(0), supports_ranges))
            }
        } else {
            let supports_ranges = accept_ranges
                .as_ref()
                .map(|s| s.to_lowercase().contains("bytes"))
                .unwrap_or(false);
            Ok((content_len.unwrap_or(0), supports_ranges))
        }
    } else if status.is_success() {
        let supports_ranges = accept_ranges
            .as_ref()
            .map(|s| s.to_lowercase().contains("bytes"))
            .unwrap_or(false);
        Ok((content_len.unwrap_or(0), supports_ranges))
    } else {
        Err(anyhow!("HTTP {} — {}", status.as_u16(), status.as_str()))
    };

    // استهلاك الجسم يجنّب ترك اتصالات معلّقة مع بعض خوادم CDN.
    let _ = r.bytes().await;
    
    super::debug_log::log_download(&format!(
        "PROBE_URL URL={} STATUS={} PARSED={:?}",
        url, status.as_u16(), parsed
    ));

    parsed
}

fn ensure_expected_total(label: &str, got: u64, expected: u64) -> Result<u64> {
    if expected > 0 && got != expected {
        debug_log::log_download(&format!(
            "WARNING: {}_size_mismatch got {} expected {} (ignoring mismatch due to dynamic streams)",
            label, got, expected
        ));
    }
    Ok(got)
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-threaded chunked download
// ─────────────────────────────────────────────────────────────────────────────

async fn download_chunked(
    client: &Client,
    url: &str,
    output_path: &Path,
    total_bytes: u64,
    connections: u32,
    state: JobState,
) -> Result<u64> {
    if let Some(parent) = output_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    let ckpt_path = super::download_checkpoint::ckpt_file_for(output_path);

    let disk_len = tokio::fs::metadata(output_path)
        .await
        .map(|m| m.len())
        .unwrap_or(0);

    let ckpt_arc: Arc<ChunkCkptHandle> =
        match ChunkCkptHandle::try_load(output_path, url, total_bytes, connections) {
            Some(h) => Arc::new(h),
            None => {
                let _ = tokio::fs::remove_file(&ckpt_path).await;
                Arc::new(ChunkCkptHandle::create_fresh(
                    output_path,
                    url,
                    total_bytes,
                    connections,
                )?)
            }
        };

    let connections = connections.clamp(1, 12);
    let conn_u64 = connections as u64;
    let chunk_size = total_bytes.div_ceil(conn_u64);

    let chunks_done = ckpt_arc.chunks_done_set();

    let mut prefilled = 0u64;
    for slot in 0..connections {
        let part_path = output_path.with_extension(format!("part{}", slot));
        prefilled += tokio::fs::metadata(&part_path).await.map(|m| m.len()).unwrap_or(0);
    }
    
    let mode = if chunks_done.is_empty() {
        "fresh"
    } else {
        "resume"
    };
    super::debug_log::log_download(&format!(
        "chunked mode={mode} chunks_done={} prefilled={}B total={}B disk_len={disk_len}",
        chunks_done.len(),
        prefilled,
        total_bytes
    ));

    let mut tasks = Vec::new();
    let mut part_files = Vec::new();

    for slot in 0..connections {
        let start = (slot as u64) * chunk_size;
        let end = (((slot as u64) + 1) * chunk_size - 1).min(total_bytes.saturating_sub(1));
        if start > end {
            continue;
        }

        let part_path = output_path.with_extension(format!("part{}", slot));
        part_files.push(part_path.clone());

        if chunks_done.contains(&slot) {
            continue;
        }

        let url_owned = url.to_string();
        let client = client.clone();
        let st = state.clone();
        let ckpt = Arc::clone(&ckpt_arc);

        tasks.push(tokio::spawn(async move {
            download_chunk(
                &client,
                &url_owned,
                start,
                end,
                part_path,
                st,
                slot,
                Some(ckpt),
            )
            .await
        }));
    }

    for t in tasks {
        match t.await {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                // Do NOT delete part files — they are needed for resume.
                // Checkpoint is also preserved so completed chunks aren't re-downloaded.
                return Err(e);
            }
            Err(e) => {
                return Err(anyhow::anyhow!("join: {}", e));
            }
        }
    }

    // Merge part files sequentially to ensure clean file without null gaps
    let mut final_file = tokio::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(output_path)
        .await?;

    let mut final_size = 0u64;
    for part_path in &part_files {
        if !part_path.exists() {
            continue;
        }
        let mut part = tokio::fs::File::open(part_path).await?;
        let copied = tokio::io::copy(&mut part, &mut final_file).await?;
        final_size += copied;
    }
    final_file.flush().await?;
    drop(final_file);

    // Validate merged file — allow small tolerance for dynamic streams (YouTube, etc.)
    // Some servers report Content-Length that differs slightly from actual data served.
    let tolerance = (total_bytes / 200).max(8192); // 0.5% or 8KB, whichever is larger
    if total_bytes > 0 && final_size + tolerance < total_bytes {
        super::debug_log::log_download(&format!(
            "ERROR: merged file {}B < expected {}B (diff={}B, tolerance={}B)",
            final_size, total_bytes, total_bytes - final_size, tolerance
        ));
        // Delete only the incomplete merged file — keep part files for retry
        let _ = tokio::fs::remove_file(output_path).await;
        return Err(anyhow::anyhow!(
            "download incomplete: got {} of {} bytes",
            final_size, total_bytes
        ));
    } else if final_size < total_bytes {
        // Within tolerance — accept but log
        super::debug_log::log_download(&format!(
            "WARNING: merged file {}B vs expected {}B (within tolerance, accepting)",
            final_size, total_bytes
        ));
    }

    // Success — cleanup part files and checkpoint
    for part_path in &part_files {
        let _ = tokio::fs::remove_file(part_path).await;
    }

    ckpt_arc.remove_file();

    Ok(final_size)
}

async fn download_chunk(
    client: &Client,
    url: &str,
    start: u64,
    end: u64,
    part_path: std::path::PathBuf,
    state: JobState,
    chunk_slot: u32,
    ckpt: Option<Arc<ChunkCkptHandle>>,
) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 6;
    let mut attempt = 0u32;
    
    let initial_len = tokio::fs::metadata(&part_path).await.map(|m| m.len()).unwrap_or(0);
    let mut offset = start + initial_len;
    
    if offset > end {
        if let Some(ref c) = ckpt {
            let _ = c.mark_chunk_done(chunk_slot);
        }
        return Ok(());
    }

    loop {
        if state.cancel.load(Ordering::SeqCst) {
            return Err(anyhow::anyhow!("cancelled"));
        }

        let mut headers = default_headers(url);
        headers.insert(
            reqwest::header::RANGE,
            reqwest::header::HeaderValue::from_str(&format!("bytes={}-{}", offset, end))?,
        );

        let resp = match client.get(url).headers(headers).send().await {
            Ok(r) => r,
            Err(e) => {
                attempt += 1;
                if attempt >= MAX_ATTEMPTS {
                    return Err(anyhow::anyhow!("{}", e));
                }
                let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
                tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
                continue;
            }
        };

        if resp.status() == reqwest::StatusCode::RANGE_NOT_SATISFIABLE {
            if let Some(ref c) = ckpt {
                let _ = c.mark_chunk_done(chunk_slot);
            }
            return Ok(());
        }

        if !resp.status().is_success() && resp.status() != reqwest::StatusCode::PARTIAL_CONTENT {
            attempt += 1;
            if attempt >= MAX_ATTEMPTS {
                return Err(anyhow::anyhow!("chunk {}..={}: HTTP {}", start, end, resp.status()));
            }
            let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
            continue;
        }

        let mut actual_end = end;
        if resp.status() == reqwest::StatusCode::PARTIAL_CONTENT {
            if let Some(cr) = resp.headers().get(reqwest::header::CONTENT_RANGE).and_then(|h| h.to_str().ok()) {
                if let Some(range_part) = cr.strip_prefix("bytes ").and_then(|s| s.split('/').next()) {
                    if let Some(dash) = range_part.find('-') {
                        if let Ok(e) = range_part[dash + 1..].parse::<u64>() {
                            actual_end = actual_end.min(e);
                        }
                    }
                }
            }
        }

        let mut file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&part_path)
            .await?;

        let mut stream = resp.bytes_stream();
        let mut write_offset = offset;
        let mut stream_ended_cleanly = false;

        loop {
            if state.cancel.load(Ordering::SeqCst) {
                return Err(anyhow::anyhow!("cancelled"));
            }
            match stream.next().await {
                None => {
                    stream_ended_cleanly = true;
                    break;
                }
                Some(Err(e)) => {
                    super::debug_log::log_download(&format!("stream error at {}: {}", write_offset, e));
                    attempt += 1;
                    if attempt >= MAX_ATTEMPTS {
                        return Err(anyhow::anyhow!("stream: {}", e));
                    }
                    let delay_ms = (300u64 * (1u64 << attempt.min(4))).min(10_000);
                    tokio::time::sleep(std::time::Duration::from_millis(delay_ms))
                        .await;
                    break;
                }
                Some(Ok(mut bytes)) => {
                    if bytes.is_empty() {
                        continue;
                    }
                    
                    let mut is_last = false;
                    let len = bytes.len() as u64;
                    if write_offset + len > actual_end + 1 {
                        let allowed = (actual_end + 1).saturating_sub(write_offset);
                        if allowed > 0 {
                            bytes = bytes.slice(0..allowed as usize);
                        } else {
                            break;
                        }
                        is_last = true;
                    }
                    
                    tokio::io::AsyncWriteExt::write_all(&mut file, &bytes).await?;
                    let written_len = bytes.len() as u64;
                    write_offset += written_len;
                    let current_total = state.downloaded.fetch_add(written_len, Ordering::SeqCst) + written_len;
                    update_speed(&state, current_total);
                    
                    if is_last || write_offset > actual_end {
                        stream_ended_cleanly = true;
                        break;
                    }
                }
            }
        }

        let _ = file.flush().await;
        drop(file);

        // Check if chunk is fully downloaded
        if write_offset > actual_end {
            if let Some(ref c) = ckpt {
                let _ = c.mark_chunk_done(chunk_slot);
            }
            return Ok(());
        }

        // Stream ended without error — verify part file actually has all the bytes
        if stream_ended_cleanly {
            let part_len = tokio::fs::metadata(&part_path)
                .await
                .map(|m| m.len())
                .unwrap_or(0);
            let expected_len = end - start + 1;
            // Accept if part is complete or nearly complete (within 0.5% or 4KB)
            let chunk_tolerance = (expected_len / 200).max(4096);
            if part_len + chunk_tolerance >= expected_len {
                // Part file is complete (or close enough — merged validation catches gaps)
                if let Some(ref c) = ckpt {
                    let _ = c.mark_chunk_done(chunk_slot);
                }
                return Ok(());
            }
            // Stream ended "cleanly" but part is significantly incomplete — server closed early
            super::debug_log::log_download(&format!(
                "chunk {}..={}: stream ended cleanly but part incomplete ({}B / {}B), retrying",
                start, end, part_len, expected_len
            ));
        }

        offset = write_offset;
        attempt += 1;
        if attempt >= MAX_ATTEMPTS {
            let part_len = tokio::fs::metadata(&part_path)
                .await
                .map(|m| m.len())
                .unwrap_or(0);
            let expected_len = end - start + 1;
            // If we got most of the data (>= 95%), accept it — the merge validation
            // will catch truly incomplete downloads with its own tolerance.
            if part_len > 0 && part_len * 100 / expected_len >= 95 {
                super::debug_log::log_download(&format!(
                    "chunk {}..={}: accepting near-complete part ({}B / {}B = {}%) after {} attempts",
                    start, end, part_len, expected_len,
                    part_len * 100 / expected_len, MAX_ATTEMPTS
                ));
                if let Some(ref c) = ckpt {
                    let _ = c.mark_chunk_done(chunk_slot);
                }
                return Ok(());
            }
            return Err(anyhow::anyhow!(
                "incomplete chunk {}..={}: got {}B of {}B after {} attempts",
                start, end, part_len, expected_len, MAX_ATTEMPTS
            ));
        }
        let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
        tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
    }
}


fn update_speed(state: &JobState, total_bytes: u64) {
    let elapsed = state.start_time.elapsed().as_secs_f64().max(0.001);
    let speed = (total_bytes as f64 / elapsed) as u64;
    state.speed.store(speed, Ordering::SeqCst);

    let total = state.total.load(Ordering::SeqCst);
    if total > total_bytes && speed > 0 {
        state
            .eta
            .store((total - total_bytes) / speed, Ordering::SeqCst);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single-stream download
// ─────────────────────────────────────────────────────────────────────────────

async fn download_single(
    client: &Client,
    url: &str,
    output_path: &Path,
    state: JobState,
) -> Result<u64> {
    const MAX_ATTEMPTS: u32 = 6;
    let mut attempt = 0;
    
    loop {
        if let Some(parent) = output_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let mut total = 0u64;
        let headers = default_headers(url);

        let resp = match client.get(url).headers(headers).send().await {
            Ok(r) => r,
            Err(e) => {
                attempt += 1;
                if attempt >= MAX_ATTEMPTS { return Err(anyhow::anyhow!("HTTP: {}", e)); }
                let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
                tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
                continue;
            }
        };

        if !resp.status().is_success() {
            attempt += 1;
            if attempt >= MAX_ATTEMPTS { return Err(anyhow::anyhow!("HTTP {}", resp.status())); }
            let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
            continue;
        }

        let mut file = tokio::fs::File::create(output_path).await?;
        let mut stream = resp.bytes_stream();
        let mut error_occurred = false;

        while let Some(next) = stream.next().await {
            if state.cancel.load(Ordering::SeqCst) {
                return Err(anyhow::anyhow!("cancelled"));
            }
            match next {
                Ok(bytes) => {
                    if !bytes.is_empty() {
                        file.write_all(&bytes).await?;
                        let len = bytes.len() as u64;
                        total += len;
                        let global_total = state.downloaded.fetch_add(len, Ordering::SeqCst) + len;
                        update_speed(&state, global_total);
                    }
                }
                Err(e) => {
                    super::debug_log::log_download(&format!("stream error in download_single: {}", e));
                    error_occurred = true;
                    break;
                }
            }
        }
        
        file.flush().await?;
        
        if error_occurred {
            attempt += 1;
            if attempt >= MAX_ATTEMPTS {
                return Err(anyhow::anyhow!("incomplete single stream after {} bytes", total));
            }
            let delay_ms = (500u64 * (1u64 << attempt.min(4))).min(15_000);
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
            continue; // restart the download from 0
        }
        
        return Ok(total);
    }
}

/// Resume a single-stream download using `Range: bytes=<existing>-` (must get HTTP 206).
async fn download_single_resume(
    client: &Client,
    url: &str,
    output_path: &Path,
    state: &JobState,
    resume_from: u64,
    expected_total: u64,
) -> Result<u64> {
    if resume_from >= expected_total {
        return Ok(expected_total);
    }

    let mut headers = default_headers(url);
    headers.insert(
        RANGE,
        HeaderValue::from_str(&format!("bytes={resume_from}-"))
            .map_err(|e| anyhow::anyhow!("range header: {}", e))?,
    );

    let resp = client.get(url).headers(headers).send().await?;
    if resp.status() != reqwest::StatusCode::PARTIAL_CONTENT {
        return Err(anyhow::anyhow!(
            "resume_expected_http_206_got_{}",
            resp.status().as_u16()
        ));
    }

    let mut file = tokio::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(output_path)
        .await?;

    let mut stream = resp.bytes_stream();
    let mut added = 0u64;

    while let Some(next) = stream.next().await {
        if state.cancel.load(Ordering::SeqCst) {
            return Err(anyhow::anyhow!("cancelled"));
        }
        let bytes = next.map_err(|e| anyhow::anyhow!("read: {}", e))?;
        if bytes.is_empty() {
            continue;
        }
        file.write_all(&bytes).await?;
        let len = bytes.len() as u64;
        added += len;
        let cur = state.downloaded.fetch_add(len, Ordering::SeqCst) + len;
        update_speed(state, cur);
    }

    file.flush().await?;

    let got = resume_from + added;
    if got != expected_total {
        super::debug_log::log_download(&format!(
            "WARNING: resume_size_mismatch got {} expected {} (ignoring mismatch due to dynamic streams)",
            got, expected_total
        ));
    }
    Ok(got)
}

// ─────────────────────────────────────────────────────────────────────────────
// HLS (m3u8)
// ─────────────────────────────────────────────────────────────────────────────

fn is_hls_url(url: &str) -> bool {
    let u = url.split('?').next().unwrap_or(url);
    u.ends_with(".m3u8") || u.contains(".m3u8?") || u.contains("/hls/")
}

async fn download_hls(
    client: &Client,
    url: &str,
    output_path: &Path,
    state: JobState,
) -> Result<u64> {
    debug_log::log_download(&format!("HLS: start url={}", url));
    let headers = default_headers(url);
    let manifest = client
        .get(url)
        .headers(headers.clone())
        .send()
        .await?
        .text()
        .await?;

    // master playlist؟ اختر أعلى جودة
    let playlist_url = if manifest.contains("#EXT-X-STREAM-INF") {
        let mut best: Option<(u64, String)> = None;
        let lines: Vec<&str> = manifest.lines().collect();
        for i in 0..lines.len() {
            if lines[i].starts_with("#EXT-X-STREAM-INF") {
                let bandwidth = lines[i]
                    .split(',')
                    .find(|s| s.contains("BANDWIDTH="))
                    .and_then(|s| s.split('=').nth(1))
                    .and_then(|s| s.split(',').next())
                    .and_then(|s| s.parse::<u64>().ok())
                    .unwrap_or(0);
                if let Some(&next) = lines.get(i + 1) {
                    if !next.starts_with('#') && !next.trim().is_empty() {
                        let abs = resolve_url(url, next.trim());
                        if best.as_ref().map(|(b, _)| *b < bandwidth).unwrap_or(true) {
                            best = Some((bandwidth, abs));
                        }
                    }
                }
            }
        }
        best.map(|(_, u)| u).unwrap_or_else(|| url.to_string())
    } else {
        url.to_string()
    };

    let media_playlist = if playlist_url != url {
        let h = default_headers(&playlist_url);
        client
            .get(&playlist_url)
            .headers(h)
            .send()
            .await?
            .text()
            .await?
    } else {
        manifest
    };

    let segments: Vec<String> = media_playlist
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|s| resolve_url(&playlist_url, s.trim()))
        .collect();

    debug_log::log_download(&format!("HLS: {} segments", segments.len()));
    if segments.is_empty() {
        return Err(anyhow!("HLS playlist فارغ"));
    }

    if let Some(parent) = output_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    // نستخدم إجمالي تقديري بناءً على segments للتقدير
    state.total.store(segments.len() as u64, Ordering::SeqCst);

    let mut file = tokio::fs::File::create(output_path).await?;
    let mut total_bytes = 0u64;

    let concurrency = 4usize;
    let mut idx = 0usize;
    let total_segs = segments.len();

    while idx < total_segs {
        if state.cancel.load(Ordering::SeqCst) {
            return Err(anyhow!("cancelled"));
        }

        let end = (idx + concurrency).min(total_segs);
        let mut batch = Vec::with_capacity(end - idx);

        for i in idx..end {
            let seg_url = segments[i].clone();
            let cl = client.clone();
            batch.push(tokio::spawn(async move {
                let h = default_headers(&seg_url);
                let mut last_err = anyhow!("init");
                for attempt in 0..4u32 {
                    match cl.get(&seg_url).headers(h.clone()).send().await {
                        Ok(r) if r.status().is_success() => match r.bytes().await {
                            Ok(b) => return Ok(b.to_vec()),
                            Err(e) => last_err = anyhow!("read: {}", e),
                        },
                        Ok(r) => last_err = anyhow!("HTTP {}", r.status()),
                        Err(e) => last_err = anyhow!("net: {}", e),
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(
                        300 * (attempt + 1) as u64,
                    ))
                    .await;
                }
                Err(last_err)
            }));
        }

        for (j, t) in batch.into_iter().enumerate() {
            let bytes = t.await.map_err(|e| anyhow!("join: {}", e))??;
            file.write_all(&bytes).await?;
            total_bytes += bytes.len() as u64;
            state
                .downloaded
                .store((idx + j + 1) as u64, Ordering::SeqCst);
            update_speed(&state, total_bytes);
        }

        idx = end;
    }

    file.flush().await?;
    debug_log::log_download(&format!("HLS: done total={}B", total_bytes));
    Ok(total_bytes)
}

fn resolve_url(base: &str, rel: &str) -> String {
    if rel.starts_with("http://") || rel.starts_with("https://") {
        return rel.to_string();
    }
    if let Ok(b) = url::Url::parse(base) {
        if let Ok(abs) = b.join(rel) {
            return abs.to_string();
        }
    }
    rel.to_string()
}

// ─────────────────────────────────────────────────────────────────────────────
// مسارات الصوت الجانبي + الدمج بـ FFmpeg (سطح المكتب) — كل المنطق هنا وليس في Dart
// ─────────────────────────────────────────────────────────────────────────────

fn audio_sidecar_path_from_output(output_path: &Path, audio_url: &str) -> PathBuf {
    let stem = output_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("audio");
    let ext = output_path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("mp4");
    let ae = audio_ext_from_url(audio_url, ext);
    output_path.with_file_name(format!("{stem}.audio.{ae}"))
}

/// ملف مؤقت للدمج لتفادي الكتابة فوق مخرجات الفيديو أثناء القراءة.
fn mux_temp_path(output_path: &Path) -> PathBuf {
    let stem = output_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("out");
    let ext = output_path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("mp4");
    // Use same container as output — webm stays webm, everything else uses mp4
    let mux_ext = if ext.eq_ignore_ascii_case("webm") { "webm" } else { "mp4" };
    output_path.with_file_name(format!("{stem}.ffmpeg.muxing.{mux_ext}"))
}

fn merged_final_path(output_path: &Path) -> PathBuf {
    let stem = output_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("out");
    let ext = output_path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("mp4");
    // Preserve container: webm→webm, everything else→mp4
    let final_ext = if ext.eq_ignore_ascii_case("webm") { "webm" } else { "mp4" };
    output_path.with_file_name(format!("{stem}.{final_ext}"))
}

async fn cleanup_download_artifacts(output_path: &Path, audio_url: Option<&str>) {
    let stem = output_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    let parent = output_path.parent().unwrap_or_else(|| Path::new("."));

    if stem.is_empty() {
        return;
    }

    super::download_checkpoint::invalidate_ckpt(output_path);
    let _ = tokio::fs::remove_file(output_path).await;

    if let Some(au) = audio_url {
        let ap = audio_sidecar_path_from_output(output_path, au);
        super::download_checkpoint::invalidate_ckpt(&ap);
        let _ = tokio::fs::remove_file(&ap).await;
    }

    let _ = tokio::fs::remove_file(parent.join(format!("{stem}.ffmpeg.muxing.mp4"))).await;

    if let Ok(mut read) = tokio::fs::read_dir(parent).await {
        let prefix_audio = format!("{stem}.audio.");
        let prefix_part = format!("{stem}.part");
        let prefix_ckpt = format!("{stem}.ckpt");
        while let Ok(Some(e)) = read.next_entry().await {
            if let Ok(name) = e.file_name().into_string() {
                if name.starts_with(&prefix_audio) 
                    || name.starts_with(&prefix_part) 
                    || name.starts_with(&prefix_ckpt)
                    || name.ends_with(".part")
                    || name.contains(".part") // to catch {stem}.audio.part0
                {
                    // Ensure we only delete files related to this specific stem
                    if name.starts_with(stem) {
                        super::download_checkpoint::invalidate_ckpt(&e.path());
                        let _ = tokio::fs::remove_file(e.path()).await;
                    }
                }
            }
        }
    }
}

fn run_ffmpeg_once(ffmpeg: &str, args: &[&str]) -> std::result::Result<(), String> {
    let out = std::process::Command::new(ffmpeg)
        .args(args)
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).to_string())
    }
}

fn mux_blocking(ffmpeg: &str, video: &Path, audio: &Path, out_tmp: &Path) -> Result<()> {
    let vs = video
        .to_str()
        .ok_or_else(|| anyhow!("video path is not valid UTF-8"))?;
    let aus = audio
        .to_str()
        .ok_or_else(|| anyhow!("audio path is not valid UTF-8"))?;
    let os = out_tmp
        .to_str()
        .ok_or_else(|| anyhow!("mux output path is not valid UTF-8"))?;
    if let Some(p) = out_tmp.parent() {
        std::fs::create_dir_all(p).ok();
    }

    let ext = out_tmp
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("mp4");
    let try_copy = [
        "-y",
        "-i",
        vs,
        "-i",
        aus,
        "-c",
        "copy",
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-shortest",
        os,
    ];
    let try_aac_in_mp4 = [
        "-y",
        "-i",
        vs,
        "-i",
        aus,
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-shortest",
        "-movflags",
        "+faststart",
        os,
    ];

    // MP4/MOV: جرّب AAC أولاً — ‎-c copy‎ قد يلصق Opus/EAC3 في MP4 فيقبله FFmpeg لكن مشغّلات ويندوز الافتراضية تصمت.
    if !ext.eq_ignore_ascii_case("webm") {
        if run_ffmpeg_once(ffmpeg, &try_aac_in_mp4).is_ok() {
            return Ok(());
        }
        let _ = std::fs::remove_file(out_tmp);
        if run_ffmpeg_once(ffmpeg, &try_copy).is_ok() {
            return Ok(());
        }
    } else {
        if run_ffmpeg_once(ffmpeg, &try_copy).is_ok() {
            return Ok(());
        }
        let _ = std::fs::remove_file(out_tmp);
        if run_ffmpeg_once(ffmpeg, &try_aac_in_mp4).is_ok() {
            return Ok(());
        }
    }
    let _ = std::fs::remove_file(out_tmp);

    let (cv, ca) = if ext.eq_ignore_ascii_case("webm") {
        ("libvpx-vp9", "libopus")
    } else {
        ("libx264", "aac")
    };
    let try3 = [
        "-y",
        "-i",
        vs,
        "-i",
        aus,
        "-c:v",
        cv,
        "-preset",
        "veryfast",
        "-c:a",
        ca,
        "-b:a",
        "192k",
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-shortest",
        "-movflags",
        "+faststart",
        os,
    ];
    run_ffmpeg_once(ffmpeg, &try3).map_err(|e| anyhow!("ffmpeg mux: {e}"))
}

async fn run_ffmpeg_mux_attempts(
    ffmpeg: &str,
    video: &Path,
    audio: &Path,
    out_tmp: &Path,
) -> Result<()> {
    let ff = ffmpeg.to_string();
    let v = video.to_path_buf();
    let a = audio.to_path_buf();
    let o = out_tmp.to_path_buf();
    tokio::task::spawn_blocking(move || mux_blocking(&ff, &v, &a, &o))
        .await
        .map_err(|e| anyhow!("mux join: {e}"))?
}

/// Tries the path from Flutter first, then plain `ffmpeg` on PATH (desktop packaging quirks).
async fn run_ffmpeg_mux_with_fallback(
    preferred: Option<&str>,
    video: &Path,
    audio: &Path,
    out_tmp: &Path,
) -> Result<()> {
    let mut candidates: Vec<String> = Vec::new();
    if let Some(p) = preferred {
        let t = p.trim();
        if !t.is_empty() {
            candidates.push(t.to_string());
        }
    }
    candidates.push("ffmpeg".into());

    let mut seen = std::collections::HashSet::<String>::new();
    candidates.retain(|c| seen.insert(c.clone()));

    let mut last = anyhow!("ffmpeg mux: no candidate");
    for ff in candidates {
        match run_ffmpeg_mux_attempts(&ff, video, audio, out_tmp).await {
            Ok(()) => return Ok(()),
            Err(e) => last = e,
        }
    }
    Err(last)
}

// ─────────────────────────────────────────────────────────────────────────────
// الدالة البسيطة (backwards compatible) — تدعم تمرير معلومات إضافية عبر URL
//
// لتجنّب الحاجة لإعادة توليد FRB، نمرّر حقولًا إضافية بعد عنوان الفيديو:
//   الحديث: فاصل RS \u{001e} (لا يظهر في URL الحقيقية) يمنع كسر العناوين الطويلة التي تحوي "|"
//   القديم: "|||" ما زال مدعومًا للتوافق
//   url = "<video_url><SEP>AUDIO:<audio_url><SEP>JOB:<job_id><SEP>CONN:<n><SEP>FFMPEG:<exe>"
// FFMPEG اختياري: عند توفره بعد تحميل فيديو+صوت يُنفَّذ الدمج هنا ويُعاد ملف mp4 واحد.
// ─────────────────────────────────────────────────────────────────────────────

pub async fn download_file(url: String, output_path: String) -> Result<DownloadResult, String> {
    let (video_url, audio_url, job_id, conn, ffmpeg_path) = parse_packed_url(&url);
    download_and_finalize(
        video_url,
        output_path,
        audio_url,
        job_id,
        conn.unwrap_or(8),
        ffmpeg_path,
    )
    .await
    .map_err(|e| e.to_string())
}

fn parse_packed_url(packed: &str) -> (String, Option<String>, String, Option<u32>, Option<String>) {
    const RS: char = '\u{001e}';
    let parts: Vec<&str> = if packed.contains(RS) {
        packed.split(RS).collect()
    } else {
        packed.split("|||").collect()
    };
    let url = parts[0].to_string();
    let mut audio_url: Option<String> = None;
    let mut job_id = String::new();
    let mut conn: Option<u32> = None;
    let mut ffmpeg_path: Option<String> = None;

    for p in parts.iter().skip(1) {
        if let Some(rest) = p.strip_prefix("AUDIO:") {
            let s = rest.to_string();
            if !s.is_empty() {
                audio_url = Some(s);
            }
        } else if let Some(rest) = p.strip_prefix("JOB:") {
            job_id = rest.to_string();
        } else if let Some(rest) = p.strip_prefix("CONN:") {
            conn = rest.parse::<u32>().ok();
        } else if let Some(rest) = p.strip_prefix("FFMPEG:") {
            let s = rest.trim().to_string();
            if !s.is_empty() {
                ffmpeg_path = Some(s);
            }
        }
    }
    (url, audio_url, job_id, conn, ffmpeg_path)
}

// ─────────────────────────────────────────────────────────────────────────────
// الدالة المتقدمة — مع job_id للتقدم، audio_url للدمج
// ─────────────────────────────────────────────────────────────────────────────

pub async fn download_file_v2(
    url: String,
    output_path: String,
    audio_url: Option<String>,
    job_id: String,
    connections: u32,
    mux_ffmpeg: Option<String>,
) -> Result<DownloadResult> {
    download_and_finalize(url, output_path, audio_url, job_id, connections, mux_ffmpeg).await
}

async fn download_and_finalize(
    url: String,
    output_path: String,
    audio_url: Option<String>,
    job_id: String,
    connections: u32,
    mux_ffmpeg: Option<String>,
) -> Result<DownloadResult> {
    let out_buf = PathBuf::from(&output_path);
    let state = if job_id.is_empty() {
        JobState::new()
    } else {
        register_job(&job_id)
    };

    let dl = download_inner(
        &url,
        &out_buf,
        audio_url.as_deref(),
        connections,
        state.clone(),
    )
    .await;

    if let Err(ref e) = dl {
        debug_log::log_download(&format!("download_inner failed: {}", e));
        let err_str = e.to_string();
        // Only destroy files on explicit cancellation — network errors preserve
        // part files and checkpoints so the user can retry/resume.
        if err_str.contains("cancelled") {
            cleanup_download_artifacts(&out_buf, audio_url.as_deref()).await;
        }
        if !job_id.is_empty() {
            unregister_job(&job_id);
        }
        return Err(dl.unwrap_err());
    }


    if !job_id.is_empty() {
        unregister_job(&job_id);
    }

    if let (Some(ref au), Some(ref ff)) = (&audio_url, &mux_ffmpeg) {
        if !ff.is_empty() {
            state.set_phase("merging");
            let video_path = out_buf.clone();
            let audio_path = audio_sidecar_path_from_output(&out_buf, au.as_str());
            let mux_tmp = mux_temp_path(&out_buf);
            let merged_final = merged_final_path(&out_buf);

            if !audio_path.is_file() {
                cleanup_download_artifacts(&out_buf, Some(au.as_str())).await;
                return Err(anyhow!(
                    "mux: audio sidecar missing at {}",
                    audio_path.display()
                ));
            }

            let _ = tokio::fs::remove_file(&mux_tmp).await;
            match run_ffmpeg_mux_with_fallback(
                Some(ff.as_str()),
                &video_path,
                &audio_path,
                &mux_tmp,
            )
            .await
            {
                Ok(()) => {}
                Err(e) => {
                    // أبقِ الفيديو والصوت المحمّلين — يمكن لـ Flutter إعادة محاولة الدمج.
                    let _ = tokio::fs::remove_file(&mux_tmp).await;
                    debug_log::log_download(&format!(
                        "rust mux failed; leaving sidecar for Dart fallback: {e}"
                    ));
                }
            }

            if !mux_tmp.is_file() {
                let meta = tokio::fs::metadata(&output_path).await?;
                state.set_phase("done");
                return Ok(DownloadResult {
                    file_path: output_path,
                    file_size_bytes: meta.len(),
                });
            }

            let _ = tokio::fs::remove_file(&merged_final).await;
            let mut rename_ok = false;
            for _ in 0..5 {
                if tokio::fs::rename(&mux_tmp, &merged_final).await.is_ok() {
                    rename_ok = true;
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
            if !rename_ok {
                let _ = tokio::fs::remove_file(&mux_tmp).await;
                return Err(anyhow!("mux rename: Failed after 5 retries (file might be locked)"));
            }
            if video_path != merged_final {
                let _ = tokio::fs::remove_file(&video_path).await;
            }
            let _ = tokio::fs::remove_file(&audio_path).await;
            super::download_checkpoint::invalidate_ckpt(&video_path);
            super::download_checkpoint::invalidate_ckpt(&audio_path);

            let sz = tokio::fs::metadata(&merged_final).await?.len();
            state.set_phase("done");
            return Ok(DownloadResult {
                file_path: merged_final.to_string_lossy().into_owned(),
                file_size_bytes: sz,
            });
        }
    }

    let meta = tokio::fs::metadata(&output_path).await?;
    Ok(DownloadResult {
        file_path: output_path,
        file_size_bytes: meta.len(),
    })
}

// ملف يُستخدم كـ "cancel flag": إن وجد بجوار ملف الإخراج بامتداد .cancel → ألغِ
fn cancel_flag_path(output: &Path) -> PathBuf {
    let mut p = output.to_path_buf();
    let name = p
        .file_name()
        .and_then(|s| s.to_str())
        .map(|s| format!("{}.cancel", s))
        .unwrap_or_else(|| ".cancel".to_string());
    p.set_file_name(name);
    p
}

async fn spawn_cancel_watcher(output: PathBuf, state: JobState) {
    let flag = cancel_flag_path(&output);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            if tokio::fs::metadata(&flag).await.is_ok() {
                state.cancel.store(true, Ordering::SeqCst);
                let _ = tokio::fs::remove_file(&flag).await;
                break;
            }
            // إيقاف الـ watcher عند الانتهاء
            let phase = state.phase.lock().unwrap().clone();
            if phase == "done" {
                break;
            }
        }
    });
}

async fn download_inner(
    url: &str,
    output_path: &Path,
    audio_url: Option<&str>,
    mut connections: u32,
    state: JobState,
) -> Result<u64> {
    if url.contains("porngun.net") || url.contains("filev.php") {
        super::debug_log::log_download("Force connections=1 for porngun.net to avoid anti-leech 404 limits");
        connections = 1;
    }
    
    let connections = connections.clamp(1, 12);
    debug_log::log_download(&format!(
        "=== download start, host={}, audio={}",
        url.split('/').nth(2).unwrap_or("?"),
        audio_url.is_some()
    ));

    spawn_cancel_watcher(output_path.to_path_buf(), state.clone()).await;

    state.set_phase("preparing");
    let client = shared_download_client()?;

    if is_hls_url(url) {
        state.set_phase("downloading");
        let total = download_hls(&client, url, output_path, state.clone()).await?;
        if total == 0 {
            tokio::fs::remove_file(output_path).await.ok();
            return Err(anyhow::anyhow!("الملف المحمّل فارغ"));
        }
        state.set_phase("done");
        return Ok(total);
    }

    let (vt, v_ranges) = probe_url(&client, url).await.unwrap_or((0, false));
    let video_path = output_path.to_path_buf();

    let (audio_path, au_url, at, a_ranges) = if let Some(au) = audio_url {
        let mut p = output_path.to_path_buf();
        let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("audio").to_string();
        let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("mp4").to_string();
        p.set_file_name(format!("{}.audio.{}", stem, audio_ext_from_url(au, &ext)));
        let (t, r) = probe_url(&client, au).await.unwrap_or((0, false));
        (Some(p), Some(au.to_string()), t, r)
    } else {
        (None, None, 0, false)
    };

    state.total.store(vt + at, Ordering::SeqCst);

    let v_existing = tokio::fs::metadata(&video_path).await.map(|m| m.len()).unwrap_or(0);
    let v_prefilled = if v_ranges && vt > 1024 * 512 {
        let chunks_done = ChunkCkptHandle::try_load(&video_path, url, vt, connections)
            .map(|h| h.chunks_done_set())
            .unwrap_or_default();
        prefilled_bytes(connections, vt, &chunks_done)
    } else if v_ranges && vt > 0 && v_existing > 0 && v_existing < vt {
        v_existing
    } else if v_existing == vt && vt > 0 {
        vt
    } else {
        0
    };

    let a_existing = if let Some(ref p) = audio_path { tokio::fs::metadata(p).await.map(|m| m.len()).unwrap_or(0) } else { 0 };
    let a_prefilled = if a_ranges && at > 1024 * 256 {
        if let Some(ref p) = audio_path {
            let chunks_done = ChunkCkptHandle::try_load(p, au_url.as_ref().unwrap(), at, connections)
                .map(|h| h.chunks_done_set())
                .unwrap_or_default();
            prefilled_bytes(connections, at, &chunks_done)
        } else { 0 }
    } else if a_ranges && at > 0 && a_existing > 0 && a_existing < at {
        a_existing
    } else if a_existing == at && at > 0 {
        at
    } else {
        0
    };

    state.downloaded.store(v_prefilled + a_prefilled, Ordering::SeqCst);
    state.set_phase("downloading");

    let client_v = client.clone();
    let url_v = url.to_string();
    let video_path_v = video_path.clone();
    let state_v = state.clone();

    let video_fut = tokio::spawn(async move {
        let skip_video_complete = v_ranges && vt > 0 && v_existing == vt;
        if skip_video_complete {
            invalidate_ckpt(&video_path_v);
            Ok(vt)
        } else if v_ranges && vt > 1024 * 512 {
            download_chunked(&client_v, &url_v, &video_path_v, vt, connections, state_v).await
        } else if v_ranges && vt > 0 {
            if v_existing > 0 && v_existing < vt {
                let v = download_single_resume(&client_v, &url_v, &video_path_v, &state_v, v_existing, vt).await?;
                ensure_expected_total("video_single", v, vt)?;
                Ok(v)
            } else {
                let v = download_single(&client_v, &url_v, &video_path_v, state_v).await?;
                ensure_expected_total("video_single", v, vt)?;
                Ok(v)
            }
        } else {
            let v = download_single(&client_v, &url_v, &video_path_v, state_v).await?;
            if vt > 0 { ensure_expected_total("video_single", v, vt)?; }
            Ok(v)
        }
    });

    let client_a = client.clone();
    let state_a = state.clone();
    
    let audio_fut = tokio::spawn(async move {
        if let Some(au) = au_url {
            let p = audio_path.unwrap();
            let skip_audio_complete = at > 0 && a_existing == at;
            if skip_audio_complete {
                invalidate_ckpt(&p);
                Ok(at)
            } else if a_ranges && at > 1024 * 256 {
                download_chunked(&client_a, &au, &p, at, connections, state_a).await
            } else if a_ranges && at > 0 {
                if a_existing > 0 && a_existing < at {
                    let a = download_single_resume(&client_a, &au, &p, &state_a, a_existing, at).await?;
                    if a != at { debug_log::log_download("WARNING: audio_single_size_mismatch"); }
                    Ok(a)
                } else {
                    let a = download_single(&client_a, &au, &p, state_a).await?;
                    if a != at { debug_log::log_download("WARNING: audio_single_size_mismatch"); }
                    Ok(a)
                }
            } else {
                let a = download_single(&client_a, &au, &p, state_a).await?;
                if at > 0 && a != at { debug_log::log_download("WARNING: audio_single_size_mismatch"); }
                Ok(a)
            }
        } else {
            Ok(0u64)
        }
    });

    let (res_v, res_a) = tokio::try_join!(video_fut, audio_fut)?;
    let video_size = res_v?;
    let audio_size = res_a?;

    state.set_phase("done");
    state.downloaded.store(video_size + audio_size, Ordering::SeqCst);
    state.total.store(video_size + audio_size, Ordering::SeqCst);

    // The output file may not exist if it was renamed during chunked merge,
    // or if mux will rename it later in download_and_finalize.
    let final_size = tokio::fs::metadata(&output_path)
        .await
        .map(|m| m.len())
        .unwrap_or(0);

    if final_size == 0 && audio_url.is_none() {
        // Only fail for zero-size single-stream downloads (no mux scenario).
        // When audio_url is present, the file might look empty here because
        // download_and_finalize will merge video+audio into the final file.
        let _ = tokio::fs::remove_file(&output_path).await;
        return Err(anyhow::anyhow!("الملف المحمّل فارغ"));
    }

    Ok(if final_size > 0 { final_size } else { video_size + audio_size })
}

/// استنتاج امتداد الصوت من رابط YouTube (m4a/webm/opus)
fn audio_ext_from_url(url: &str, video_ext: &str) -> String {
    let u = url.to_lowercase();
    if u.contains("mime=audio%2fwebm") || u.contains("mime=audio/webm") {
        return "webm".into();
    }
    if u.contains("mime=audio%2fmp4") || u.contains("mime=audio/mp4") {
        return "m4a".into();
    }
    // افتراضي: نفس امتداد الفيديو (سيعمل غالباً مع FFmpeg)
    match video_ext {
        "webm" => "webm".into(),
        _ => "m4a".into(),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// الدمج يتم في Flutter عبر FFmpeg kit — Rust يُنزّل فقط
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// أدوات
// ─────────────────────────────────────────────────────────────────────────────

pub fn get_downloads_dir() -> Result<String, String> {
    let path: String = if cfg!(target_os = "android") {
        // NOTE: /storage/emulated/0/Download is NOT writable on Android 10+
        // without MANAGE_EXTERNAL_STORAGE. Callers on Android should resolve
        // the path from the Dart side (StorageService.getDownloadsDirectory)
        // which returns an app-scoped writable directory. This value is kept
        // only as a legacy fallback for callers that still expect a path.
        std::env::var("DARK_DOWNLOADER_ANDROID_DOWNLOADS_DIR")
            .unwrap_or_else(|_| "/storage/emulated/0/Download/DarkDownloader".to_string())
    } else if cfg!(target_os = "ios") {
        dirs::document_dir()
            .map(|p| p.join("DarkDownloader"))
            .unwrap_or_else(|| std::path::PathBuf::from("Documents/DarkDownloader"))
            .to_string_lossy()
            .to_string()
    } else {
        dirs::download_dir()
            .or_else(dirs::home_dir)
            .map(|p| p.join("DarkDownloader"))
            .unwrap_or_else(|| std::path::PathBuf::from("Downloads/DarkDownloader"))
            .to_string_lossy()
            .to_string()
    };
    Ok(path)
}

pub fn safe_filename(title: &str, format: &str) -> String {
    let safe: String = title
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => '_',
            other if other.is_control() => '_',
            other => other,
        })
        .take(100)
        .collect();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let trimmed = safe.trim();
    let base = if trimmed.is_empty() { "video" } else { trimmed };
    format!("{}_{}.{}", base, ts, format)
}
