use reqwest::{Client, header};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client1 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .build().unwrap();
    
    let mut full_url = url.to_string();
    if let Ok(resp) = client1.get(&full_url).send().await {
        if resp.status().is_success() {
            full_url = resp.url().to_string();
        }
    }
    
    // Now simulate downloader.rs
    let mut h = header::HeaderMap::new();
    h.insert(header::USER_AGENT, header::HeaderValue::from_static("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"));
    h.insert(header::REFERER, header::HeaderValue::from_static("https://porngun.net/"));
    h.insert(header::HeaderName::from_static("origin"), header::HeaderValue::from_static("https://porngun.net"));
    h.insert(header::HeaderName::from_static("accept"), header::HeaderValue::from_static("*/*"));
    h.insert(header::HeaderName::from_static("accept-language"), header::HeaderValue::from_static("en-US,en;q=0.9"));
    h.insert(header::HeaderName::from_static("accept-encoding"), header::HeaderValue::from_static("identity"));
    h.insert(header::RANGE, header::HeaderValue::from_static("bytes=0-0"));

    let r = client1.get(&full_url).headers(h).send().await.unwrap();
    println!("Probe Status: {}", r.status());
}
