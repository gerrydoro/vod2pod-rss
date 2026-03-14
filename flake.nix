{
  description = "VoD2Pod-RSS - Convert video-on-demand content into audio podcast feeds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;

        # Runtime dependencies
        runtimeDeps = with pkgs; [
          ffmpeg
          yt-dlp
          deno
          redis
        ];

        # Build the VoD2Pod-RSS package
        vod2pod-rss = pkgs.rustPlatform.buildRustPackage {
          pname = "vod2pod-rss";
          version = "1.2.5";

          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          # Disable tests as they require API keys
          doCheck = false;

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
            makeWrapper
            perl
          ];

          buildInputs = with pkgs; [
            openssl
            libiconv
          ];

          # Copy templates to the package
          postInstall = ''
            wrapProgram $out/bin/app \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
              --set-default RUST_LOG INFO \
              --set-default MP3_BITRATE 192 \
              --set-default TRANSCODE true \
              --set-default REDIS_ADDRESS localhost \
              --set-default REDIS_PORT 6379 \
              --set-default SUBFOLDER /

            # Copy templates directory
            cp -r templates $out/templates
          '';

          meta = with pkgs.lib; {
            description = "Convert YouTube, Twitch, PeerTube, or RSS feeds into podcast RSS feeds";
            homepage = "https://github.com/madiele/vod2pod-rss";
            license = licenses.mit;
            maintainers = [ maintainers.geralddoro ];
            mainProgram = "app";
          };
        };
      in
      {
        packages = {
          inherit vod2pod-rss;
          default = vod2pod-rss;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = vod2pod-rss;
          name = "vod2pod-rss";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustToolchain
            cargo
            rustfmt
            clippy
            openssl
            pkg-config
            ffmpeg
            yt-dlp
            deno
            redis
            cargo-watch
          ];

          shellHook = ''
            export RUST_LOG=DEBUG
            export MP3_BITRATE=192
            export TRANSCODE=true
            export REDIS_ADDRESS=localhost
            export REDIS_PORT=6379
            export SUBFOLDER=/
          '';
        };
      }
    );
}
