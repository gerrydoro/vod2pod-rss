# AGENTS.md

This file provides guidance to agents when working with code in this repository.

- Always run `make start-deps` to ensure Redis is running before tests or development.
- When adding a new media provider:
  - Implement `MediaProvider` trait in `src/provider/<new_provider>.rs`.
  - MUST register in `src/provider/mod.rs` using the `generate_static_dispatcher!` macro.
- Tests may require API keys; those without keys will fail or use mocks.
- `yt-dlp` must be in the system PATH.
- All network requests require `domain_whitelist_regexes` from the provider for security.
