{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.vod2pod-rss;

  defaultYtDlpArgs = [ "-U" ];

  formatYtDlpArgs = args:
    if args == [ ] then "[]"
    else builtins.concatStringsSep "," (map (s: ''"${s}"'') args);
in
{
  options.services.vod2pod-rss = {
    enable = lib.mkEnableOption "VoD2Pod-RSS service for converting video feeds to podcast RSS";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vod2pod-rss;
      defaultText = lib.literalExpression "pkgs.vod2pod-rss";
      description = "The VoD2Pod-RSS package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "vod2pod-rss";
      description = "User under which VoD2Pod-RSS runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "vod2pod-rss";
      description = "Group under which VoD2Pod-RSS runs.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host address to bind to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for VoD2Pod-RSS.";
    };

    settings = {
      transcode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable/disable transcoding.";
      };

      mp3Bitrate = lib.mkOption {
        type = lib.types.int;
        default = 192;
        description = "Audio bitrate in kbps.";
      };

      subfolder = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Root path for reverse proxy support.";
      };

      ytApiKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "YouTube API key (optional, lifts 15-item limit).";
      };

      twitchClientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Twitch API client ID.";
      };

      twitchSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Twitch API secret.";
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

      cacheTtl = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Cache TTL in seconds.";
      };

      validUrlDomains = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Comma-separated allowed domains for SSRF protection.";
      };

      audioCodec = lib.mkOption {
        type = lib.types.enum [ "MP3" "OPUS" "OGG_VORBIS" ];
        default = "MP3";
        description = "Output codec.";
      };

      youtubeYtDlpGetUrlExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaultYtDlpArgs;
        description = "JSON array of extra yt-dlp arguments.";
      };

      ffmpegTimeoutSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "ffmpeg operation timeout in seconds.";
      };

      rustLog = lib.mkOption {
        type = lib.types.str;
        default = "INFO";
        description = "Rust log level.";
      };
    };

    redisService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable and configure the Redis service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users = lib.mkIf (cfg.user == "vod2pod-rss") {
      vod2pod-rss = {
        isSystemUser = true;
        group = "vod2pod-rss";
        description = "VoD2Pod-RSS service user";
        home = "/var/lib/vod2pod-rss";
        createHome = true;
      };
    };

    users.groups = lib.mkIf (cfg.group == "vod2pod-rss") {
      vod2pod-rss = { };
    };

    # Enable Redis if requested
    services.redis = lib.mkIf cfg.redisService {
      enable = true;
      servers.vod2pod = {
        port = cfg.settings.redisPort;
      };
    };

    # VoD2Pod-RSS systemd service
    systemd.services.vod2pod-rss = {
      description = "VoD2Pod-RSS - Convert video feeds to podcast RSS";
      after = [
        "network.target"
      ] ++ lib.optional cfg.redisService "redis-vod2pod.service";

      requires = lib.optional cfg.redisService "redis-vod2pod.service";

      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart = "${cfg.package}/bin/app";

        # Restart policy
        Restart = "always";
        RestartSec = "5s";

        # Security hardening (relaxed to allow ffmpeg/yt-dlp to work)
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Allow network access
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];

        # Working directory
        WorkingDirectory = "/var/lib/vod2pod-rss";

        # Environment - PATH must include ffmpeg and yt-dlp for child processes
        Environment = [
          "PORT=${toString cfg.port}"
          "PATH=${pkgs.ffmpeg}/bin:${pkgs.yt-dlp}/bin:${pkgs.deno}/bin:/nix/store/d4c56s8wa6rz2dnw6ridg7r1dvax1gky-gnugrep-3.12/bin:/nix/store/0zqnw11n1hk8mflzzvrz7sv1rm1cbnp8-gnused-4.9/bin:/nix/store/wkkwxc04gdw6b263l1h29pjarjnjdyb6-coreutils-9.8/bin:/run/wrappers/bin"
          "TRANSCODE=${if cfg.settings.transcode then "true" else "false"}"
          "MP3_BITRATE=${toString cfg.settings.mp3Bitrate}"
          "SUBFOLDER=${cfg.settings.subfolder}"
          "REDIS_ADDRESS=${cfg.settings.redisAddress}"
          "REDIS_PORT=${toString cfg.settings.redisPort}"
          "CACHE_TTL=${toString cfg.settings.cacheTtl}"
          "AUDIO_CODEC=${cfg.settings.audioCodec}"
          "FFMPEG_TIMEOUT_SECONDS=${toString cfg.settings.ffmpegTimeoutSeconds}"
          "RUST_LOG=${cfg.settings.rustLog}"
          "YOUTUBE_YT_DLP_GET_URL_EXTRA_ARGS=${formatYtDlpArgs cfg.settings.youtubeYtDlpGetUrlExtraArgs}"
        ] ++ lib.optional (cfg.settings.ytApiKey != null) "YT_API_KEY=${cfg.settings.ytApiKey}"
          ++ lib.optional (cfg.settings.twitchClientId != null) "TWITCH_CLIENT_ID=${cfg.settings.twitchClientId}"
          ++ lib.optional (cfg.settings.twitchSecret != null) "TWITCH_SECRET=${cfg.settings.twitchSecret}"
          ++ lib.optional (cfg.settings.validUrlDomains != null) "VALID_URL_DOMAINS=${lib.concatStringsSep "," cfg.settings.validUrlDomains}"
          ++ lib.mapAttrsToList (name: value: "${name}=${value}") cfg.environment;
      };
    };

    # Ensure templates directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/vod2pod-rss 0755 ${cfg.user} ${cfg.group} -"
      "d /var/lib/vod2pod-rss/templates 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Copy templates on activation
    systemd.services.vod2pod-rss.preStart = ''
      if [ -d "${cfg.package}/templates" ]; then
        cp -r ${cfg.package}/templates/* /var/lib/vod2pod-rss/templates/ 2>/dev/null || true
      fi
    '';

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [ cfg.port ];
  };
}
