use std::process::Command;
use flutter_rust_bridge::frb;
use anyhow::{Result, Context};

#[frb(sync)]
pub fn mux_video_audio(video_path: String, audio_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    // Choose the muxing strategy from the *output container*.
    //   - MP4  : video must be H.264, audio must be AAC.
    //   - WEBM : video must be VP8/VP9, audio must be Opus/Vorbis.
    // Attempt 1 stream-copies the video (fast, lossless) and only re-encodes
    // the audio to the container-appropriate codec. If the source video codec
    // is incompatible with the container (e.g. VP9 into MP4), FFmpeg fails and
    // we fall back to a full transcode so the result is always playable.
    let ext = std::path::Path::new(&output_path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_else(|| "mp4".to_string());

    let is_webm = matches!(ext.as_str(), "webm" | "mkv");
    let audio_codec = if is_webm { "libopus" } else { "aac" };

    // Attempt 1: copy video, encode audio to match the container.
    let copy_status = Command::new(&ffmpeg_path)
        .arg("-i").arg(&video_path)
        .arg("-i").arg(&audio_path)
        .arg("-c:v").arg("copy")
        .arg("-c:a").arg(audio_codec)
        .arg("-map").arg("0:v:0")
        .arg("-map").arg("1:a:0")
        .arg("-shortest")
        .arg("-y")
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg mux (copy) process")?;

    if copy_status.success() {
        return Ok(());
    }

    // Attempt 2: full transcode into a codec the container accepts.
    let video_codec = if is_webm { "libvpx-vp9" } else { "libx264" };
    let mut cmd = Command::new(&ffmpeg_path);
    cmd.arg("-i").arg(&video_path)
        .arg("-i").arg(&audio_path)
        .arg("-c:v").arg(video_codec)
        .arg("-c:a").arg(audio_codec)
        .arg("-map").arg("0:v:0")
        .arg("-map").arg("1:a:0")
        .arg("-shortest");
    if !is_webm {
        // Broadest MP4 playback compatibility (phones, browsers, TVs).
        cmd.arg("-preset").arg("veryfast")
            .arg("-crf").arg("20")
            .arg("-pix_fmt").arg("yuv420p")
            .arg("-movflags").arg("+faststart");
    } else {
        cmd.arg("-b:v").arg("0").arg("-crf").arg("32");
    }
    cmd.arg("-y").arg(&output_path);

    let transcode_status = cmd
        .status()
        .context("Failed to execute FFmpeg mux (transcode) process")?;

    if !transcode_status.success() {
        return Err(anyhow::anyhow!(
            "FFmpeg mux failed (copy and transcode both failed)"
        ));
    }

    Ok(())
}

#[frb(sync)]
pub fn extract_audio(video_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    // Attempt 1: stream-copy — fastest, lossless, keeps original codec.
    // Works when target container supports the source codec
    // (e.g. AAC → .m4a, Opus → .opus / .webm / .mka).
    let copy_status = Command::new(&ffmpeg_path)
        .arg("-i")
        .arg(&video_path)
        .arg("-vn")
        .arg("-c:a")
        .arg("copy")
        .arg("-y")
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg process")?;

    if copy_status.success() {
        return Ok(());
    }

    // Attempt 2: transcode to a codec that matches the target container.
    // Handles the classic "Opus in WebM → .m4a (ipod)" mismatch that made
    // extraction appear to fail even though the source download succeeded.
    let ext = std::path::Path::new(&output_path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_default();

    let (codec, extra_args): (&str, &[&str]) = match ext.as_str() {
        "m4a" | "mp4" | "aac" => ("aac", &["-b:a", "192k"]),
        "opus" | "webm" => ("libopus", &["-b:a", "160k"]),
        "ogg" => ("libvorbis", &["-q:a", "5"]),
        "mp3" => ("libmp3lame", &["-q:a", "2"]),
        "wav" => ("pcm_s16le", &[]),
        "flac" => ("flac", &[]),
        _ => ("aac", &["-b:a", "192k"]),
    };

    let mut cmd = Command::new(&ffmpeg_path);
    cmd.arg("-i")
        .arg(&video_path)
        .arg("-vn")
        .arg("-c:a")
        .arg(codec);
    for a in extra_args {
        cmd.arg(a);
    }
    cmd.arg("-y").arg(&output_path);

    let transcode_status = cmd
        .status()
        .context("Failed to execute FFmpeg transcode fallback")?;

    if !transcode_status.success() {
        return Err(anyhow::anyhow!(
            "FFmpeg audio extraction failed (copy and transcode both failed)"
        ));
    }

    Ok(())
}

/// Hardened MP3 conversion.
///
/// Same signature as the previous implementation so callers keep working.
/// - VBR quality 0 (highest, ~245 kbps average)
/// - Proper Xing/LAME header for accurate seeking in all players
/// - id3v2 v3 tags (widest compatibility, incl. Windows Explorer)
/// - Preserves source metadata when present
#[frb(sync)]
pub fn convert_to_mp3(input_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    let status = Command::new(&ffmpeg_path)
        .arg("-i")
        .arg(&input_path)
        .arg("-vn")
        .arg("-c:a")
        .arg("libmp3lame")
        .arg("-q:a")
        .arg("0")
        .arg("-write_xing")
        .arg("1")
        .arg("-id3v2_version")
        .arg("3")
        .arg("-map_metadata")
        .arg("0")
        .arg("-y")
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg process for MP3 conversion")?;

    if !status.success() {
        return Err(anyhow::anyhow!("FFmpeg MP3 conversion failed"));
    }

    Ok(())
}

/// Rich MP3 conversion with optional metadata and embedded album art.
///
/// Any `None` field is skipped. `cover_path`, when provided and readable,
/// is embedded as the front-cover artwork.
#[frb(sync)]
pub fn convert_to_mp3_rich(
    input_path: String,
    output_path: String,
    ffmpeg_path: String,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    date: Option<String>,
    comment: Option<String>,
    cover_path: Option<String>,
) -> Result<()> {
    let mut cmd = Command::new(&ffmpeg_path);
    cmd.arg("-i").arg(&input_path);

    let has_cover = cover_path
        .as_deref()
        .map(|p| !p.is_empty() && std::path::Path::new(p).exists())
        .unwrap_or(false);

    if has_cover {
        if let Some(cover) = cover_path.as_deref() {
            cmd.arg("-i").arg(cover);
        }
        cmd.arg("-map").arg("0:a");
        cmd.arg("-map").arg("1:v");
        cmd.arg("-c:v").arg("mjpeg");
        cmd.arg("-disposition:v:0").arg("attached_pic");
        cmd.arg("-metadata:s:v:0").arg("title=Album cover");
        cmd.arg("-metadata:s:v:0").arg("comment=Cover (front)");
    } else {
        // Same shape as the plain convert_to_mp3 — safe on any container,
        // handles inputs that FFmpeg struggles to auto-select streams from.
        cmd.arg("-vn");
    }

    cmd.arg("-c:a").arg("libmp3lame");
    cmd.arg("-q:a").arg("0");
    cmd.arg("-write_xing").arg("1");
    cmd.arg("-id3v2_version").arg("3");
    cmd.arg("-map_metadata").arg("0");

    let add_meta = |cmd: &mut Command, key: &str, value: &Option<String>| {
        if let Some(v) = value {
            let trimmed = v.trim();
            if !trimmed.is_empty() {
                cmd.arg("-metadata").arg(format!("{}={}", key, trimmed));
            }
        }
    };
    add_meta(&mut cmd, "title", &title);
    add_meta(&mut cmd, "artist", &artist);
    add_meta(&mut cmd, "album", &album);
    add_meta(&mut cmd, "date", &date);
    add_meta(&mut cmd, "comment", &comment);

    cmd.arg("-y").arg(&output_path);

    let status = cmd
        .status()
        .context("Failed to execute FFmpeg process for rich MP3 conversion")?;

    if !status.success() {
        return Err(anyhow::anyhow!("FFmpeg rich MP3 conversion failed"));
    }

    Ok(())
}

/// Embed (or replace) the front-cover artwork on an existing MP3 file.
/// Rewrites the file in-place via a temporary intermediate.
#[frb(sync)]
pub fn embed_album_art(mp3_path: String, cover_path: String, ffmpeg_path: String) -> Result<()> {
    if !std::path::Path::new(&cover_path).exists() {
        return Err(anyhow::anyhow!("Cover file not found: {}", cover_path));
    }

    let tmp_path = format!("{}.cover.tmp.mp3", mp3_path);

    let status = Command::new(&ffmpeg_path)
        .arg("-i").arg(&mp3_path)
        .arg("-i").arg(&cover_path)
        .arg("-map").arg("0:a")
        .arg("-map").arg("1:v")
        .arg("-c:a").arg("copy")
        .arg("-c:v").arg("mjpeg")
        .arg("-disposition:v:0").arg("attached_pic")
        .arg("-id3v2_version").arg("3")
        .arg("-metadata:s:v:0").arg("title=Album cover")
        .arg("-metadata:s:v:0").arg("comment=Cover (front)")
        .arg("-y")
        .arg(&tmp_path)
        .status()
        .context("Failed to execute FFmpeg for album-art embed")?;

    if !status.success() {
        let _ = std::fs::remove_file(&tmp_path);
        return Err(anyhow::anyhow!("FFmpeg album-art embed failed"));
    }

    std::fs::rename(&tmp_path, &mp3_path).context("Failed to swap tmp mp3 into place")?;
    Ok(())
}

#[frb(sync)]
pub fn compress_video(input_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    let status = Command::new(&ffmpeg_path)
        .arg("-i")
        .arg(&input_path)
        .arg("-vcodec")
        .arg("libx264")
        .arg("-crf")
        .arg("26")
        .arg("-y")
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg process")?;

    if !status.success() {
        return Err(anyhow::anyhow!("FFmpeg exited with non-zero status"));
    }

    Ok(())
}
