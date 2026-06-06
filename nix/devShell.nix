{
  pkgs,
  runtimeDeps,
  rustToolchain,
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Rust toolchain
    rustToolchain
    cargo-watch
    rustfmt
    clippy

    # Build dependencies
    pkg-config
    openssl
    libiconv
    perl

    # Runtime dependencies for tests
    ffmpeg
    yt-dlp
    redis
    python3
    python3Packages.pip

    # Testing utilities
    cargo-nextest
  ];

  # Environment variables for the project
  shellHook = ''
    # Set Redis connection for tests
    export REDIS_ADDRESS=localhost
    export REDIS_PORT=6379

    # Set default logging
    export RUST_LOG=DEBUG

    # Add runtime deps to PATH
    export PATH="${pkgs.lib.makeBinPath runtimeDeps}":$PATH

    # Start Redis if not running (optional convenience)
    if ! redis-cli ping > /dev/null 2>&1; then
      echo "Redis not running. Start with: redis-server --daemonize yes"
    fi

    echo "=== VoD2Pod-RSS Development Environment ==="
    echo "Rust: $(cargo --version)"
    echo "FFmpeg: $(ffmpeg -version | head -1)"
    echo "yt-dlp: $(yt-dlp --version)"
    echo "Redis: $(redis-cli --version | head -1)"
    echo "==========================================="
  '';
}
