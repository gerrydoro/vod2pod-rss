# Project Debug Rules (Non-Obvious Only)
- Tests may require API keys (e.g., `YT_API_KEY`). Failures without keys are expected.
- Some tests use `localhost` or mock responses - ensure `make start-deps` has run to start Redis.
- If transcoding issues occur, check `ffmpeg` installation and `yt-dlp` path.
- Logs can be set via `RUST_LOG` environment variable (e.g., `RUST_LOG=DEBUG`).
