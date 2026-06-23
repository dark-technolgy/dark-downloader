use reqwest::{Client, header};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client1 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build().unwrap();
    
    let final_url = match client1.get(url).send().await {
        Ok(resp) => resp.url().to_string(),
        Err(e) => return println!("Error: {}", e),
    };

    // Try with the generic referer that downloader.rs uses
    let client2 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build().unwrap();
    
    let mut headers = header::HeaderMap::new();
    headers.insert(header::REFERER, header::HeaderValue::from_static("https://porngun.net/"));
    
    match client2.get(&final_url).headers(headers).send().await {
        Ok(resp) => println!("Status with generic referer: {}", resp.status()),
        Err(e) => println!("Error 2: {}", e),
    }
}
