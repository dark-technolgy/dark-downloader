use reqwest::{header, Client};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client1 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build()
        .unwrap();

    // Simulating exactly what universal_extractor does
    let mut full_url = url.to_string();
    if let Ok(resp) = client1.get(&full_url).send().await {
        if resp.status().is_success() {
            full_url = resp.url().to_string();
            println!("Extracted URL: {}", full_url);
        }
    }

    // Now simulate downloader.rs
    let r = client1
        .get(&full_url)
        .header(header::RANGE, "bytes=0-0")
        .send()
        .await
        .unwrap();
    println!("Probe Status: {}", r.status());

    let chunk_req = client1
        .get(&full_url)
        .header(header::RANGE, "bytes=0-1000")
        .send()
        .await
        .unwrap();
    println!("Chunk Status: {}", chunk_req.status());
    if !chunk_req.status().is_success()
        && chunk_req.status() != reqwest::StatusCode::PARTIAL_CONTENT
    {
        println!("Chunk Failed!");
    }
}
