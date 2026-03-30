# GitHub Actions Self-Hosted Runners on NixOS

This guide explains how to set up GitHub Actions self-hosted runners on NixOS with a flexible configuration that supports multiple runners for different repositories.

## Overview

GitHub self-hosted runners allow you to run GitHub Actions workflows on your own infrastructure. This is useful for:
- Faster build times (no queue waiting)
- Access to local resources (Docker, specific hardware, etc.)
- Better control over the build environment
- Cost savings for private repositories

## Architecture

We'll set up runners using a modular approach:
- **Organization-level runners**: Available to all repos in an organization
- **Repository-level runners**: Specific to a single repository
- **Label-based routing**: Use labels to route workflows to appropriate runners

## Prerequisites

1. A GitHub account with admin access to the repository/organization
2. NixOS with flakes enabled
3. Sufficient system resources (CPU, RAM, disk space)

## Step 1: Create the NixOS Configuration

### Option A: Using the GitHub Runner Module (Recommended)

NixOS has a built-in module for GitHub runners. Create a configuration file:

```nix
# /etc/nixos/github-runners.nix
{ config, pkgs, lib, ... }:

{
  # Enable GitHub Actions runner for VoD2Pod-RSS
  services.github-runners.vod2pod-rss = {
    enable = true;
    # Repository or organization URL
    url = "https://github.com/gerrydoro/vod2pod-rss";
    # Token obtained from GitHub (see Step 2)
    tokenFile = config.sops.secrets.github-runner-token-vod2pod.path;
    # Runner name (must be unique)
    name = "vod2pod-rss-runner";
    # Labels for workflow routing
    extraLabels = [ "nixos" "self-hosted" "vod2pod" ];
    # User to run the runner as
    user = "github-runner";
    # Group
    group = "github-runner";
    # Extra packages available to workflows
    extraPackages = with pkgs; [
      nix
      git
      cargo
      rustc
      rustfmt
      clippy
      docker
      docker-compose
    ];
  };

  # Create user and group for GitHub runners
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    extraGroups = [ "docker" "wheel" ];
  };

  users.groups.github-runner = {};

  # Enable Docker (often needed for CI/CD)
  virtualisation.docker.enable = true;

  # Optional: SOPS for secret management
  sops.secrets.github-runner-token-vod2pod = {
    owner = "github-runner";
    group = "github-runner";
  };
}
```

### Option B: Manual Configuration (More Flexible)

For more control, create a custom module:

```nix
# /etc/nixos/modules/github-runner.nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.github-runner;
  
  defaultPackages = with pkgs; [
    git
    bash
    coreutils
    gnugrep
    gnused
  ];
in
{
  options.services.github-runner = {
    instances = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "GitHub runner instance";
          
          url = mkOption {
            type = types.str;
            description = "GitHub repository or organization URL";
          };
          
          tokenFile = mkOption {
            type = types.path;
            description = "Path to file containing registration token";
          };
          
          name = mkOption {
            type = types.str;
            description = "Runner name";
          };
          
          labels = mkOption {
            type = types.listOf types.str;
            default = [ "self-hosted" "nixos" ];
            description = "Runner labels";
          };
          
          user = mkOption {
            type = types.str;
            default = "github-runner";
            description = "User to run runner as";
          };
          
          extraPackages = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Extra packages for CI/CD";
          };
          
          workDir = mkOption {
            type = types.path;
            default = "/var/lib/github-runners";
            description = "Working directory for runner";
          };
        };
      });
      default = {};
      description = "GitHub runner instances";
    };
  };

  config = mkIf (cfg.instances != {}) {
    # Create runner user
    users.users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
    };
    
    users.groups.github-runner = {};
    
    # Create one systemd service per instance
    systemd.services = mapAttrs' (name: instance: 
      nameValuePair "github-runner-${name}" {
        description = "GitHub Actions Runner: ${instance.name}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        
        serviceConfig = {
          Type = "simple";
          User = instance.user;
          Group = "github-runner";
          WorkingDirectory = "${instance.workDir}/${name}";
          ExecStart = "${instance.workDir}/${name}/run.sh";
          Restart = "always";
          RestartSec = "10s";
        };
        
        # Setup runner on first start
        preStart = ''
          if [ ! -f "${instance.workDir}/${name}/.runner" ]; then
            mkdir -p ${instance.workDir}/${name}
            cd ${instance.workDir}/${name}
            cp ${pkgs.github-runner}/actions-runner.tar.gz .
            tar xzf actions-runner.tar.gz
            ./config.sh --unattended \
              --url ${instance.url} \
              --token $(cat ${instance.tokenFile}) \
              --name ${instance.name} \
              --labels ${concatStringsSep "," instance.labels} \
              --work ${instance.workDir}/${name}/_work
          fi
        '';
      }
    ) cfg.instances;
    
    # Environment with all packages
    environment.systemPackages = flatten (mapAttrsToList (_: inst: inst.extraPackages) cfg.instances);
  };
}
```

