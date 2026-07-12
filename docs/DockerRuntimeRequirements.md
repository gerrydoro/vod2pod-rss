# Docker Runtime Requirements

## glibc ≥ 2.40

This project requires **glibc ≥ 2.40** at runtime due to the use of musl-based Nixpkgs
binaries that link against newer glibc features.

### Verification

To verify your system meets this requirement:

```bash
ldd --version | head -n1
```

Expected output: `ldd (GNU libc) 2.40.x` (or higher).

### Docker Images

The provided Dockerfile (`Dockerfile`) is built on a glibc ≥ 2.40 base image:

```dockerfile
FROM docker.io/library/debian:bookworm-slim AS builder
...
FROM docker.io/library/debian:bookworm-slim
```

Debian Bookworm ships with glibc 2.36. For production deployments requiring glibc ≥ 2.40,
use a newer base image:

```dockerfile
FROM docker.io/library/ubuntu:24.04
```

### NixOS

On NixOS, glibc is provided by the `glibc` package. Ensure your system uses a recent
enough nixpkgs checkout:

```bash
nix shell nixpkgs#glibc
ldd --version | head -n1
```

### Affected Components

- **yt-dlp**: The yt-dlp binary bundled in the Nix package requires glibc ≥ 2.40 for
  proper operation with certain video formats and DRM-protected content.
- **ffmpeg**: FFmpeg binaries from Nixpkgs are linked against glibc and require the
  same minimum version.

### Troubleshooting

If you encounter errors like `version 'GLIBC_2.40' not found`:

1. Update your base image to one shipping glibc ≥ 2.40.
2. Rebuild the Docker image from source using the provided `Dockerfile`.
3. On non-NixOS systems, consider using the Nix development shell to build yt-dlp
   and ffmpeg from source.
