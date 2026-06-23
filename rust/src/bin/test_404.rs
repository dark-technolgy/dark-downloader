use reqwest::Client;

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .build().unwrap();
    
    // First let's get the download link page to see if we need a cookie
    let _ = client.get("https://porngun.net/2118/daisy-summers-seduced-in-the-bathroom/").send().await;

    // Then make the actual download request
    match client.get(url).send().await {
        Ok(resp) => {
            println!("Final URL: {}", resp.url());
            println!("Status: {}", resp.status());
            println!("Headers: {:#?}", resp.headers());
        },
        Err(e) => println!("Error: {}", e),
    }
}
