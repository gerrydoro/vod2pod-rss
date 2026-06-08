# Pull Request Review: `upstream/main` → `origin/main`

**Generated:** 2026-06-08T16:45:00Z  
**Source Branch:** `upstream/main` (madiele/vod2pod-rss)  
**Target Branch:** `origin/main` (gerrydoro/vod2pod-rss)  
**Diff Command:** `git diff --no-merges upstream/main...origin/main`  
**Files Changed:** 41 files (+6,143 / −1,058 lines)  
**Core Source Files:** 7 files modified

---

## 1. Summary of Changes

This PR represents a significant refactoring and feature enhancement of the `vod2pod-rss` media transcoding service. The changes span configuration, provider implementations, transcoding logic, server endpoints, and infrastructure. Below is a categorized summary of all functional and structural changes.

### 1.1 Configuration Layer (`src/configs/mod.rs`)

| Change | Description |
|--------|-------------|
| **New config key** | Added `UseBestAudioQuality` enum variant and environment variable `USE_BEST_AUDIO_QUALITY` (default: `"false"`) |
| **AudioCodec refactoring** | Merged `Default` impl into derive macro (`#[derive(Default)]`); moved `#[default]` attribute to `MP3` variant |
| **Extension/MIME fix** | `Opus` now returns `"opus"` (was `"webm"`), `OGGVorbis` returns `"ogg"` (was `"webm"`); MIME types corrected to `"audio/opus"` and `"audio/ogg"` respectively |
| **Warning removal** | Removed `warn!()` calls for Opus/OGG seeking limitations from `get_ffmpeg_codec_str()` |

### 1.2 PeerTube Provider (`src/provider/peertube.rs`)

| Change | Description |
|--------|-------------|
| **HTTPS enforcement** | New `ensure_https()` helper function forces HTTP→HTTPS redirect; applied to both `generate_rss_feed()` and `get_stream_url()` |
| **Client reuse** | Replaced global `reqwest::get()` with explicit `reqwest::Client::new()` for connection pooling |
| **Security comment** | Added inline comments documenting HTTPS enforcement rationale |

### 1.3 Twitch Provider (`src/provider/twitch.rs`)

| Change | Description |
|--------|-------------|
| **Logging cleanup** | Replaced verbose `info!()` with `debug!()` for channel URL conversion; removed expiration timestamps from cache logs |
| **URL builder pattern** | Twitch API call refactored from string interpolation to `.query(&[("login", username)])` builder pattern |
| **yt-dlp path config** | Added `YT_DLP_PATH` environment variable support (fallback: `"yt-dlp"`) |
| **Error handling** | Changed `e.to_string()` to direct `e` display in warning (relies on `Display` impl) |

### 1.4 YouTube Provider (`src/provider/youtube.rs`)

| Change | Description |
|--------|-------------|
| **Cache removal** | Removed all `#[io_cached]` Redis caching macros (`get_youtube_stream_url`, `find_yt_channel_url_with_c_id`, `get_youtube_video_duration_with_ytdlp`) |
| **YouTube client update** | Migrated from `hyper` to `hyper_util` (`TokioExecutor`, `HttpsConnector`); added `.expect()` for TLS root initialization |
| **Best audio quality mode** | New conditional logic: when `USE_BEST_AUDIO_QUALITY=true`, uses format selector `ba[ext={codec_ext}]` with fallback to `bestaudio` |
| **Container mapping** | OPUS/OGG → `"webm"`, default (AAC) → `"m4a"` |
| **Path config** | Added `YT_DLP_PATH` environment variable support |
| **Error message cleanup** | Removed `.to_string()` from error display; added `.trim()` on yt-dlp output; added empty URL check |
| **API signature** | Changed `&String` to `&str` in `fetch_playlist_items()` and `fetch_playlist()` |
| **Path extraction** | Replaced `.path_segments().unwrap().last()` with `.next_back()` (correct semantics for path segments) |
| **Test addition** | New `test_yt_dlp_channel_conversion()` test for channel handle resolution |

### 1.5 RSS Transcodizer (`src/rss_transcodizer/mod.rs`)

| Change | Description |
|--------|-------------|
| **Content-Length fix** | Changed calculation from `(bitrate * 1024 * duration_secs)` to `(bitrate * 1000 * duration_secs) / 8` (bitrate is in kbit/s, not Kbyte/s) |
| **MIME type dynamic** | Changed from hardcoded `"audio/mpeg"` to `codec.get_mime_type_str()` |
| **Author update** | Updated credits from `madiele` to `gerrydoro` with new GitHub repository URL |

