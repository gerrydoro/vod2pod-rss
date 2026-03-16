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
        vod2pod-rss-pkg = pkgs.rustPlatform.buildRustPackage {
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
          default = vod2pod-rss-pkg;
          vod2pod-rss = vod2pod-rss-pkg;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = vod2pod-rss-pkg;
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
    )
    // {
      # NixOS module for system-wide installation
      nixosModules.default =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          cfg = config.services.vod2pod-rss;
        in
        {
          options.services.vod2pod-rss = {
            enable = lib.mkEnableOption "VoD2Pod-RSS service";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "VoD2Pod-RSS package to use";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 65001;
              description = "Port to listen on";
            };

            settings = {
              ytApiKey = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "YouTube API key";
              };

              useBestAudioQuality = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Use best audio quality from yt-dlp";
              };

              audioCodec = lib.mkOption {
                type = lib.types.enum [
                  "MP3"
                  "OPUS"
                  "OGG_VORBIS"
                ];
                default = "MP3";
                description = "Audio codec";
              };
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            # Redis instance for VoD2Pod-RSS
            # The application requires TCP connection (doesn't support Unix sockets)
            services.redis.servers.vod2pod = {
              enable = true;
              port = 6380;
              bind = "127.0.0.1";
            };

            # User and group for the service
            users.users.vod2pod-rss = {
              isSystemUser = true;
              group = "vod2pod-rss";
              description = "VoD2Pod-RSS service user";
              home = "/var/lib/vod2pod-rss";
              createHome = true;
            };

            users.groups.vod2pod-rss = { };

            # Systemd service configuration
            systemd.services.vod2pod-rss = {
              description = "VoD2Pod-RSS - Convert video feeds to podcast RSS";
              after = [
                "network.target"
                "redis-vod2pod.service"
              ];
              requires = [ "redis-vod2pod.service" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                User = "vod2pod-rss";
                Group = "vod2pod-rss";
                ExecStart = "${cfg.package}/bin/app";
                Restart = "always";
                RestartSec = "5s";
                WorkingDirectory = "/var/lib/vod2pod-rss";
                Environment = [
                  "PORT=${toString cfg.port}"
                  "REDIS_ADDRESS=127.0.0.1"
                  "REDIS_PORT=6380"
                  "USE_BEST_AUDIO_QUALITY=${if cfg.settings.useBestAudioQuality then "true" else "false"}"
                  "AUDIO_CODEC=${cfg.settings.audioCodec}"
                ]
                ++ lib.optional (cfg.settings.ytApiKey != null) "YT_API_KEY=${cfg.settings.ytApiKey}";

                # Security hardening
                ProtectSystem = "full";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                ];
              };

              # Copy templates on activation
              preStart = ''
                if [ -d "${cfg.package}/templates" ]; then
                  cp -r ${cfg.package}/templates/* /var/lib/vod2pod-rss/templates/ 2>/dev/null || true
                fi
              '';
            };

            # Ensure templates directory exists
            systemd.tmpfiles.rules = [
              "d /var/lib/vod2pod-rss 0755 vod2pod-rss vod2pod-rss -"
              "d /var/lib/vod2pod-rss/templates 0755 vod2pod-rss vod2pod-rss -"
            ];
          };
        };
    };
}
