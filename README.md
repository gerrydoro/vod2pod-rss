# VoD2Pod-RSS Project Context

## Project Overview

**VoD2Pod-RSS** is a Rust-based application that converts video-on-demand (VoD) content from platforms like YouTube, Twitch, PeerTube, or generic RSS/Atom feeds into audio podcast RSS feeds. The converted feeds can be listened to in any standard podcast client.

### Key Features

- **Multi-platform Support**: YouTube, Twitch, PeerTube, and generic RSS/Atom feeds
- **On-the-fly Transcoding**: VoDs are transcoded to MP3 (default 192k), OPUS, or OGG Vorbis without server-side storage
- **RSS Feed Generation**: Creates proper podcast RSS feeds with iTunes extensions
- **Caching**: Uses Redis for caching generated feeds and stream URLs
- **Web UI**: Includes a simple web interface for generating podcast URLs
- **Self-hosted**: Designed for personal hosting with Docker or NixOS

### Architecture

The application consists of three main phases:

1. **Feed Generation**: Implements the `MediaProvider` trait for each platform (YouTube, Twitch, PeerTube, Generic)
2. **Feed Rewriting**: Injects transcoding URLs into the generated RSS feed
3. **Live Transcoding**: Uses ffmpeg to transcode videos on-demand when clients request the audio stream

### Directory Structure

```
vod2pod-rss/
├── src/
│   ├── lib.rs              # Library root, exports modules
│   ├── main.rs             # Application entry point
│   ├── configs/            # Configuration management (environment variables)
│   │   └── mod.rs
│   ├── provider/           # Media provider implementations
│   │   ├── mod.rs          # MediaProvider trait and dispatcher macro
│   │   ├── youtube.rs      # YouTube provider (API + atom feed fallback)
│   │   ├── twitch.rs       # Twitch provider
│   │   ├── peertube.rs     # PeerTube provider
│   │   └── generic.rs      # Generic RSS/Atom feed provider
│   ├── rss_transcodizer/   # RSS feed modification logic
│   ├── server/             # Actix-web HTTP server
│   │   └── mod.rs
│   └── transcoder/         # ffmpeg transcoding logic
├── templates/              # HTML templates for web UI
├── tests/                  # Integration tests
├── Cargo.toml              # Rust dependencies and project metadata
├── Makefile                # Development commands
├── docker-compose.yml      # Production Docker setup
├── Dockerfile              # Multi-arch Docker build
├── flake.nix               # Nix flake with NixOS module
└── nixos-module.nix        # Standalone NixOS module
```

## Building and Running

### Prerequisites

- **Rust** (stable toolchain)
- **Redis** (for caching)
- **ffmpeg** (for transcoding)
- **yt-dlp** (for URL extraction from YouTube and other platforms)
- **Deno** (optional, for some provider functionality)

### Development Setup

#### Using Make (Recommended)

```bash
# Install dependencies (Ubuntu/Debian)
make install-ubuntu-deps

# Install dependencies (Fedora)
make install-fedora-deps

# Start required services (Redis)
make start-deps

# Run tests
make test

# Run the server
make run

# Hot-reload on file changes
make hot-reload
```

#### Manual Setup

```bash
# Install system dependencies
sudo apt install -y ffmpeg python3-pip redis
pip3 install yt-dlp

# Start Redis
redis-server

# Set environment variables (optional)
export REDIS_ADDRESS=localhost
export REDIS_PORT=6379
export MP3_BITRATE=192
export TRANSCODE=true
export SUBFOLDER=/

# Run the application
cargo run --bin app
```

### Docker Deployment

```bash
# Using docker-compose
docker compose up -d

# Update
docker compose pull && docker compose up -d
```

### NixOS Module

```nix
{
  services.vod2pod-rss = {
    enable = true;
    port = 65001;
    settings = {
      ytApiKey = "your-youtube-api-key";  # Optional, for >15 items
      useBestAudioQuality = true;
      audioCodec = "MP3";  # MP3, OPUS, or OGG_VORBIS
    };
  };
}
```

## Configuration

