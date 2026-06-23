pub mod api;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

use api::downloader;
use api::extractor;
use api::models::{DownloadResult, ExtractionResult};
use flutter_rust_bridge::frb;

// Re-export torrent + RSS public surface so flutter_rust_bridge_codegen picks
// them up when scanning lib.rs. The actual implementations live in
// api::torrent and api::torrent_rss.
pub use api::adblock_engine::{
    rust_get_default_ad_rules, rust_init_adblocker, rust_should_block_url,
};
pub use api::security::{rust_check_app_integrity, rust_get_device_fingerprint, rust_sign_message};

/// استخراج معلومات الفيديو أو قوائم التشغيل من أي رابط مدعوم
#[frb]
pub async fn rust_extract_video(url: String) -> Result<ExtractionResult, String> {
    extractor::extract(url).await
}

/// تحميل ملف وحفظه في المسار المحدد
///
/// لتمرير معلومات إضافية، استخدم URL مُعبّأ:
///   "<video_url>|||AUDIO:<audio_url>|||JOB:<job_id>|||CONN:<n>"
#[frb]
pub async fn rust_download_file(
    url: String,
    output_path: String,
) -> Result<DownloadResult, String> {
    downloader::download_file(url, output_path).await
}

/// مجلد التحميلات
#[frb(sync)]
pub fn rust_get_downloads_dir() -> String {
    downloader::get_downloads_dir().unwrap_or_else(|_| "Downloads/DarkDownloader".to_string())
}

/// اسم ملف آمن
#[frb(sync)]
pub fn rust_safe_filename(title: String, format: String) -> String {
    downloader::safe_filename(&title, &format)
}
