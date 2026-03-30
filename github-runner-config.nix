# GitHub Actions Runner Configuration for VoD2Pod-RSS
# 
# Import this file in your /etc/nixos/configuration.nix or flake.nix
#
# Usage in configuration.nix:
#   imports = [ ./github-runner-config.nix ];
#
# Usage in flake.nix:
#   imports = [ ./github-runner-config.nix ];
#
# After importing:
#   1. Get a registration token from GitHub (see GITHUB_RUNNERS_NIXOS.md)
#   2. Store it: echo "YOUR_TOKEN" | sudo tee /run/secrets/github-runner-token-vod2pod
#   3. Set permissions: sudo chmod 600 /run/secrets/github-runner-token-vod2pod
#   4. Rebuild: sudo nixos-rebuild switch
#
# To add more runners in the future, add new entries to services.github-runners

{ config, pkgs, ... }:

{
  # Import the GitHub runners module
  imports = [ ./nixos-github-runners.nix ];
  
  # Configure VoD2Pod-RSS runner
  services.github-runners.vod2pod-rss = {
    enable = true;
    url = "https://github.com/gerrydoro/vod2pod-rss";
    tokenFile = "/run/secrets/github-runner-token-vod2pod";
    name = "vod2pod-rss-runner";
    extraLabels = [ 
      "nixos" 
      "self-hosted" 
      "vod2pod"
      "rust"
    ];
    user = "github-runner-vod2pod";
    group = "github-runner-vod2pod";
    workDir = "/var/lib/github-runners";
    extraPackages = with pkgs; [
      # Rust toolchain
      cargo
      rustc
      rustfmt
      clippy
      # Build tools
      pkg-config
      openssl
      # Testing
      jq
      # Container support
      docker
      docker-compose
    ];
  };
  
  # Create dedicated user for VoD2Pod runner
  users.users.github-runner-vod2pod = {
    isSystemUser = true;
    group = "github-runner-vod2pod";
    extraGroups = [ "docker" ];
    shell = pkgs.bash;
  };
  
  users.groups.github-runner-vod2pod = {};
  
  # Enable Docker for CI/CD workflows
  virtualisation.docker.enable = true;
  virtualisation.docker.autoPrune.enable = true;
  
  # Optional: Store token with SOPS (more secure)
  # Uncomment if you use sops-nix
  # sops.secrets.github-runner-token-vod2pod = {
  #   owner = "github-runner-vod2pod";
  #   group = "github-runner-vod2pod";
  # };
  
  # Firewall rules for GitHub Actions
  # GitHub runners need outbound access to GitHub's API
  networking.firewall.allowedTCPOutbound = [ 80 443 ];
  
  # Example: Add more runners in the future
  # services.github-runners.scopone = {
  #   enable = true;
  #   url = "https://github.com/gerrydoro/scopone-ng";
  #   tokenFile = "/run/secrets/github-runner-token-scopone";
  #   name = "scopone-runner";
  #   extraLabels = [ "nixos" "self-hosted" "scopone" "typescript" ];
  #   user = "github-runner-scopone";
  #   group = "github-runner-scopone";
  #   extraPackages = with pkgs; [
  #     nodejs
  #     npm
  #     yarn
  #   ];
  # };
  #
  # users.users.github-runner-scopone = {
  #   isSystemUser = true;
  #   group = "github-runner-scopone";
  # };
  #
  # users.groups.github-runner-scopone = {};
}
