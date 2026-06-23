use reqwest::{Client};

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build().unwrap();
    
    let final_url = match client.get(url).send().await {
        Ok(resp) => resp.url().to_string(),
        Err(e) => return println!("Error: {}", e),
    };
    println!("Got URL: {}", final_url);

    // Concurrent requests
    let c1 = client.clone();
    let f1 = final_url.clone();
    let t1 = tokio::spawn(async move { c1.get(&f1).send().await.unwrap().status() });

    let c2 = client.clone();
    let f2 = final_url.clone();
    let t2 = tokio::spawn(async move { c2.get(&f2).send().await.unwrap().status() });

    let c3 = client.clone();
    let f3 = final_url.clone();
    let t3 = tokio::spawn(async move { c3.get(&f3).send().await.unwrap().status() });

    println!("Req 1: {}", t1.await.unwrap());
    println!("Req 2: {}", t2.await.unwrap());
    println!("Req 3: {}", t3.await.unwrap());
}
