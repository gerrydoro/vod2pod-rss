# Project Coding Rules (Non-Obvious Only)
- When adding a new media provider:
  - Implement `MediaProvider` trait in `src/provider/<new_provider>.rs`.
  - MUST register in `src/provider/mod.rs` using the `generate_static_dispatcher!` macro.
- Always use `eyre::Result` for error handling to ensure proper context.
- All network requests MUST use `domain_whitelist_regexes` from the provider for security.
- `yt-dlp` must be in the system PATH.
