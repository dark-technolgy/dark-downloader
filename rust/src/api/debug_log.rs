//! Append-only trace file under the OS temp dir (`dark_downloader.log`).
//! Disabled in release builds (`debug_assertions` off) to avoid disk I/O and leaks.

use std::io::Write;

fn write_line(body: &str) {
    let path = std::env::temp_dir().join("dark_downloader.log");
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "[{}] {}", ts, body);
    }
}

pub(crate) fn log_debug(msg: &str) {
    if !cfg!(debug_assertions) {
        return;
    }
    write_line(msg);
}

pub(crate) fn log_download(msg: &str) {
    if !cfg!(debug_assertions) {
        return;
    }
    write_line(&format!("DL: {msg}"));
}
