use std::{borrow::Cow, collections::HashMap, net::TcpListener, time::Instant};

use actix_web::{
    dev::Server, guard, http, middleware, web, App, HttpRequest, HttpResponse, HttpServer,
};
use log::{debug, error, info, warn};
use regex::Regex;
use serde::Deserialize;
use url::Url;

use crate::{
    configs::{conf, Conf, ConfName},
    provider::{self, MediaProvider},
    rss_transcodizer,
    transcoder::{FfmpegParameters, Transcoder},
};

pub fn spawn_server(listener: TcpListener) -> eyre::Result<Server> {
    let root = conf().get(ConfName::SubfolderPath).unwrap();
    Ok(HttpServer::new(move || {
        App::new()
            .wrap(middleware::NormalizePath::new(
                middleware::TrailingSlash::MergeOnly,
            ))
            .service(
                web::scope(&root)
                    .service(
                        web::resource("transcode_media/to.mp3")
                            .name("transcode_mp3")
                            .guard(guard::Any(guard::Get()).or(guard::Head()))
                            .to(transcode_to_mp3),
                    )
                    .service(
                        //this is an old URL used in old vod2pod versions that did not work with
                        //itunes kept for backwards compatiility
                        web::resource("transcode_media/to_mp3")
                            .name("transcode_mp3_obsolete")
                            .guard(guard::Any(guard::Get()).or(guard::Head()))
                            .to(transcode_to_mp3),
                    )
                    .route("transcodize_rss", web::get().to(transcodize_rss))
                    .route("transcodize_rss", web::head().to(transcodize_rss))
                    .route("health", web::get().to(health))
                    .route("oauth_health", web::get().to(oauth_health_check))
                    .route("/", web::get().to(index))
                    .route("", web::get().to(index)),
            )
    })
    .listen(listener)?
    .run())
}

async fn health() -> HttpResponse {
    HttpResponse::Ok().finish()
}

/// LW-02: OAuth token health check endpoint for YouTube provider
/// Returns 200 OK if OAuth token is valid, 503 if expired or missing
async fn oauth_health_check() -> HttpResponse {
    // Check if YouTube OAuth is configured
    let youtube_api_key = match conf().get(ConfName::YoutubeApiKey) {
        Ok(key) if !key.is_empty() => key,
        _ => {
            // No API key configured - not an error, just skip
            return HttpResponse::Ok().json(serde_json::json!({
                "status": "ok",
                "oauth_configured": false
            }));
        }
    };

    // Attempt a minimal YouTube API call to verify token validity
    // Using search.list with maxResults=1 is the cheapest valid call
    let youtube = match crate::provider::youtube::get_youtube_client(youtube_api_key).await {
        Ok(client) => client,
        Err(_) => {
            warn!("OAuth token validation failed");
            return HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "status": "error",
                "message": "OAuth token invalid or expired"
            }));
        }
    };

    // Perform a minimal API call to validate the token
    match youtube.search()
        .list(&vec!["snippet".into()])
        .q("health check")
        .max_results(1)
        .doit()
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "oauth_configured": true
        })),
        Err(_) => {
            warn!("OAuth token API call failed");
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "status": "error",
                "message": "OAuth token expired or invalid"
            }))
        }
    }
}

