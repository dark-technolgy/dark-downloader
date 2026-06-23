import re
import sys

def process():
    path = r"c:\Users\Dark\Desktop\dark_downloader-main\rust\src\api\downloader.rs"
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Replace download_single
    single_regex = re.compile(r'async fn download_single\(.*?Ok\(total\)\n\}', re.DOTALL)
    single_new = """async fn download_single(
    client: &Client,
    url: &str,
    output_path: &Path,
    state: JobState,
) -> Result<u64> {
    const MAX_ATTEMPTS: u32 = 4;
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
                tokio::time::sleep(std::time::Duration::from_millis(500 * attempt as u64)).await;
                continue;
            }
        };

        if !resp.status().is_success() {
            attempt += 1;
            if attempt >= MAX_ATTEMPTS { return Err(anyhow::anyhow!("HTTP {}", resp.status())); }
            tokio::time::sleep(std::time::Duration::from_millis(500 * attempt as u64)).await;
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
            tokio::time::sleep(std::time::Duration::from_millis(500 * attempt as u64)).await;
            continue; // restart the download from 0
        }
        
        return Ok(total);
    }
}"""
    content = single_regex.sub(single_new, content, count=1)
    
    # Remove download_single_additive completely
    additive_single_regex = re.compile(r'// تحميل single إضافي.*async fn download_single_additive\(.*?Ok\(total\)\n\}', re.DOTALL)
    content = additive_single_regex.sub('', content)
    
    # 2. Update download_single_resume
    resume_regex = re.compile(r'async fn download_single_resume\(\n.*?Ok\(got\)\n\}', re.DOTALL)
    resume_new = """async fn download_single_resume(
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
}"""
    content = resume_regex.sub(resume_new, content, count=1)

    # 3. Update download_chunked
    chunked_regex = re.compile(r'async fn download_chunked\(.*?Ok\(final_size\)\n\}', re.DOTALL)
    chunked_new = """async fn download_chunked(
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
            Some(h) if disk_len == total_bytes => Arc::new(h),
            Some(h) => {
                h.remove_file();
                let _ = tokio::fs::remove_file(output_path).await;
                Arc::new(ChunkCkptHandle::create_fresh(
                    output_path,
                    url,
                    total_bytes,
                    connections,
                )?)
            }
            None => {
                if disk_len > 0 && disk_len != total_bytes {
                    let _ = tokio::fs::remove_file(output_path).await;
                }
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

    let file = tokio::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(output_path)
        .await?;
    file.set_len(total_bytes).await?;
    drop(file);

    let chunks_done = ckpt_arc.chunks_done_set();
    let prefilled = prefilled_bytes(connections, total_bytes, &chunks_done);
    let mode = if chunks_done.is_empty() {
        "fresh"
    } else {
        "resume"
    };
    super::debug_log::log_download(&format!(
        "chunked mode={mode} chunks_done={} prefilled={}B total={}B disk_len={disk_len}",
        chunks_done.len(),
        prefilled,
        total_bytes,
    ));

    let file = Arc::new(tokio::sync::Mutex::new(
        tokio::fs::OpenOptions::new()
            .write(true)
            .open(output_path)
            .await?,
    ));

    let mut tasks = Vec::new();

    for slot in 0..connections {
        let start = (slot as u64) * chunk_size;
        let end = (((slot as u64) + 1) * chunk_size - 1).min(total_bytes.saturating_sub(1));
        if start > end {
            continue;
        }
        if chunks_done.contains(&slot) {
            continue;
        }

        let url_owned = url.to_string();
        let client = client.clone();
        let file = Arc::clone(&file);
        let st = state.clone();
        let ckpt = Arc::clone(&ckpt_arc);

        tasks.push(tokio::spawn(async move {
            download_chunk(
                &client,
                &url_owned,
                start,
                end,
                file,
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
            Ok(Err(e)) => return Err(e),
            Err(e) => return Err(anyhow::anyhow!("join: {}", e)),
        }
    }

    ckpt_arc.remove_file();

    let final_size = tokio::fs::metadata(output_path).await?.len();
    ensure_expected_total("chunked", final_size, total_bytes)?;
    Ok(final_size)
}"""
    content = chunked_regex.sub(chunked_new, content, count=1)
    
    # Remove download_chunked_additive
    additive_chunked_regex = re.compile(r'// نسخة خاصة لـ audio تُضيف للـ state.*?async fn download_chunked_additive\(.*?Ok\(final_size\)\n\}', re.DOTALL)
    content = additive_chunked_regex.sub('', content)

    # 4. Update download_chunk
    chunk_regex = re.compile(r'async fn download_chunk\(.*?Ok\(\(\)\)\n\s*\}\n\s*\}\n\}', re.DOTALL)
    chunk_new = """async fn download_chunk(
    client: &Client,
    url: &str,
    start: u64,
    end: u64,
    file: Arc<tokio::sync::Mutex<tokio::fs::File>>,
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
    # Replace download_chunk
    content = chunk_regex.sub(chunk_new, content, count=1)
    
    # Remove download_chunk_additive
    additive_chunk_regex = re.compile(r'async fn download_chunk_additive\(.*?Ok\(\(\)\)\n\s*\}\n\s*\}\n\}', re.DOTALL)
    content = additive_chunk_regex.sub('', content)

    # 5. Replace download_inner with tokio::try_join!
    inner_regex = re.compile(r'async fn download_inner\(.*?Ok\(final_size\)\n\}', re.DOTALL)
    inner_new = """async fn download_inner(
    url: &str,
    output_path: &Path,
    audio_url: Option<&str>,
    connections: u32,
    state: JobState,
) -> Result<u64> {
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

    let final_size = tokio::fs::metadata(&output_path).await?.len();
    if final_size == 0 {
        tokio::fs::remove_file(&output_path).await.ok();
        return Err(anyhow::anyhow!("الملف المحمّل فارغ"));
    }

    Ok(final_size)
}"""
    content = inner_regex.sub(inner_new, content, count=1)

    # Note: ensure replace `AsyncMutex` with `tokio::sync::Mutex` if I missed it, but they might alias it.
    content = content.replace("use tokio::sync::Mutex as AsyncMutex;", "use tokio::sync::Mutex;")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
        
process()