Then use it in your configuration:

```nix
# /etc/nixos/configuration.nix
{
  imports = [ ./modules/github-runner.nix ];
  
  services.github-runner.instances = {
    vod2pod-rss = {
      enable = true;
      url = "https://github.com/gerrydoro/vod2pod-rss";
      tokenFile = "/run/secrets/github-runner-token-vod2pod";
      name = "vod2pod-rss-runner";
      labels = [ "nixos" "self-hosted" "vod2pod" ];
      extraPackages = with pkgs; [
        cargo
        rustc
        docker
      ];
    };
    
    # Add more runners in the future:
    # my-other-repo = {
    #   enable = true;
    #   url = "https://github.com/gerrydoro/my-other-repo";
    #   tokenFile = "/run/secrets/github-runner-token-other";
    #   name = "other-repo-runner";
    #   labels = [ "nixos" "self-hosted" "other" ];
    # };
  };
}
```

## Step 2: Get Registration Token from GitHub

### For Repository Runner

1. Go to your repository on GitHub
2. Click **Settings** → **Actions** → **Runners**
3. Click **New self-hosted runner**
4. Select your OS (Linux) and architecture (x64)
5. Copy the registration token (valid for 1 hour)

### For Organization Runner

1. Go to your organization on GitHub
2. Click **Settings** → **Actions** → **Runners**
3. Click **New self-hosted runner**
4. Select your OS and architecture
5. Copy the registration token

### Store the Token Securely

**Option A: Using SOPS (Recommended)**

```bash
# Install sops if not already installed
nix-env -iA nixos.sops

# Create encrypted secret
echo "YOUR_TOKEN_HERE" | sops --encrypt --stdin > /etc/nixos/secrets/github-runner-token-vod2pod.age

# Add to secrets.yaml
cat >> /etc/nixos/secrets.yaml << EOF
github-runner-token-vod2pod: age:<your-age-key>
EOF
```

**Option B: Simple File (Less Secure)**

```bash
sudo mkdir -p /run/secrets
echo "YOUR_TOKEN_HERE" | sudo tee /run/secrets/github-runner-token-vod2pod
sudo chmod 600 /run/secrets/github-runner-token-vod2pod
```

## Step 3: Build and Activate the Configuration

```bash
# Test the configuration
sudo nixos-rebuild build --flake /etc/nixos#ASUS

# Apply the configuration
sudo nixos-rebuild switch --flake /etc/nixos#ASUS

# Check runner status
systemctl status github-runner-vod2pod-rss
```

## Step 4: Configure GitHub Actions Workflow

Update your workflow to use the self-hosted runner:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: [ self-hosted, nixos, vod2pod ]
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install Nix
      uses: cachix/install-nix-action@v25
    
    - name: Build
      run: nix build .#vod2pod-rss
    
    - name: Test
      run: nix flake check
