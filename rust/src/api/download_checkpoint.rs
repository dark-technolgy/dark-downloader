//! Sparse checkpoint for HTTP chunked downloads — enables resume after crash/kill.
//!
//! Sidecar file: `{filename}.dark_ckpt.json` next to the partial download.
//! Stores completed chunk slot indices (same indices as `download_chunked` loop).

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ChunkCkpt {
    pub v: u32,
    pub url: String,
    pub total_bytes: u64,
    pub connections: u32,
    pub chunks_done: Vec<u32>,
}

pub fn ckpt_file_for(output: &Path) -> PathBuf {
    let name = output
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("download");
    let mut p = output.to_path_buf();
    p.set_file_name(format!("{name}.dark_ckpt.json"));
    p
}

fn atomic_write(path: &Path, data: &[u8]) -> Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let tmp = parent.join(format!("dark_ckpt_write_{stamp}.tmp"));
    std::fs::write(&tmp, data)?;
    #[cfg(unix)]
    {
        std::fs::rename(&tmp, path)?;
    }
    #[cfg(windows)]
    {
        let _ = std::fs::remove_file(path);
        std::fs::rename(&tmp, path)?;
    }
    Ok(())
}

/// Tracks chunk completion and persists to disk after each finished chunk slot.
pub struct ChunkCkptHandle {
    path: PathBuf,
    ckpt: Mutex<ChunkCkpt>,
}

impl ChunkCkptHandle {
    pub fn create_fresh(
        output: &Path,
        url: &str,
        total_bytes: u64,
        connections: u32,
    ) -> Result<Self> {
        let path = ckpt_file_for(output);
        let ckpt = ChunkCkpt {
            v: 1,
            url: url.to_string(),
            total_bytes,
            connections,
            chunks_done: Vec::new(),
        };
        atomic_write(&path, &serde_json::to_vec(&ckpt)?)?;
        Ok(Self {
            path,
            ckpt: Mutex::new(ckpt),
        })
    }

    pub fn try_load(output: &Path, url: &str, total_bytes: u64, connections: u32) -> Option<Self> {
        let path = ckpt_file_for(output);
        let bytes = std::fs::read(&path).ok()?;
        let ckpt: ChunkCkpt = serde_json::from_slice(&bytes).ok()?;
        if ckpt.v != 1
            || ckpt.url != url
            || ckpt.total_bytes != total_bytes
            || ckpt.connections != connections
        {
            return None;
        }
        Some(Self {
            path,
            ckpt: Mutex::new(ckpt),
        })
    }

    pub fn chunks_done_set(&self) -> HashSet<u32> {
        self.ckpt
            .lock()
            .expect("ckpt mutex poisoned")
            .chunks_done
            .iter()
            .copied()
            .collect()
    }

    pub fn mark_chunk_done(&self, slot: u32) -> Result<()> {
        let serialized = {
            let mut g = self.ckpt.lock().expect("ckpt mutex poisoned");
            if g.chunks_done.contains(&slot) {
                return Ok(());
            }
            g.chunks_done.push(slot);
            g.chunks_done.sort_unstable();
            serde_json::to_vec(&*g)?
        };
        atomic_write(&self.path, &serialized)
    }

    pub fn remove_file(&self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub fn invalidate_ckpt(output: &Path) {
    let _ = std::fs::remove_file(ckpt_file_for(output));
}

/// Sum byte lengths covered by finished chunk slots (same geometry as `download_chunked`).
pub fn prefilled_bytes(connections: u32, total_bytes: u64, done: &HashSet<u32>) -> u64 {
    let conn = connections.clamp(1, 16) as u64;
    if total_bytes == 0 {
        return 0;
    }
    let chunk_size = total_bytes.div_ceil(conn);
    let mut sum = 0u64;
    for i in 0..connections.clamp(1, 16) as u64 {
        let start = i * chunk_size;
        let end = ((i + 1) * chunk_size - 1).min(total_bytes - 1);
        if start > end {
            continue;
        }
        if done.contains(&(i as u32)) {
            sum += end - start + 1;
        }
    }
    sum
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn prefilled_empty_is_zero() {
        let done = HashSet::new();
        assert_eq!(prefilled_bytes(4, 100, &done), 0);
    }

    #[test]
    fn prefilled_all_matches_total() {
        let done: HashSet<u32> = [0, 1, 2, 3].into_iter().collect();
        assert_eq!(prefilled_bytes(4, 100, &done), 100);
    }

    #[test]
    fn prefilled_partial_three_connections() {
        let done: HashSet<u32> = [0, 2].into_iter().collect();
        assert_eq!(prefilled_bytes(3, 100, &done), 34 + 32);
    }
}
