use flutter_rust_bridge::frb;

#[frb]
pub struct VideoInfoResult {
    pub title: String,
    pub thumbnail_url: Option<String>,
    pub platform: String,
    pub duration_seconds: Option<u32>,
    pub author: Option<String>,
    pub streams: Vec<StreamResult>,
}

#[frb]
pub struct StreamResult {
    pub url: String,
    pub quality: String,
    pub format: String,
    pub container: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub fps: Option<f32>,
    pub video_codec: Option<String>,
    pub audio_codec: Option<String>,
    pub bitrate_kbps: Option<u32>,
    pub file_size_bytes: Option<u64>,
    pub has_video: bool,
    pub has_audio: bool,
    pub is_audio_only: bool,
    pub is_hdr: bool,
}

#[frb]
pub struct PlaylistResult {
    pub title: String,
    pub author: Option<String>,
    pub items: Vec<PlaylistItem>,
}

#[frb]
pub struct PlaylistItem {
    pub url: String,
    pub title: String,
    pub thumbnail_url: Option<String>,
    pub duration_seconds: Option<u32>,
}

#[frb]
pub struct DownloadResult {
    pub file_path: String,
    pub file_size_bytes: u64,
}

#[frb]
pub enum ExtractionResult {
    Video(VideoInfoResult),
    Playlist(PlaylistResult),
}

// ─────────────────────────────────────────────────────────────────────────────
// BitTorrent — public types crossing the FRB boundary
// ─────────────────────────────────────────────────────────────────────────────

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentSummary {
    pub id: i64,
    pub name: String,
    pub info_hash: String,
    pub total_size: u64,
    pub downloaded: u64,
    pub uploaded: u64,
    pub dl_speed: u64,
    pub ul_speed: u64,
    pub peers: u32,
    pub seeds: u32,
    pub eta_secs: u64,
    pub state: String,
    pub progress: f64,
    pub save_path: String,
    pub num_files: u32,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentFile {
    pub index: u32,
    pub path: String,
    pub size: u64,
    pub priority: i32,
    pub progress: f64,
    pub included: bool,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentEvent {
    pub id: i64,
    pub kind: String,
    pub message: Option<String>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentAddOptions {
    pub paused: bool,
    pub sequential: bool,
    pub only_files: Option<Vec<u32>>,
    pub save_path_override: Option<String>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentSessionConfig {
    pub session_dir: String,
    pub default_save_path: String,
    pub enable_dht: bool,
    pub enable_pex: bool,
    pub enable_lsd: bool,
    pub max_global_dl_bytes_per_sec: u64,
    pub max_global_ul_bytes_per_sec: u64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentPeerInfo {
    pub address: String,
    pub client: Option<String>,
    pub flags: String,
    pub progress: f64,
    pub dl_speed: u64,
    pub ul_speed: u64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct TorrentTrackerInfo {
    pub url: String,
    pub status: String,
    pub seeds: u32,
    pub leechers: u32,
}
