use reqwest::{header, Client};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build()
        .unwrap();

    // Simulate probe_url
    let mut h = header::HeaderMap::new();
    h.insert(header::RANGE, header::HeaderValue::from_static("bytes=0-0"));
    let r1 = client.get(url).headers(h).send().await.unwrap();
    println!("Probe via /download/: {}", r1.status());

    // Simulate chunk 1
    let mut h1 = header::HeaderMap::new();
    h1.insert(
        header::RANGE,
        header::HeaderValue::from_static("bytes=0-1000"),
    );
    let r2 = client.get(url).headers(h1).send().await.unwrap();
    println!("Chunk 1 via /download/: {}", r2.status());

    // Simulate chunk 2
    let mut h2 = header::HeaderMap::new();
    h2.insert(
        header::RANGE,
        header::HeaderValue::from_static("bytes=1001-2000"),
    );
    let r3 = client.get(url).headers(h2).send().await.unwrap();
    println!("Chunk 2 via /download/: {}", r3.status());
}
