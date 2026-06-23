use reqwest::Client;

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client1 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .build().unwrap();
    
    let final_url = match client1.get(url).send().await {
        Ok(resp) => {
            println!("Got URL: {}", resp.url());
            resp.url().to_string()
        },
        Err(e) => return println!("Error: {}", e),
    };

    // Now try to download with a DIFFERENT user agent
    let client2 = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36")
        .build().unwrap();
    
    match client2.get(&final_url).send().await {
        Ok(resp) => {
            println!("Status with different UA: {}", resp.status());
        },
        Err(e) => println!("Error 2: {}", e),
    }
}
