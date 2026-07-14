use rust_lib_dark_downloader::api::downloader::{download_file_v2, get_job_progress};
use rust_lib_dark_downloader::api::extractor::extract;
use rust_lib_dark_downloader::api::models::ExtractionResult;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::main]
async fn main() {
    println!("\n--- TEST 2K: YouTube Extraction & Dynamic Download ---");
    // "Costa Rica in 4K 60fps" - reliable for 1440p/2160p testing
    let yt_url = "https://www.youtube.com/watch?v=LXb3EKWsInQ".to_string();
    println!("Extracting YouTube URL: {}", yt_url);

    match extract(yt_url).await {
        Ok(ExtractionResult::Video(video)) => {
            println!("Extraction Success: {}", video.title);

            // Print all streams for debugging
            println!("--- Available Video Streams ---");
            for s in video.streams.iter().filter(|s| s.has_video) {
                println!(
                    "- {} ({} fps) [Audio: {}]",
                    s.quality,
                    s.fps.unwrap_or(0.0),
                    s.has_audio
                );
            }

            // Find 1440p or 2160p video (or best available)
            let mut v_stream = video
                .streams
                .iter()
                .filter(|s| s.has_video)
                .collect::<Vec<_>>();
            v_stream.sort_by(|a, b| b.quality.cmp(&a.quality)); // descending
            let best_video = v_stream.first().map(|s| s.url.clone());

            // Find best audio
            let mut a_stream = video
                .streams
                .iter()
                .filter(|s| s.has_audio && !s.has_video)
                .collect::<Vec<_>>();
            a_stream.sort_by(|a, b| b.quality.cmp(&a.quality));
            let best_audio = a_stream.first().map(|s| s.url.clone());

            if let Some(v_url) = best_video {
                let output_path_yt = "test_2k_video.mp4".to_string();
                let job_id_yt = "test_job_2k".to_string();
                let job_id_clone_yt = job_id_yt.clone();

                // Cleanup previous
                let _ = tokio::fs::remove_file(&output_path_yt).await;
                let _ = tokio::fs::remove_file("test_2k_video.audio.m4a").await;

                let monitor_yt = tokio::spawn(async move {
                    loop {
                        if let Some(progress) = get_job_progress(job_id_clone_yt.clone()) {
                            println!(
                                "Progress: {:.2}% ({} / {}) - Speed: {} B/s",
                                progress.percent,
                                progress.downloaded_bytes,
                                progress.total_bytes,
                                progress.speed_bytes_sec
                            );
                            if progress.phase == "done" {
                                break;
                            }
                        } else {
                            break;
                        }
                        sleep(Duration::from_millis(2000)).await;
                    }
                });

                println!(
                    "Starting YouTube Download with audio: {}",
                    best_audio.is_some()
                );

                // Using None for muxFfmpeg because we just want to test download architecture and sidecar creation
                match download_file_v2(v_url, output_path_yt, best_audio, job_id_yt, 8, Some("c:\\Users\\Dark\\Desktop\\dark_downloader-main\\build\\windows\\x64\\runner\\Debug\\data\\flutter_assets\\assets\\bundled_ffmpeg\\windows\\ffmpeg.exe".to_string())).await {
                    Ok(res) => println!("TEST SUCCESS! Saved to {}, Size: {}", res.file_path, res.file_size_bytes),
                    Err(e) => println!("TEST FAILED: {:?}", e),
                }
                let _ = monitor_yt.await;
            } else {
                println!("TEST FAILED: No videos found in extraction");
            }
        }
        _ => println!("TEST FAILED: Extraction error"),
    }
}