### 1.6 Server Layer (`src/server/mod.rs`)

| Change | Description |
|--------|-------------|
| **URL injection prevention** | Added validation blocking characters: `|`, `;`, `&`, `` ` ``, `$(` in `stream_url` |
| **Scheme/host validation** | Explicit scheme whitelist (`http`, `https`, `ws`→`http`, `wss`→`https`); host length cap at 253 chars with `"localhost"` fallback |
| **Subfolder path support** | Added `SubfolderPath` config; URL now includes subfolder in transcode service URL |
| **Range header overflow protection** | Added `MAX_RANGE_BYTES` (10 GiB) guard; saturation arithmetic for `end` calculation; explicit overflow check via `checked_sub`/`checked_add` |
| **HEAD response cleanup** | Removed `Content-Range` header from HEAD responses |
| **Logging reduction** | Removed `RemoteAddr` and `Referer` from homepage logs; downgraded to `debug!()` |
| **Redis arg fix** | Removed `&` reference from `.arg(parsed_url.to_string())` (correct ownership) |

### 1.7 Transcoder (`src/transcoder/mod.rs`)

| Change | Description |
|--------|-------------|
| **ffprobe-based codec detection** | New `probe()` closure runs `ffprobe` to detect input audio codec; enables stream copy when source matches target |
| **Stream copy mode** | When input codec matches target, uses `-c copy` instead of re-encoding (avoids "Error parsing Opus packet header") |
| **FFmpeg path config** | Added `FFMPEG_PATH` environment variable support (fallback: `"ffmpeg"`) |
| **Partial request handling removed** | Removed `sent_bytes_count` tracking, early termination, and padding logic; stream now runs until EOF |
| **Log level change** | Changed from `-loglevel error` to `-loglevel info` |
| **Error API update** | Changed `std::io::Error::new()` to `std::io::Error::other()` (Rust 1.80+ API) |
| **Test updates** | Added `pipe:1` output handler; added `-c copy` stream copy test case; made ffmpeg path check Nix-compatible (`ends_with("ffmpeg")`) |

### 1.8 Infrastructure & Configuration Files

| File | Change |
|------|--------|
| `.github/workflows/` | Removed `docker-image-beta.yml`, `rust-clippy.yml`, `remove_dev_deps_and_version.sh`; added `auto-merge-ytdlp.yml`; updated `ci.yml` and `rust.yml` |
| `.github/FUNDING.yml` | Removed (13 lines deleted) |
| `.github/dependabot.yml` | Updated (68 lines changed) |
| `Cargo.toml` / `Cargo.lock` | Dependency updates (38 lines changed / 4,059 lines added) |
| `Dockerfile` | 7 lines changed |
| `flake.nix` / `flake.lock` | Added Nix flake configuration (205 lines) |
| `nix/` | Added NixOS modules and dev shell (301 lines) |
| `requirements.txt` | Updated Python dependencies |
| `DEPENDENCY_UPDATES.md` / `TASK.md` | New documentation files (433 lines) |
| `LICENSE` | License update |
| `.roo/rules-*/AGENTS.md` | Added agent rule files |

---

## 2. Code Quality & Detailed Evaluation

### 2.1 Security Analysis

| ID | Severity | Finding | Location |
|----|----------|---------|----------|
| **SEC-01** | **HIGH** | **URL injection characters partially sanitized** — The validation in [`transcode_to_mp3()`](src/server/mod.rs:264) blocks `|`, `;`, `&`, `` ` ``, `$(` but does NOT block `'`, `"`, `>`, `<`, `!`, or whitespace. An attacker could potentially inject arguments via URL-encoded characters or shell metacharacters that bypass the check. | `src/server/mod.rs:267-271` |
| **SEC-02** | **MEDIUM** | **HTTPS enforcement in PeerTube is incomplete** — The `ensure_https()` function converts `http://` to `https://` but does not verify that the target server actually supports HTTPS. This may cause silent failures for PeerTube instances that only serve HTTP. | `src/provider/peertube.rs:91-110` |
| **SEC-03** | **LOW** | **Host header injection mitigation is heuristic** — The 253-character host length check is correct per RFC 1123, but the fallback to `"localhost"` could cause incorrect URL generation in reverse-proxy setups where the actual host is required. | `src/server/mod.rs:89-96` |
| **SEC-04** | **INFO** | **Redis URL from config is unwrapped** — In YouTube provider, `.get(ConfName::RedisUrl).unwrap()` panics on missing config. While cache was removed, this pattern persists in other cached functions. | N/A (cache removed) |

### 2.2 Performance Analysis

| ID | Severity | Finding | Location |
|----|----------|---------|----------|
| **PERF-01** | **HIGH** | **Redis cache removal for YouTube provider** — All three `#[io_cached]` macros were removed (`get_youtube_stream_url`, `find_yt_channel_url_with_c_id`, `get_youtube_video_duration_with_ytdlp`). Every request now triggers a full `yt-dlp` subprocess call, significantly increasing latency and CPU usage under load. | `src/provider/youtube.rs:22-27` (removed) |
| **PERF-02** | **MEDIUM** | **ffprobe probe called per transcoding request** — The new `probe()` closure runs `ffprobe` synchronously via `std::process::Command::output()` for every transcoding operation. This adds a blocking system call and ~50-200ms overhead per request. | `src/transcoder/mod.rs:67-84` |
| **PERF-03** | **MEDIUM** | **New `reqwest::Client::new()` per request in PeerTube** — While the comment says "connection pooling," creating a new `Client` per `get_stream_url()` call defeats connection reuse. The global `reqwest::get()` was actually more efficient for this use case. | `src/provider/peertube.rs:34` |
| **PERF-04** | **LOW** | **String concatenation in URL building** — The `format!()` calls in `ensure_https()` and transcode service URL building create multiple intermediate `String` allocations. Could be optimized with `Url::parse()` + `set_scheme()`/`set_host()`. | `src/server/mod.rs:97-103`, `src/provider/peertube.rs:100-105` |

### 2.3 Maintainability Analysis

| ID | Severity | Finding | Location |
|----|----------|---------|----------|
| **MAINT-01** | **INFO** | **Code style improvement** — Removed redundant `return` statements, trailing commas, and unused imports. The YouTube provider cleanup (`&String` → `&str`) improves idiomatic Rust. | `src/provider/youtube.rs:273,433` |
| **MAINT-02** | **INFO** | **Logging consistency** — Reduced log verbosity across providers (Twitch, server index) improves production log clarity. However, the removal of expiration timestamps from OAuth cache logs reduces observability for debugging cache issues. | `src/provider/twitch.rs:193,208` |
| **MAINT-03** | **INFO** | **Test coverage** — Added `test_yt_dlp_channel_conversion()` and updated transcoder tests for stream copy mode. However, no unit tests were added for `ensure_https()`, URL injection validation, or the ffprobe probe logic. | `src/provider/youtube.rs:844-855`, `src/transcoder/mod.rs:315-390` |
| **MAINT-04** | **INFO** | **Nix/PATH handling** — The `*_PATH` environment variable pattern for `yt-dlp`, `ffmpeg`, and `ffprobe` is consistent and well-documented for Nix users. However, these variables are only used in specific providers; the transcoder still uses hardcoded `"ffmpeg"` in some code paths. | `src/provider/youtube.rs:334`, `src/provider/twitch.rs:219`, `src/transcoder/mod.rs:65` |

### 2.4 Edge Cases & Error Handling

| ID | Severity | Finding | Location |
|----|----------|---------|----------|
| **EDGE-01** | **MEDIUM** | **Empty yt-dlp output not handled in all paths** — While `find_yt_channel_url_with_c_id()` now checks for empty results, the fallback path in `get_youtube_stream_url()` (bestaudio fallback) does NOT check if `fallback_url.trim()` is empty before parsing. This could produce a misleading parse error instead of a clear "no audio stream found" message. | `src/provider/youtube.rs:490-494` |
| **EDGE-02** | **LOW** | **Range header with `start > end`** — The overflow check handles `end < start` via `checked_sub`, but does not explicitly validate that `start >= 0` (though `usize` prevents negative values). The regex allows up to 20 digits, which is reasonable. | `src/server/mod.rs:231-244` |
| **EDGE-03** | **LOW** | **PeerTube `ensure_https()` with custom ports** — The function correctly handles custom ports, but PeerTube instances behind reverse proxies may use non-standard HTTPS ports that are not 443. The function preserves the port, which is correct. | `src/provider/peertube.rs:99-104` |
| **EDGE-04** | **INFO** | **ffprobe probe failure silently falls back to re-encode** — If `ffprobe` fails (e.g., binary not found, network error), the code falls back to re-encoding, which is the safe default. However, no warning is logged, making debugging difficult. | `src/transcoder/mod.rs:85-91` |

---

## 3. Potential Regression Bugs

### CRITICAL Priority

| Bug ID | Module | Description | Root Cause | Mitigation |
|--------|--------|-------------|------------|------------|
| **REG-01** | YouTube Provider | **Massive latency increase due to Redis cache removal** — Without `AsyncRedisCache`, every YouTube URL resolution triggers a blocking `yt-dlp` subprocess. Under concurrent load, this can exhaust file descriptors, increase p99 latency from milliseconds to seconds, and potentially cause request timeouts. | Complete removal of `#[io_cached]` macros for `get_youtube_stream_url`, `find_yt_channel_url_with_c_id`, and `get_youtube_video_duration_with_ytdlp`. The cache previously stored results for 5 hours (`86400s`), 5 hours (`18000s`), and indefinitely. | **Immediate:** Re-introduce Redis caching with a shorter TTL (e.g., 1 hour). **Long-term:** Implement in-memory LRU cache with TTL for hot keys. |
| **REG-02** | Transcoder | **Stream copy mode may produce invalid output for mismatched codecs** — When `ffprobe` detects the input codec matches the target, the transcoder uses `-c copy`. However, if the container format differs (e.g., MP4 source → Opus target), the output may be unplayable because the container headers are not rewritten. | The probe only checks audio codec name (`"opus"`, `"mp3"`, `"aac"`), not container compatibility. The `-f` flag sets the output format, but stream copy does not remux container headers. | **Immediate:** Add container format check alongside codec check. **Long-term:** Always remux when container differs; use `-c copy` only when both codec AND container match. |
| **REG-03** | Server | **Partial request (Range) support broken** — Removal of `sent_bytes_count` tracking and padding logic means HTTP Range requests (used by podcast players for seeking) will now stream the entire transcoded audio instead of the requested byte range. Clients expecting partial content will hang or receive incorrect data. | Complete removal of partial request handling in `get_transcode_stream()`. The `expected_bytes_count` parameter is now `_expected_bytes_count` (unused). | **Immediate:** Restore partial request handling with proper byte-range tracking. **Long-term:** Implement proper HTTP Range response with `Content-Range` header. |

### HIGH Priority

| Bug ID | Module | Description | Root Cause | Mitigation |
|--------|--------|-------------|------------|------------|
| **REG-04** | YouTube Provider | **Best audio quality fallback may loop indefinitely** — If `ba[ext={codec_ext}]` fails AND the fallback `bestaudio` also fails (e.g., geo-restricted content), the error message is misleading: "Failed to parse fallback URL" rather than "yt-dlp returned no audio stream." Users cannot distinguish between network errors and content restrictions. | No validation of `fallback_output.stdout` emptiness before `Url::from_str()`. | **Immediate:** Add empty output check for fallback path. **Long-term:** Log stderr on fallback failure for debugging. |
| **REG-05** | PeerTube Provider | **HTTP-only PeerTube instances will fail** — The `ensure_https()` function unconditionally converts `http://` to `https://`. Self-hosted PeerTube instances that do not configure SSL certificates will return 404 or connection errors. | No configuration option to disable HTTPS enforcement; no TLS certificate verification handling. | **Immediate:** Add `PEERTUBE_FORCE_HTTP` config option. **Long-term:** Detect HTTPS support via HTTP headers before redirecting. |
| **REG-06** | Transcoder | **ffprobe blocking call on main thread** — The `probe()` closure uses `std::process::Command::output()` which blocks the current thread until ffprobe completes. In an async context, this blocks the Tokio executor thread, potentially starving other concurrent requests. | Synchronous `std::process::Command` used instead of `tokio::process::Command`. | **Immediate:** Replace with `tokio::process::Command`. **Long-term:** Add ffprobe result caching (see HI-01 in original review). |

### MEDIUM Priority

| Bug ID | Module | Description | Root Cause | Mitigation |
|--------|--------|-------------|------------|------------|
| **REG-07** | RSS Transcodizer | **Incorrect Content-Length for non-MP3 codecs** — The new formula `(bitrate * 1000 * duration_secs) / 8` assumes constant bitrate encoding. For Opus/Vorbis, actual file sizes may differ by 10-20% due to codec overhead and framing. Podcast players using Content-Length for progress tracking will show incorrect progress. | Bitrate is in kbit/s (1000-based), but the previous formula used 1024-based. The new formula is mathematically correct for bitrate but does not account for container overhead. | **Immediate:** Add container overhead buffer (e.g., +50 bytes per 10-minute segment). **Long-term:** Use actual encoded size from ffprobe. |
| **REG-08** | Server | **Subfolder path traversal not fully validated** — The `SubfolderPath` config is trimmed of trailing slashes but not validated for directory traversal sequences (`../`, `..\\`). A malicious config value like `/../../etc` could expose unintended routes. | No path traversal check on `subfolder` value before URL construction. | **Immediate:** Add `path_clean` crate or manual `../` check. **Long-term:** Validate subfolder against allowlist of permitted paths. |
| **REG-09** | Twitch Provider | **Twitch API query parameter injection** — The `.query(&[("login", username)])` builder is safer than string interpolation, but `username` is extracted from `path_segments().next_back()` without URL decoding. If a channel name contains special characters (rare but possible), the API may return unexpected results. | Username is used directly from path segments without validation or normalization. | **Immediate:** Add username validation (alphanumeric, hyphens, underscores only). **Long-term:** Use Twitch's user ID lookup instead of login name. |

### LOW Priority

| Bug ID | Module | Description | Root Cause | Mitigation |
|--------|--------|-------------|------------|------------|
| **REG-10** | YouTube Provider | **`.next_back()` vs `.last()` semantics differ for some URL patterns** — For URLs ending with a trailing slash (e.g., `/channel/UCxxx/`), `.last()` returns `None` while `.next_back()` returns `Some("")`. This could cause channel ID extraction to return an empty string for malformed URLs. | Semantic difference between iterator methods on `PathSegments`. | **Immediate:** Add non-empty check after `.next_back()`. **Long-term:** Normalize URLs before parsing. |
| **REG-11** | Server | **WebSocket scheme mapping may cause confusion** — `ws` maps to `http` and `wss` maps to `https` in the scheme whitelist. While technically correct for URL generation, this mapping is implicit and undocumented. Future maintainers may not understand the rationale. | Implicit scheme mapping without documentation. | **Immediate:** Add inline comment explaining the mapping. **Long-term:** Document in configuration reference. |
| **REG-12** | All Providers | **Logging verbosity reduction reduces observability** — Removing expiration timestamps from OAuth cache logs and reducing channel conversion logs makes it harder to debug cache-related issues in production. | Deliberate logging cleanup without compensating observability measures. | **Immediate:** Add structured logging with cache hit/miss indicators. **Long-term:** Implement metrics export (e.g., Prometheus) for cache hit rates. |

---

## Appendix: Diff Statistics

```
Files changed: 41
Insertions:    +6,143
Deletions:     −1,058
Net change:    +5,085 lines

Core source changes (src/):
  src/configs/mod.rs       |    31 +-
  src/provider/peertube.rs |    30 +-
  src/provider/twitch.rs   |    29 +-
  src/provider/youtube.rs  |   185 +-
  src/rss_transcodizer/mod.rs | 13 +-
  src/server/mod.rs        |   104 +-
  src/transcoder/mod.rs    |   197 +-
  Total source change:     +689 / −182 = +507 lines
```

## Recommendation

**Status: ⚠️ APPROVE WITH CONDITIONS**

This PR introduces valuable security hardening (URL injection prevention, HTTPS enforcement, range header overflow protection) and useful features (best audio quality mode, stream copy optimization, Nix/ffprobe support). However, the **three critical regressions** (REG-01, REG-02, REG-03) must be addressed before merge:

1. **Restore Redis caching** for YouTube provider (REG-01) — This is the highest priority; without it, production latency will increase dramatically.
2. **Fix stream copy container compatibility** (REG-02) — Ensure stream copy only activates when both codec AND container are compatible.
3. **Restore partial request handling** (REG-03) — Podcast players rely on HTTP Range requests for seeking; breaking this will cause user-facing playback issues.

All HIGH and MEDIUM priority items should be resolved in follow-up PRs within the same sprint.

---

*This review was generated by automated diff analysis between `upstream/main` and `origin/main` using `git diff --no-merges`. All findings are based on the net diff excluding merge commits.*