```

## Managing Multiple Runners

### Adding a New Runner

1. Add new instance to configuration:

```nix
services.github-runner.instances = {
  vod2pod-rss = { ... };  # Existing runner
  
  # New runner
  scopone = {
    enable = true;
    url = "https://github.com/gerrydoro/scopone-ng";
    tokenFile = "/run/secrets/github-runner-token-scopone";
    name = "scopone-runner";
    labels = [ "nixos" "self-hosted" "scopone" ];
    extraPackages = with pkgs; [
      nodejs
      npm
    ];
  };
};
```

2. Get new token from GitHub
3. Store token securely
4. Rebuild configuration: `sudo nixos-rebuild switch`

### Runner Labels

Use labels to route workflows to specific runners:

```yaml
# Run on VoD2Pod runner
runs-on: [ self-hosted, nixos, vod2pod ]

# Run on Scopone runner
runs-on: [ self-hosted, nixos, scopone ]

# Run on any NixOS runner
runs-on: [ self-hosted, nixos ]
```

## Monitoring and Maintenance

### Check Runner Status

```bash
# Systemd status
systemctl status github-runner-vod2pod-rss

# Logs
journalctl -u github-runner-vod2pod-rss -f

# GitHub UI: Settings → Actions → Runners
```

### Update Runner Software

```bash
# Runners auto-update when GitHub releases new versions
# To manually update, restart the service:
sudo systemctl restart github-runner-vod2pod-rss
```

### Rotate Tokens

Registration tokens expire after 1 hour, but runner tokens (once registered) don't expire. To rotate:

1. Generate new token in GitHub UI
2. Update secret file
3. Restart runner service

### Resource Monitoring

```bash
# Check disk usage
du -sh /var/lib/github-runners/*

# Check memory usage
systemctl status github-runner-*

# Check CPU usage
htop
```

## Security Considerations

1. **Isolate runners**: Use separate users for different runners
2. **Limit permissions**: Don't give runners unnecessary access
3. **Use labels**: Restrict which workflows can use which runners
4. **Monitor logs**: Watch for suspicious activity
5. **Regular updates**: Keep NixOS and runner software updated
6. **Network isolation**: Consider firewall rules for runners

### Required Firewall Rules

```nix
# /etc/nixos/firewall.nix
networking.firewall = {
  enable = true;
  allowedTCPOutbound = [ 80 443 ];  # GitHub API
  allowedUDPOutbound = [ 53 ];       # DNS
};
```

## Troubleshooting

### Runner Not Connecting

1. Check token validity
2. Verify network connectivity to GitHub
3. Check firewall rules
4. Review logs: `journalctl -u github-runner-* -f`

### Workflows Not Running

1. Verify labels match workflow `runs-on`
2. Check runner is online in GitHub UI
3. Review workflow syntax

### Resource Issues

1. Clean old work directories: `/var/lib/github-runners/*/`
2. Increase system resources
3. Limit concurrent jobs in workflow

## Complete Example Configuration

```nix
# /etc/nixos/github-runners.nix
{ config, pkgs, ... }:

{
  # Enable GitHub Actions runners
  services.github-runners = {
    vod2pod-rss = {
      enable = true;
      url = "https://github.com/gerrydoro/vod2pod-rss";
      tokenFile = config.sops.secrets.github-runner-vod2pod.path;
      name = "vod2pod-rss-runner";
      extraLabels = [ "nixos" "self-hosted" "vod2pod" ];
      user = "github-runner-vod2pod";
      group = "github-runner";
      extraPackages = with pkgs; [
        nix
        git
        cargo
        rustc
        rustfmt
        clippy
        docker
        docker-compose
      ];
    };
  };

  # Create users
  users.users.github-runner-vod2pod = {
    isSystemUser = true;
    group = "github-runner";
    extraGroups = [ "docker" ];
  };

  users.groups.github-runner = {};

  # Enable Docker
  virtualisation.docker.enable = true;

  # Secrets
  sops.secrets.github-runner-vod2pod = {
    owner = "github-runner-vod2pod";
    group = "github-runner";
  };
}
```

## Additional Resources

- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [NixOS GitHub Runner Module](https://search.nixos.org/options?show=services.github-runners)
- [Self-Hosted Runner Security](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#self-hosted-runner-security)
