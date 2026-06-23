use reqwest::Client;

#[tokio::main]
async fn main() {
    let url = "https://porngun.net/2118/daisy-summers-seduced-in-the-bathroom/";
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build().unwrap();
    
    let html = client.get(url).send().await.unwrap().text().await.unwrap();
    
    let download_re = regex::Regex::new(r#"href=["'](?:https?://[^/]+)?(/download/[0-9]+/[0-9]+/[^/"']+/?)["']"#).unwrap();
    let count = download_re.captures_iter(&html).count();
    println!("Found {} download links matching regex", count);
    
    for cap in download_re.captures_iter(&html) {
        println!("Match: {}", &cap[1]);
    }
}
