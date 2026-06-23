import re

path = r"c:\Users\Dark\Desktop\dark_downloader-main\rust\src\api\downloader.rs"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Restore AsyncMutex import
content = content.replace("use tokio::sync::Mutex;", "use tokio::sync::Mutex as AsyncMutex;")
# And change AsyncMutex back where needed
content = content.replace("file: Arc<tokio::sync::Mutex<tokio::fs::File>>", "file: Arc<AsyncMutex<tokio::fs::File>>")

# 2. Fix `download_chunk` definition and calls
# The error E0061 says download_chunk takes 9 arguments.
# Let's see the signature in the file right now
import sys
# Wait, let's just find `async fn download_chunk` and replace it entirely!
chunk_pattern = re.compile(r'async fn download_chunk\(.*?Ok\(\(\)\)\n\}', re.DOTALL)
chunk_new = """async fn download_chunk(
    client: &Client,
    url: &str,
    start: u64,
    end: u64,
    file: Arc<AsyncMutex<tokio::fs::File>>,
    state: JobState,
    chunk_slot: u32,
    ckpt: Option<Arc<ChunkCkptHandle>>,
) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 4;
    let mut attempt = 0u32;
    let mut offset = start;

    loop {
        if state.cancel.load(Ordering::SeqCst) {
            return Err(anyhow::anyhow!("cancelled"));
        }

        let mut headers = default_headers(url);
        headers.insert(
            RANGE,
            HeaderValue::from_str(&format!("bytes={}-{}", offset, end))?,
        );

        let resp = match client.get(url).headers(headers).send().await {
            Ok(r) => r,
            Err(e) => {
                attempt += 1;
                if attempt >= MAX_ATTEMPTS {
                    return Err(anyhow::anyhow!("{}", e));
                }
                tokio::time::sleep(std::time::Duration::from_millis(500 * attempt as u64)).await;
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
            tokio::time::sleep(std::time::Duration::from_millis(500 * attempt as u64)).await;
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

        let mut stream = resp.bytes_stream();
        let mut write_offset = offset;

        loop {
            if state.cancel.load(Ordering::SeqCst) {
                return Err(anyhow::anyhow!("cancelled"));
            }
            match stream.next().await {
                None => break,
                Some(Err(e)) => {
                    super::debug_log::log_download(&format!("stream error at {}: {}", write_offset, e));
                    attempt += 1;
                    if attempt >= MAX_ATTEMPTS {
                        return Err(anyhow::anyhow!("stream: {}", e));
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(300 * attempt as u64))
                        .await;
                    break;
                }
                Some(Ok(bytes)) => {
                    if bytes.is_empty() {
                        continue;
                    }
                    {
                        let mut f = file.lock().await;
                        f.seek(std::io::SeekFrom::Start(write_offset)).await?;
                        f.write_all(&bytes).await?;
                    }
                    let len = bytes.len() as u64;
                    write_offset += len;
                    let current_total = state.downloaded.fetch_add(len, Ordering::SeqCst) + len;
                    update_speed(&state, current_total);
                }
            }
        }

        if write_offset > actual_end {
            if let Some(ref c) = ckpt {
                let _ = c.mark_chunk_done(chunk_slot);
            }
            return Ok(());
        }

        offset = write_offset;
        attempt += 1;
        if attempt >= MAX_ATTEMPTS {
            return Err(anyhow::anyhow!("incomplete chunk at {}/{} (actual_end: {})", write_offset, end, actual_end));
        }
    }
}"""
content = chunk_pattern.sub(chunk_new, content, count=1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
