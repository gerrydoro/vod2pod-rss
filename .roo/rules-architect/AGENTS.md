# Project Architecture Rules (Non-Obvious Only)
- The application uses a provider-based architecture where new media sources must implement the `MediaProvider` trait.
- Providers are stateless (caching is external via Redis).
- Security relies on `domain_whitelist_regexes` implemented per provider to prevent SSRF.
- Transcoding is live; no storage of transcoded files is performed by design.
- The `generate_static_dispatcher!` macro is required to register new providers in the system.
