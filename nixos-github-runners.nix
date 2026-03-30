# GitHub Actions Self-Hosted Runners Configuration for NixOS
# 
# This module provides a flexible setup for running multiple GitHub Actions runners
# on a single NixOS machine, with support for different repositories and configurations.
#
# Usage:
#   1. Import this module in your configuration.nix or flake.nix
#   2. Configure runners in services.github-runners
#   3. Get registration tokens from GitHub
#   4. Rebuild your system
#
# Example:
#   services.github-runners = {
#     vod2pod-rss = {
#       enable = true;
#       url = "https://github.com/gerrydoro/vod2pod-rss";
#       tokenFile = "/run/secrets/github-runner-token-vod2pod";
#       name = "vod2pod-rss-runner";
#       extraLabels = [ "nixos" "self-hosted" "vod2pod" ];
#     };
#   };

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.github-runners;
  
  # Default packages available to all runners
  defaultPackages = with pkgs; [
    git
    bash
    coreutils
    gnugrep
    gnused
    curl
    jq
    nix
  ];
  
  # Create a runner configuration
  createRunnerService = name: runnerCfg: {
    description = "GitHub Actions Runner: ${runnerCfg.name}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = runnerCfg.user;
      Group = runnerCfg.group;
      WorkingDirectory = "${runnerCfg.workDir}/${name}";
      ExecStart = "${runnerCfg.workDir}/${name}/run.sh";
      Restart = "always";
      RestartSec = "10s";
      # Security hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      # Allow write access to work directory
      ReadWritePaths = [ "${runnerCfg.workDir}/${name}" ];
    };
    
    # Setup runner on first start
    preStart = ''
      RUNNER_DIR="${runnerCfg.workDir}/${name}"
      
      if [ ! -f "$RUNNER_DIR/.runner" ]; then
        echo "Setting up GitHub Actions runner: ${runnerCfg.name}"
        mkdir -p "$RUNNER_DIR"
        cd "$RUNNER_DIR"
        
        # Download latest runner
        RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)
        curl -L -o runner.tar.gz "https://github.com/actions/runner/releases/download/${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION#v}.tar.gz"
        tar xzf runner.tar.gz
        rm runner.tar.gz
        
        # Configure runner
        ./config.sh --unattended \
          --url ${runnerCfg.url} \
          --token $(cat ${runnerCfg.tokenFile}) \
          --name ${runnerCfg.name} \
          --labels ${concatStringsSep "," runnerCfg.extraLabels} \
          --work "$RUNNER_DIR/_work" \
          --ephemeral
      fi
      
      # Ensure correct ownership
      chown -R ${runnerCfg.user}:${runnerCfg.group} "$RUNNER_DIR"
    '';
  };
in
{
  options.services.github-runners = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        enable = mkEnableOption "GitHub Actions runner";
        
        url = mkOption {
          type = types.str;
          description = "GitHub repository or organization URL (e.g., https://github.com/user/repo)";
          example = "https://github.com/gerrydoro/vod2pod-rss";
        };
        
        tokenFile = mkOption {
          type = types.path;
          description = "Path to file containing registration token";
          example = "/run/secrets/github-runner-token";
        };
        
        name = mkOption {
          type = types.str;
          description = "Runner name (must be unique per GitHub account/org)";
          example = "my-runner";
        };
        
        extraLabels = mkOption {
          type = types.listOf types.str;
          default = [ "self-hosted" "nixos" ];
          description = "Additional labels for workflow routing";
          example = [ "nixos" "self-hosted" "vod2pod" ];
        };
        
        user = mkOption {
          type = types.str;
          default = "github-runner";
          description = "System user to run the runner as";
        };
        
        group = mkOption {
          type = types.str;
          default = "github-runner";
          description = "System group for the runner";
        };
        
        workDir = mkOption {
          type = types.path;
          default = "/var/lib/github-runners";
          description = "Base working directory for all runners";
        };
        
        extraPackages = mkOption {
          type = types.listOf types.package;
          default = [];
          description = "Extra packages available to workflows";
          example = literalExpression "[ pkgs.cargo pkgs.rustc pkgs.docker ]";
        };
      };
    });
    default = {};
    description = "GitHub Actions runner instances";
  };

  config = mkIf (cfg != {}) {
    # Create default runner user/group if needed
    users.users.github-runner = mkIf (any (r: r.user == "github-runner") (attrValues cfg)) {
      isSystemUser = true;
      group = "github-runner";
    };
    
    users.groups.github-runner = mkIf (any (r: r.group == "github-runner") (attrValues cfg)) {};
    
    # Create one systemd service per runner instance
    systemd.services = mapAttrs' (name: runnerCfg: 
      nameValuePair "github-runner-${name}" (createRunnerService name runnerCfg)
    ) (filterAttrs (_: runnerCfg: runnerCfg.enable) cfg);
    
    # Add all extra packages to system
    environment.systemPackages = flatten (mapAttrsToList (_: runnerCfg: runnerCfg.extraPackages) cfg);
    
    # Enable Docker if any runner needs it
    virtualisation.docker.enable = any (r: any (pkg: pkg.pname or "" == "docker") r.extraPackages) (attrValues cfg);
  };
}
