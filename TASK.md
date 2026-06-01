I have an instance of vod2pod-rss on "https://podcasts.gerryd.myaddr.io/" configured as following

```nix
  # VoD2Pod-RSS Service Configuration
  services.vod2pod-rss = {
    enable = true;
    port = 65001; # Using port 65001 (same as old configuration)

    # API Keys and Settings
    settings = {
      ytApiKey = "my-api-key";
      useBestAudioQuality = true; # Set to true to use best audio quality from yt-dlp
      audioCodec = "OPUS";
    };
  };
```

When I play an episode on my client (e.g. "https://podcasts.gerryd.myaddr.io/transcode_media/to.mp3?bitrate=192&uuid=28e827bb-68b8-46c8-8d0c-0e68a29a3ff9&duration=2174&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdKNRlhTpPqI&ext=.opus") the client throws an error about OPUS decoding

Please, have a look at the project and propose a solution.
Feel free to check the logs for the systemd unit vod2pod-rss.service to get more info, and to try test the output of the example url I provided you to see what's going on.