async fn index(req: HttpRequest) -> HttpResponse {
    if req.headers().get("User-Agent").is_some() {
        debug!("serving homepage");
    }

    let html = std::fs::read_to_string("./templates/index.html").unwrap();

    HttpResponse::Ok().content_type("text/html").body(html)
}
async fn transcodize_rss(
    req: HttpRequest,
    query: web::Query<HashMap<String, String>>,
) -> HttpResponse {
    if req.method() == http::Method::HEAD {
        return HttpResponse::Ok().finish();
    }

    let start_time = Instant::now();

    let should_transcode = match conf().get(ConfName::TranscodingEnabled) {
        Ok(value) => !value.eq_ignore_ascii_case("false"),
        Err(_) => true,
    };

    if !should_transcode {
        warn!("transcoding is disabled");
    }
    let url = if let Some(x) = query.get("url") {
        x
    } else {
        error!("no url provided");
        return HttpResponse::BadRequest().finish();
    };

    // Build transcode service URL using request connection info and configured subfolder path
    let subfolder = conf().get(ConfName::SubfolderPath).unwrap_or_else(|_| "/".to_string());
    // MD-04: Validate subfolder path to prevent directory traversal
    if subfolder.contains("..") || subfolder.contains('\0') {
        error!("invalid subfolder path containing traversal sequences: {}", subfolder);
        return HttpResponse::BadRequest().body("invalid configuration: subfolder path");
    }
    // Validate subfolder contains only safe characters
    if !subfolder.is_empty() && !subfolder.chars().all(|c| c.is_alphanumeric() || c == '/' || c == '-' || c == '_' || c == '.') {
        error!("subfolder path contains invalid characters: {}", subfolder);
        return HttpResponse::BadRequest().body("invalid configuration: subfolder path");
    }

    let conn_info = req.connection_info();
    // Validate scheme to prevent injection through X-Forwarded-Proto
    let scheme = match conn_info.scheme() {
        "https" => "https",
        "http" => "http",
        "ws" => "http",
        "wss" => "https",
        _ => "http", // Default to http for unknown schemes
    };
    // Validate host to prevent Host header injection attacks
    let host = conn_info.host();
    let host = if host.is_empty() || host.len() > 253 {
        "localhost"
    } else {
        host
    };
    let transcode_service_url = Url::parse(&format!(
        "{}://{}{}/transcode_media/to.mp3",
        scheme,
        host,
        subfolder.trim_end_matches('/')
    ))
    .expect("valid transcode service URL");

    let parsed_url = match Url::parse(url) {
        Ok(x) => x,
        Err(e) => return HttpResponse::BadRequest().body(e.to_string()),
    };

    let provider = provider::from(&parsed_url);

    if !provider
        .domain_whitelist_regexes()
        .iter()
        .any(|r| r.is_match(parsed_url.as_ref()))
    {
        error!("supplied url ({parsed_url}) not in whitelist (whitelist is needed to prevent SSRF attack)");
        return HttpResponse::Forbidden().body("scheme and host not in whitelist");
    }

    //check cache
    let Ok(mut redis) = crate::get_redis_client().await else {
        error!("could not get redis client");
        return HttpResponse::InternalServerError().finish();
    };

    let cached_rss: Option<String> = redis::cmd("GET")
        .arg(parsed_url.to_string())
        .query_async(&mut redis)
        .await
        .unwrap_or_default();

    if let Some(cached_rss) = cached_rss {
        info!("serving cached rss feed for {parsed_url}");
        return HttpResponse::Ok()
            .content_type("application/xml")
            .body(cached_rss);
    }

    //generate rss feed
    let raw_rss = match provider.generate_rss_feed(parsed_url.clone()).await {
        Ok(raw_rss) => raw_rss,
        Err(e) => {
            error!("could not generate rss feed for {parsed_url}:\n{e}");
            return HttpResponse::Conflict().finish();
        }
    };

    // rewrite urls in feed
    let injected_feed = rss_transcodizer::inject_vod2pod_customizations(
        raw_rss,
        should_transcode.then_some(transcode_service_url),
    );

    let body = match injected_feed {
        Ok(body) => body,
        Err(e) => {
            error!("could not inject vod2pod customizations into generated feed");
            error!("{e}");
            return HttpResponse::Conflict().finish();
        }
    };

    //set cache to env var CACHE_TTL (or default 600 seconds)
    let cache_ttl: u64 = match conf().get(ConfName::CacheTTL) {
        Ok(value) => value.parse().unwrap_or(600),
        Err(_) => 600,
    };
    let _: () = redis::cmd("SET")
        .arg(parsed_url.to_string())
        .arg(&body)
        .arg("EX")
        .arg(cache_ttl)
        .query_async(&mut redis)
        .await
        .unwrap_or_default();

    let end_time = Instant::now();
    let duration = end_time - start_time;
    debug!("rss generation took {} seconds", duration.as_secs_f32());

    HttpResponse::Ok()
        .content_type("application/xml")
        .body(body)
}

#[derive(Deserialize)]
struct TranscodizeQuery {
    url: Url,
    bitrate: usize,
    duration: usize,
}

