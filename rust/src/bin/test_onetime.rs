use reqwest::Client;

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build()
        .unwrap();

    // 1. Get the final URL
    let final_url = match client.get(url).send().await {
        Ok(resp) => resp.url().to_string(),
        Err(e) => return println!("Error: {}", e),
    };
    println!("Got URL: {}", final_url);

    // 2. Consume it once (Simulating probe_url)
    println!(
        "Consume 1: {}",
        client.get(&final_url).send().await.unwrap().status()
    );

    // 3. Consume it again (Simulating the actual download)
    println!(
        "Consume 2: {}",
        client.get(&final_url).send().await.unwrap().status()
    );

    // 4. Consume it third time
    println!(
        "Consume 3: {}",
        client.get(&final_url).send().await.unwrap().status()
    );
}
