use reqwest::{Client, header};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/filev.php?id=2118&file_id=4674&server=1&hash=5d703333521acc4a2f27&expire=1782108488&file=/mp4/2118.mp4";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build().unwrap();
    
    let resp = client.get(url).header(header::RANGE, "bytes=0-1000").send().await.unwrap();
    println!("Status with Range: {}", resp.status());
}