fn parse_range_header(
    content_range_str: &str,
    bytes_count: usize,
) -> eyre::Result<(usize, usize, usize)> {
    // Guard against unreasonably large values that could cause overflow or DoS
    const MAX_RANGE_BYTES: usize = 10 * 1024 * 1024 * 1024; // 10 GiB
    if bytes_count > MAX_RANGE_BYTES {
        return Err(eyre::eyre!(
            "requested range exceeds maximum allowed size ({} bytes)",
            MAX_RANGE_BYTES
        ));
    }
    if bytes_count == 0 {
        error!("The requested Range header with a length of 0 is invalid: {content_range_str}");
        return Err(eyre::eyre!(
            "The requested Range header with a length of 0 is invalid: {content_range_str}"
        ));
    }

    let re = Regex::new(r"(?P<start>[0-9]{1,20})-?(?P<end>[0-9]{1,20})?")?;
    let captures = if let Some(x) = re.captures_iter(content_range_str).next() {
        x
    } else {
        return Err(eyre::eyre!("content range regex failed"));
    };

    let mut start: usize = 0;
    if let Some(x) = captures.name("start") {
        start = x.as_str().parse()?;
    }

    let mut end: usize = bytes_count.saturating_sub(1);
    if let Some(x) = captures.name("end") {
        end = x.as_str().parse()?;
    }

    // Guard against overflow
    let expected = end
        .checked_sub(start)
        .and_then(|diff| diff.checked_add(1))
        .ok_or_else(|| eyre::eyre!("range overflow: start={start}, end={end}"))?;

    if expected > MAX_RANGE_BYTES {
        return Err(eyre::eyre!(
            "requested range exceeds maximum allowed size ({} bytes)",
            MAX_RANGE_BYTES
        ));
    }

    if end == start {
        return Err(eyre::eyre!(
            "The requested Range header with a length of 0 is invalid: {content_range_str}"
        ));
    }

    Ok((start, end, expected))
}

