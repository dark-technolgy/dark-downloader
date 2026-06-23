use std::process::Command;
use flutter_rust_bridge::frb;
use anyhow::{Result, Context};

#[frb(sync)]
pub fn mux_video_audio(video_path: String, audio_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    let status = Command::new(&ffmpeg_path)
        .arg("-i")
        .arg(&video_path)
        .arg("-i")
        .arg(&audio_path)
        .arg("-c:v")
        .arg("copy")
        .arg("-c:a")
        .arg("aac")
        .arg("-y") // Overwrite output file if it exists
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg process")?;

    if !status.success() {
        return Err(anyhow::anyhow!("FFmpeg exited with non-zero status"));
    }

    Ok(())
}

#[frb(sync)]
pub fn extract_audio(video_path: String, output_path: String, ffmpeg_path: String) -> Result<()> {
    let status = Command::new(&ffmpeg_path)
        .arg("-i")
        .arg(&video_path)
        .arg("-vn")
        .arg("-c:a")
        .arg("copy")
        .arg("-y")
        .arg(&output_path)
        .status()
        .context("Failed to execute FFmpeg process")?;

    if !status.success() {
        return Err(anyhow::anyhow!("FFmpeg exited with non-zero status"));
    }

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
