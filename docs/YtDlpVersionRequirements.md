# yt-dlp Version Requirements

## Minimum Version: 2024.03.03+

This project requires **yt-dlp ≥ 2024.03.03** for full compatibility with all supported
media providers.

### Supported Providers

| Provider | Minimum yt-dlp Version | Notes |
|----------|----------------------|-------|
| YouTube | 2024.03.03 | Required for `bestaudio` extraction and OAuth token support |
| Twitch | 2024.03.03 | Required for VOD metadata parsing |
| PeerTube | 2024.03.03 | Required for ActivityPub feed parsing |

### Key Features Requiring Minimum Version

1. **`--extractor-args` with `extractAudio`**: Used by the YouTube provider to extract
   the best audio quality from videos. This requires yt-dlp 2024.03.03 or later.

2. **OAuth Token Support**: The YouTube provider supports OAuth access tokens for
   authenticated API calls. Token handling requires the updated Google extractor.

3. **Improved Error Handling**: Newer versions provide better error messages for
   geo-restricted content and age-restricted videos.

### Verification

To verify your yt-dlp installation:

```bash
yt-dlp --version
```

Expected output: `2024.03.03` or higher.

### Updating yt-dlp

On NixOS:

```bash
nix shell nixpkgs.yt-dlp
```

Using pip:

```bash
pip install --upgrade yt-dlp
```

Manual update:

```bash
yt-dlp -U
```

### Known Compatibility Issues

- **yt-dlp < 2024.03.03**: Does not support the `extractAudio` extractor argument,
  causing YouTube provider failures.
- **yt-dlp 2024.03.03 - 2024.05.27**: May have issues with certain PeerTube instances
  using ActivityPub feeds.
- **yt-dlp ≥ 2024.05.27**: Recommended for best compatibility with all providers.

### Docker

The provided Dockerfile bundles a specific version of yt-dlp from Nixpkgs. To update:

```dockerfile
# In Dockerfile, update the Nixpkgs revision:
RUN cp /nix/store/$(nix eval --raw nixpkgs.yt-dlp --extra-experimental-features nix-command)/bin/yt-dlp /usr/local/bin/yt-dlp
```

Or use the provided `flake.nix` which pins a specific Nixpkgs revision:

```bash
nix develop
yt-dlp --version
```