async fn transcode_to_mp3(req: HttpRequest, query: web::Query<TranscodizeQuery>) -> HttpResponse {
    let stream_url = &query.url;
    let bitrate = query.bitrate;
    let duration_secs = query.duration;

    // HI-02: URL injection validation using URL-decoded sanitization
    // Check both raw and URL-decoded forms to catch encoded bypass attempts
    let decoded_url = urlencoding::decode(stream_url.as_str()).unwrap_or_else(|_| Cow::Owned(stream_url.as_str().to_string()));
    let dangerous_patterns = ["|", ";", "&", "`", "$(", "$(", "||", "&&", "%0a", "%0A", "%26", "%7C", "%3B"];
    let raw_str = stream_url.as_str();
    for pattern in &dangerous_patterns {
        if raw_str.contains(pattern) || decoded_url.contains(pattern) {
            error!("URL contains potentially dangerous characters: {}", stream_url);
            return HttpResponse::BadRequest().body("invalid URL");
        }
    }

    // MD-03: Content-Length overflow check for very long videos
    // Check: (duration_secs * bitrate * 1000) / 8 could overflow usize on 32-bit systems
    const MAX_DURATION_SECS: usize = 10_000_000; // ~115 days
    const MAX_BITRATE: usize = 999;
    if duration_secs > MAX_DURATION_SECS || bitrate > MAX_BITRATE {
        error!(
            "Request exceeds maximum allowed duration ({}s) or bitrate ({}k): duration={}, bitrate={}",
            MAX_DURATION_SECS, MAX_BITRATE, duration_secs, bitrate
        );
        return HttpResponse::BadRequest().body("request exceeds maximum allowed duration or bitrate");
    }

    let total_streamable_bytes = (duration_secs * bitrate * 1000) / 8;
    info!("processing transcode at {bitrate}k for {stream_url}");
    
    if let Ok(value) = conf().get(ConfName::TranscodingEnabled) {
        if value.eq_ignore_ascii_case("false") {
            return HttpResponse::Forbidden().finish();
        }
    }
    
    let provider = provider::from(stream_url);
    
    if !provider
        .domain_whitelist_regexes()
        .iter()
        .any(|r| r.is_match(stream_url.as_ref()))
    {
        error!("supplied url ({stream_url}) not in whitelist (whitelist is needed to prevent SSRF attack)");
        return HttpResponse::Forbidden().body("scheme and host not in whitelist");
    }

    // Range header parsing
    const DEFAULT_CONTENT_RANGE: &str = "0-";
    let content_range_str = match req.headers().get("Range") {
        Some(x) => x.to_str().unwrap_or_default(),
        None => DEFAULT_CONTENT_RANGE,
    };

    debug!("received content range {content_range_str}");

    let (start_bytes, end_bytes, expected_bytes) =
        match parse_range_header(content_range_str, total_streamable_bytes) {
            Ok((start, end, expected)) => (start, end, expected),
            Err(e) => return HttpResponse::BadRequest().body(e.to_string()),
        };

    debug!("requested content-range: bytes {start_bytes}-{end_bytes}/{total_streamable_bytes}");

    if start_bytes > end_bytes || start_bytes > total_streamable_bytes {
        return HttpResponse::RangeNotSatisfiable().finish();
    }

    let seek_secs =
        ((start_bytes as f32) / (total_streamable_bytes as f32)) * (duration_secs as f32);
    debug!("choosen seek_time: {seek_secs}");

    let timeout_in_seconds = conf()
        .get(ConfName::FfmpegTimeoutSeconds)
        .unwrap()
        .parse()
        .unwrap();
    debug!("choosen timeout in seconds: {timeout_in_seconds}");

    let codec = conf().get(ConfName::AudioCodec).unwrap().into();
    let ffmpeg_paramenters = FfmpegParameters {
        seek_time: seek_secs,
        url: stream_url.clone(),
        audio_codec: codec,
        bitrate_kbit: bitrate,
        max_rate_kbit: bitrate * 30,
        expected_bytes_count: expected_bytes,
        timeout_in_seconds,
    };
    debug!("seconds: {duration_secs}, bitrate: {bitrate}");

    if req.method() == http::Method::HEAD {
        return HttpResponse::Ok()
            .insert_header(("Accept-Ranges", "bytes"))
            .content_type(codec.get_mime_type_str())
            .finish();
    }

    match Transcoder::new(&ffmpeg_paramenters).await {
        Ok(transcoder) => {
            let stream = transcoder.get_transcode_stream();

            let mut response_builder = if ffmpeg_paramenters.seek_time <= 0.1 {
                HttpResponse::Ok()
            } else {
                HttpResponse::PartialContent()
            };

            response_builder
                .insert_header(("Accept-Ranges", "bytes"))
                .insert_header((
                    "Content-Range",
                    format!("bytes {start_bytes}-{end_bytes}/{total_streamable_bytes}"),
                ))
                .content_type(codec.get_mime_type_str())
                .no_chunking((expected_bytes).try_into().unwrap())
                .streaming(stream)
        }
        Err(e) => HttpResponse::ServiceUnavailable().body(e.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_start_and_end_start_to_end() {
        let content_range_str = "bytes=0-99";
        let bytes_count = 100;
        let (start, end, expected) = parse_range_header(content_range_str, bytes_count).unwrap();
        assert_eq!((start, end, expected), (0, 99, 100));
    }

    #[test]
    fn test_get_start_and_end_middle1_to_middle2() {
        let content_range_str = "bytes=50-199";
        let bytes_count = 200;
        let (start, end, expected) = parse_range_header(content_range_str, bytes_count).unwrap();
        assert_eq!((start, end, expected), (50, 199, 150));
    }

    #[test]
    fn test_get_start_and_end_middle_to_undefined() {
        let content_range_str = "bytes=100-";
        let bytes_count = 200;
        let (start, end, expected) = parse_range_header(content_range_str, bytes_count).unwrap();
        assert_eq!((start, end, expected), (100, 199, 100));
    }

    #[test]
    fn test_get_start_and_end_start_to_undefined() {
        let content_range_str = "bytes=0-";
        let bytes_count = 200;
        let (start, end, expected) = parse_range_header(content_range_str, bytes_count).unwrap();
        assert_eq!((start, end, expected), (0, 199, 200));
    }
}
