{
  description = "vod2pod-rss — VoD to podcast RSS converter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      ytDlpVersion = (import ./nix/yt-dlp-version.nix).version;

      ytDlpFor =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "yt-dlp";
          version = ytDlpVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/yt-dlp/yt-dlp/releases/download/${ytDlpVersion}/yt-dlp";
            hash = "sha256-5dV0Zmgs+p1h6c98ik8JsA9KYq8307vcS8/99jYV/qw=";
          };

          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            cp $src $out/bin/yt-dlp
            chmod +x $out/bin/yt-dlp
          '';

          meta = {
            description = "Feature-rich command-line audio/video downloader";
            license = pkgs.lib.licenses.unlicense;
          };
        };

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      # Rust target triple for each system
      rustTarget =
        system:
        if system == "x86_64-linux" then "x86_64-unknown-linux-gnu" else "aarch64-unknown-linux-gnu";

    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          lib = pkgs.lib;

          rustPlatform = pkgs.makeRustPlatform {
            cargo = pkgs.cargo;
            rustc = pkgs.rustc;
          };

          ytDlpPkg = ytDlpFor pkgs;
          target = rustTarget system;

        in
        {
          default = self.packages.${system}.package;

          package = rustPlatform.buildRustPackage {
            pname = "vod2pod-rss";
            version = "1.2.5";

            src = lib.cleanSourceWith {
              src = ./.;
              filter =
                name: type:
                let
                  baseName = baseNameOf name;
                in
                !(baseName == "target" || baseName == ".git");
            };

            # Cargo.lock is generated on-demand (not tracked in git).
            # Regenerate with: nix develop -c cargo update

            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            nativeBuildInputs = with pkgs; [
              pkg-config
              openssl.dev
              perl
            ];

            buildInputs = with pkgs; [
              ffmpeg
              openssl
              ytDlpPkg
            ];

            OPENSSL_DIR = pkgs.openssl.dev;

            doCheck = false;
            # Tests requiring API keys (YT_API_KEY, TWITCH_SECRET/TWITCH_CLIENT_ID)
            # are skipped. Run locally with: nix develop -c cargo test --lib

            # Copy templates and binary
            installPhase = ''
              mkdir -p $out/bin $out/templates
              cp target/${target}/release/app $out/bin/vod2pod-rss
              cp -r templates $out/
            '';

            meta = {
              description = "Converts YouTube, Twitch, and PeerTube channels into podcast RSS feeds";
              homepage = "https://github.com/madiele/vod2pod-rss";
              license = lib.licenses.mit;
              mainProgram = "vod2pod-rss";
              platforms = [
                "x86_64-linux"
                "aarch64-linux"
              ];
            };
          };
        }
      );

      # Run checks with "nix flake check --no-build"
      checks.x86_64-linux.vod2pod-rss-module-eval =
        let
          pkgs = pkgsFor "x86_64-linux";
          eval = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              self.nixosModules.vod2pod-rss
              {
                boot.isContainer = true;
                fileSystems."/" = {
                  device = "/dev/null";
                  fsType = "ext4";
                };
                system.stateVersion = "26.05";

                services.vod2pod-rss = {
                  enable = true;
                  package = pkgs.hello;
                };
              }
            ];
          };
        in
        pkgs.runCommand "vod2pod-rss-module-eval" { } ''
          echo ${eval.config.system.build.toplevel.drvPath} > $out
        '';

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          ytDlpPkg = ytDlpFor pkgs;
        in
        {
          default = pkgs.mkShell {
            name = "vod2pod-rss-dev";

            packages = with pkgs; [
              cargo
              rustc
              rust-analyzer
              cargo-watch
              ffmpeg
              ytDlpPkg
              redis
              openssl.dev
            ];

            OPENSSL_DIR = pkgs.openssl.dev;

            shellHook = ''
              export REDIS_ADDRESS=localhost
              export REDIS_PORT=6379
            '';
          };
        }
      );

      nixosModules.vod2pod-rss = import ./nix/modules/vod2pod-rss.nix self;
    };
}
