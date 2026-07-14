use reqwest::Client;

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/download/2118/4674/360p/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        // .redirect(reqwest::redirect::Policy::limited(5))
        .build()
        .unwrap();

    match client.get(url).send().await {
        Ok(resp) => {
            println!("Final URL: {}", resp.url());
            println!("Status: {}", resp.status());
            println!("Headers: {:#?}", resp.headers());
        }
        Err(e) => println!("Error: {}", e),
    }
}