Environment variables (can be set in `.env` file or Docker compose):

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_ADDRESS` | `localhost` | Redis server address |
| `REDIS_PORT` | `6379` | Redis server port |
| `MP3_BITRATE` | `192` | Transcoding bitrate in kbps |
| `TRANSCODE` | `true` | Enable/disable transcoding |
| `SUBFOLDER` | `/` | Root path for reverse proxy support |
| `YT_API_KEY` | - | YouTube API key (for >15 results) |
| `TWITCH_CLIENT_ID` | - | Twitch API client ID |
| `TWITCH_SECRET` | - | Twitch API secret |
| `AUDIO_CODEC` | `MP3` | Audio codec: MP3, OPUS, OGG_VORBIS |
| `USE_BEST_AUDIO_QUALITY` | `false` | Use best audio from yt-dlp |
| `CACHE_TTL` | `600` | Cache TTL in seconds |
| `VALID_URL_DOMAINS` | - | Comma-separated allowed domains |
| `YOUTUBE_YT_DLP_GET_URL_EXTRA_ARGS` | `[]` | Extra args for yt-dlp (JSON array) |

## API Endpoints

- `GET /` - Web UI for generating podcast URLs
- `GET /transcodize_rss?url=<channel_url>` - Generate podcast RSS feed
- `GET /transcode_media/to.mp3?url=<video_url>&bitrate=<kbit>&duration=<secs>` - Transcode video to audio
- `GET /health` - Health check endpoint

## Provider System

### MediaProvider Trait

Each platform provider implements the `MediaProvider` trait:

```rust
#[async_trait]
pub trait MediaProvider {
    async fn generate_rss_feed(&self, channel_url: Url) -> eyre::Result<String>;
    async fn get_stream_url(&self, media_url: &Url) -> eyre::Result<Url>;
    fn domain_whitelist_regexes(&self) -> Vec<Regex>;
}
```

### Adding a New Provider

1. Create a new file in `src/provider/` (e.g., `newplatform.rs`)
2. Implement the `MediaProvider` trait
3. Add the provider to the dispatcher macro in `src/provider/mod.rs`:

```rust
generate_static_dispatcher!(
    Provider
    for
    YoutubeProvider,
    TwitchProvider,
    PeerTubeProvider,
    GenericProvider,
    NewPlatformProvider,  // Add here
);
```

## Testing

```bash
# Run all tests
cargo test -- --nocapture

# Watch mode (requires cargo-watch)
cargo watch -x "test -- --nocapture"
```

**Note**: Tests may require API keys for full functionality. Some tests use mocked responses or localhost URLs.

## Development Conventions

### Code Style

- Follows standard Rust conventions
- Uses `eyre` for error handling (provides better error context)
- Async/await with Tokio runtime
- Actix-web for HTTP server

### Logging

Uses the `log` crate with `simple_logger`:

```rust
use log::{info, debug, warn, error};

info!("Starting feed generation");
debug!("Detailed debug info");
warn!("Warning message");
error!("Error occurred");
```

Set log level with `RUST_LOG` environment variable:
- `RUST_LOG=DEBUG` - Full debug output
- `RUST_LOG=INFO` - Standard logging (production)
- `RUST_LOG=ERROR` - Errors only

### Caching Strategy

- **Feed Cache**: Generated RSS feeds cached in Redis by URL
- **Stream URL Cache**: YouTube stream URLs cached for 5 hours
- **Channel ID Cache**: YouTube channel username-to-ID mapping cached indefinitely

### Security Considerations

- **URL Whitelisting**: All URLs must match provider regex patterns (prevents SSRF attacks)
- **No Secrets in Logs**: API keys validated but never logged
- **Range Request Support**: Proper handling of HTTP Range headers for seeking

## Key Dependencies

### Rust (as of latest update)

| Dependency | Version | Purpose |
|------------|---------|---------|
| `actix-web` | 4.13.0 | HTTP server framework |
| `tokio` | 1.50.0 | Async runtime |
| `rss` | 2.0 | RSS feed generation |
| `feed-rs` | 2.3.1 | RSS/Atom feed parsing |
| `google-youtube3` | 7.0.0 | YouTube API client |
| `google-apis-common` | 8.0.0 | Google APIs authentication (NoToken) |
| `hyper-util` | 0.1.20 | HTTP client utilities |
| `redis` | 1.1 | Redis client for caching |
| `cached` | 0.59.0 | Caching macros with Redis backend |
| `eyre` | 0.6 | Error handling |
| `regex` | 1.12.3 | URL matching and parsing |
| `reqwest` | 0.13.2 | HTTP client |
| `chrono` | 0.4.44 | Date/time handling |
| `uuid` | 1.23.0 | UUID generation |

### Python

| Dependency | Version | Purpose |
|------------|---------|---------|
| `yt-dlp` | 2026.3.17 | Video URL extraction |

## Common Issues

### YouTube API Limit

Without an API key, YouTube feeds are limited to 15 items (uses atom feed fallback).

### Redis Connection

The application requires Redis. Ensure Redis is running and accessible at the configured address/port.

### yt-dlp Path

The application expects `yt-dlp` to be in PATH. Docker images include it; for local development, install via pip:

```bash
pip3 install yt-dlp
```

### Transcoding Performance

Default bitrate is 192kbps. Tested to work on Raspberry Pi 3-4. Adjust `MP3_BITRATE` for lower bandwidth.

## Contributing

- Discuss changes via issue before making significant changes
- Small bug fixes and typos can be submitted directly
- Add tests for new features when possible
- All PRs must pass `make test`
- Target the `main` branch for pull requests

## Related Projects

- **PodTube** (amckee): Original YouTube-to-podcast inspiration
- **TwitchToPodcastRSS** (lzeke0): Original Twitch RSS inspiration

## License

MIT License - see `LICENSE` file for details.
