#!/bin/bash
# Quick Setup Script for GitHub Actions Runner on NixOS
# 
# This script helps you set up a GitHub Actions self-hosted runner
# for the VoD2Pod-RSS repository on your NixOS machine.
#
# Usage: ./setup-github-runner.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GitHub Actions Runner Setup for NixOS ===${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Please run as root (use sudo)${NC}"
  exit 1
fi

# Configuration
REPO_URL="https://github.com/gerrydoro/vod2pod-rss"
RUNNER_NAME="vod2pod-rss-runner"
TOKEN_FILE="/run/secrets/github-runner-token-vod2pod"
CONFIG_FILE="/etc/nixos/github-runner-config.nix"
MODULE_FILE="/etc/nixos/nixos-github-runners.nix"

echo -e "${YELLOW}Step 1: Copy configuration files${NC}"
cp "$(dirname "$0")/nixos-github-runners.nix" "$MODULE_FILE"
cp "$(dirname "$0")/github-runner-config.nix" "$CONFIG_FILE"
echo -e "${GREEN}✓ Configuration files copied${NC}"
echo

echo -e "${YELLOW}Step 2: Get GitHub Registration Token${NC}"
echo "Please follow these steps:"
echo "1. Go to: $REPO_URL/settings/actions/runners"
echo "2. Click 'New self-hosted runner'"
echo "3. Select Linux and x64"
echo "4. Copy the registration token"
echo

read -p "Paste your registration token here: " -s TOKEN
echo
echo

if [ -z "$TOKEN" ]; then
  echo -e "${RED}Error: Token cannot be empty${NC}"
  exit 1
fi

# Store token securely
mkdir -p /run/secrets
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
echo -e "${GREEN}✓ Token stored securely${NC}"
echo

echo -e "${YELLOW}Step 3: Check NixOS configuration${NC}"
echo "The following files need to be imported in your NixOS configuration:"
echo "  - $MODULE_FILE"
echo "  - $CONFIG_FILE"
echo
echo -e "${YELLOW}Choose how to import:${NC}"
echo "1. Add to /etc/nixos/configuration.nix (traditional)"
echo "2. Add to /etc/nixos/flake.nix (flakes)"
echo "3. I'll do it manually"
echo
read -p "Choose option (1/2/3): " IMPORT_OPTION

case $IMPORT_OPTION in
  1)
    echo -e "${YELLOW}Adding to configuration.nix...${NC}"
    if ! grep -q "github-runner-config.nix" /etc/nixos/configuration.nix; then
      echo "imports = [ ./github-runner-config.nix ];" >> /etc/nixos/configuration.nix
      echo -e "${GREEN}✓ Added to configuration.nix${NC}"
    else
      echo -e "${GREEN}✓ Already in configuration.nix${NC}"
    fi
    ;;
  2)
    echo -e "${YELLOW}Please add the following to your flake.nix imports:${NC}"
    echo "  imports = [ ./github-runner-config.nix ];"
    echo
    read -p "Press Enter after you've added it..."
    ;;
  3)
    echo -e "${YELLOW}Manual configuration selected${NC}"
    echo "Make sure to import ./github-runner-config.nix in your NixOS configuration"
    ;;
  *)
    echo -e "${RED}Invalid option${NC}"
    exit 1
    ;;
esac

echo

echo -e "${YELLOW}Step 4: Build and activate configuration${NC}"
echo "This will download and configure the GitHub Actions runner"
echo
read -p "Continue with build? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Build cancelled. Run 'sudo nixos-rebuild switch' manually later.${NC}"
  exit 0
fi

echo -e "${GREEN}Building NixOS configuration...${NC}"
if [ -f /etc/nixos/flake.nix ]; then
  sudo nixos-rebuild switch --flake /etc/nixos#ASUS
else
  sudo nixos-rebuild switch
fi

echo
echo -e "${GREEN}✓ Build complete!${NC}"
echo

echo -e "${YELLOW}Step 5: Verify runner status${NC}"
sleep 5
systemctl status github-runner-vod2pod-rss --no-pager || true
echo

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo
echo "Your GitHub Actions runner should now be:"
echo "  - Registered with GitHub"
echo "  - Running as a systemd service"
echo "  - Available for workflows with 'runs-on: [self-hosted, nixos, vod2pod]'"
echo
echo "Useful commands:"
echo "  - Check status: systemctl status github-runner-vod2pod-rss"
echo "  - View logs: journalctl -u github-runner-vod2pod-rss -f"
echo "  - Restart: sudo systemctl restart github-runner-vod2pod-rss"
echo "  - Stop: sudo systemctl stop github-runner-vod2pod-rss"
echo
echo "To add more runners in the future:"
echo "  1. Edit $CONFIG_FILE"
echo "  2. Uncomment and configure additional runners"
echo "  3. Run: sudo nixos-rebuild switch"
echo
echo "For more information, see: GITHUB_RUNNERS_NIXOS.md"
