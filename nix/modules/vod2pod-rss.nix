{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.vod2pod-rss;
  audioCodecEnum = lib.enumFromList [
    "mp3"
    "opus"
    "oggVorbis"
  ];
in
{
  options.services.vod2pod-rss = {
    enable = lib.mkEnableOption "vod2pod-rss service";

    package = lib.mkOption {
      type = lib.types.package;
      defaultText = lib.literalMD "flake's package output";
      description = "The vod2pod-rss package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host address to bind the web server to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    transcode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable live ffmpeg transcoding.";
    };

    mp3Bitrate = lib.mkOption {
      type = lib.types.int;
      default = 192;
      description = "Bitrate in kilobits of the MP3 transcode.";
    };

    audioCodec = lib.mkOption {
      type = audioCodecEnum;
      default = "mp3";
      description = "Audio codec for transcoding.";
    };

    subfolder = lib.mkOption {
      type = lib.types.str;
      default = "/";
      description = "Root path prefix for reverse proxies.";
    };

    validUrlDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Comma-separated list of domains allowed for RSS conversion.";
    };

    cacheTTL = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = "Cache TTL in seconds.";
    };

    ffmpegTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Timeout in seconds for ffmpeg transcoding.";
    };

    youtubeApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "YouTube Data API v3 key (optional, limits feed to 15 items without it).";
    };

    twitchClientId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Twitch API client ID (optional).";
    };

    twitchSecretKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Twitch API secret key (optional).";
    };

    youtubeMaxResults = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Maximum number of YouTube results to fetch.";
    };

    youtubeYtDlpExtraArgs = lib.mkOption {
      type = lib.types.str;
      default = "[]";
      description = "JSON array of extra arguments passed to yt-dlp for URL extraction.";
    };

    peertubeValidHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of allowed PeerTube host domains.";
    };

    redisAddress = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Redis server address.";
    };

    redisPort = lib.mkOption {
      type = lib.types.port;
      default = 6379;
      description = "Redis server port.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for the configured port.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "INFO"
        "DEBUG"
        "WARN"
        "ERROR"
      ];
      default = "INFO";
      description = "Rust log level.";
    };

    timezone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Timezone for log timestamps.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.redis = {
          enable = true;
          settings = {
            save = "20 1";
            loglevel = "warning";
          };
          bind = cfg.redisAddress;
          port = cfg.redisPort;
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

        systemd.services.vod2pod-rss = {
          description = "vod2pod-rss — VoD to podcast RSS converter";
          after = [ "redis.service" ];
          wants = [ "redis.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            ExecStart = lib.getExe cfg.package;
            Restart = "on-failure";
            Environment = [
              "VOD2POD_RSS_HOST=${cfg.host}"
              "VOD2POD_RSS_PORT=${toString cfg.port}"
              "TRANSCODE=${if cfg.transcode then "true" else "false"}"
              "MP3_BITRATE=${toString cfg.mp3Bitrate}"
              "AUDIO_CODEC=${lib.toUpper cfg.audioCodec}"
              "SUBFOLDER=${cfg.subfolder}"
              "VALID_URL_DOMAINS=${lib.concatStringsSep "," cfg.validUrlDomains}"
              "CACHE_TTL=${toString cfg.cacheTTL}"
              "FFMPEG_TIMEOUT_SECONDS=${toString cfg.ffmpegTimeoutSeconds}"
              "YOUTUBE_MAX_RESULTS=${toString cfg.youtubeMaxResults}"
              "YOUTUBE_YT_DLP_GET_URL_EXTRA_ARGS=${cfg.youtubeYtDlpExtraArgs}"
              "PEERTUBE_VALID_DOMAINS=${lib.concatStringsSep "," cfg.peertubeValidHosts}"
              "REDIS_ADDRESS=${cfg.redisAddress}"
              "REDIS_PORT=${toString cfg.redisPort}"
              "RUST_LOG=${cfg.logLevel}"
            ]
            ++ lib.optionals (cfg.youtubeApiKey != null) [
              "YT_API_KEY=${cfg.youtubeApiKey}"
            ]
            ++ lib.optionals (cfg.twitchClientId != null) [
              "TWITCH_CLIENT_ID=${cfg.twitchClientId}"
            ]
            ++ lib.optionals (cfg.twitchSecretKey != null) [
              "TWITCH_SECRET=${cfg.twitchSecretKey}"
            ]
            ++ lib.optionals (cfg.timezone != null) [
              "TZ=${cfg.timezone}"
            ];

            User = "vod2pod-rss";
            Group = "vod2pod-rss";
            RuntimeDirectory = "vod2pod-rss";
            StateDirectory = "vod2pod-rss";
            ReadWritePaths = [ "/var/lib/vod2pod-rss" ];
          };

          users.users = lib.mkIf pkgs.stdenv.isLinux {
            vod2pod-rss = {
              description = "vod2pod-rss service user";
              home = "/var/lib/vod2pod-rss";
              createHome = true;
              homeMode = "750";
              isSystemUser = true;
              group = "vod2pod-rss";
            };
          };

          users.groups.vod2pod-rss = lib.mkIf pkgs.stdenv.isLinux { };
        };
      }
    ]
  );
}
