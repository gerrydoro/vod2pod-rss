# Project Documentation Rules (Non-Obvious Only)
- The core provider logic resides in `src/provider/`.
- RSS feed transformation is handled in `src/rss_transcodizer/`.
- Transcoding is performed on-demand via `src/transcoder/`.
- Configuration is managed in `src/configs/`.
- `make` targets are the primary entry points for development tasks (run `make help` if available or check `Makefile`).
