{
  description = "VoD2Pod-RSS - Convert video-on-demand content into audio podcast feeds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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

        # Runtime dependencies (shared between package and devShell)
        runtimeDeps = with pkgs; [
          ffmpeg
          yt-dlp
          redis
        ];

        # VoD2Pod-RSS package (for production)
        vod2pod-rss-pkg = pkgs.rustPlatform.buildRustPackage {
          pname = "vod2pod-rss";
          version = "1.2.6";

          src = ./.;

          # Use native TLS (OpenSSL) instead of rustls
          buildInputs = with pkgs; [
            openssl
            libiconv
          ];

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
            makeWrapper
            perl
          ];

          # Cargo lock file for reproducible builds
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          # Disable tests in package build (they require API keys)
          doCheck = false;

          postInstall = ''
            wrapProgram $out/bin/app \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
              --set-default RUST_LOG INFO \
              --set-default MP3_BITRATE 192 \
              --set-default TRANSCODE true \
              --set-default REDIS_ADDRESS localhost \
              --set-default REDIS_PORT 6379 \
              --set-default SUBFOLDER / \
              --set-default VOD2POD_RSS_HOST 0.0.0.0 \
              --set-default VOD2POD_RSS_PORT 8080

            # Copy templates directory
            cp -r templates $out/templates
          '';

          meta = with pkgs.lib; {
            description = "Convert YouTube, Twitch, PeerTube, or RSS feeds into podcast RSS feeds";
            homepage = "https://github.com/gerrydoro/vod2pod-rss";
            license = licenses.mit;
            maintainers = [ maintainers.geralddoro ];
            mainProgram = "app";
          };
        };
      in
      {
        packages = {
          default = vod2pod-rss-pkg;
          vod2pod-rss = vod2pod-rss-pkg;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = vod2pod-rss-pkg;
          name = "vod2pod-rss";
        };

        # Development shell (references external nix/devShell.nix)
        devShells.default = import ./nix/devShell.nix {
          inherit pkgs runtimeDeps;
          inherit rustToolchain;
        };
      }
    );

  # NixOS module (top-level, not per-system)
  # The module is wrapped in an attribute set so that consumers can
  # access inputs.vod2pod-rss.nixosModules.default as an attribute set
  # with an 'imports' key containing the actual module.
  nixosModules.default = {
    imports = [ (import ./nix/nixosModules.nix) ];
  };
}
