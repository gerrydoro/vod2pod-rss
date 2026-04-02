# Automated Dependency Updates for VoD2Pod-RSS

This document explains how to set up automated dependency updates for the VoD2Pod-RSS project to ensure all components stay up-to-date, especially critical components like `yt-dlp`.

## Overview

VoD2Pod-RSS uses multiple dependency types:
- **Rust dependencies** (Cargo.toml)
- **Python dependencies** (requirements.txt) - primarily yt-dlp
- **Nix flake inputs** (flake.nix)
- **Docker base images** (Dockerfile)
- **GitHub Actions** (if used)

## Solution 1: GitHub Dependabot (Recommended)

Dependabot is GitHub's built-in automated dependency update tool. It's free for public repositories and integrates seamlessly with GitHub's pull request system.

### Setup Instructions

1. **Create the Dependabot configuration file**

   Create a file at `.github/dependabot.yml` with the following content:

   ```yaml
   version: 2
   updates:
     # Rust dependencies (Cargo.toml)
     - package-ecosystem: "cargo"
       directory: "/"
       schedule:
         interval: "weekly"
         day: "monday"
         time: "09:00"
         timezone: "UTC"
       open-pull-requests-limit: 10
       labels:
         - "dependencies"
         - "rust"
       commit-message:
         prefix: "deps"
       groups:
         rust-minor:
           patterns:
             - "*"
           update-types:
             - "minor"
             - "patch"
     
     # Python dependencies (requirements.txt) - includes yt-dlp
     - package-ecosystem: "pip"
       directory: "/"
       schedule:
         interval: "daily"
         time: "09:00"
         timezone: "UTC"
       open-pull-requests-limit: 5
       labels:
         - "dependencies"
         - "python"
       commit-message:
         prefix: "deps"
     
     # GitHub Actions
     - package-ecosystem: "github-actions"
       directory: "/"
       schedule:
         interval: "weekly"
         day: "monday"
         time: "09:00"
         timezone: "UTC"
       open-pull-requests-limit: 5
       labels:
         - "dependencies"
         - "github-actions"
       commit-message:
         prefix: "ci"
     
     # Docker (for base image updates)
     - package-ecosystem: "docker"
       directory: "/"
       schedule:
         interval: "weekly"
         day: "monday"
         time: "09:00"
         timezone: "UTC"
       open-pull-requests-limit: 3
       labels:
         - "dependencies"
         - "docker"
       commit-message:
         prefix: "docker"
   ```

2. **Enable Dependabot**

   - Go to your repository on GitHub
   - Click on **Settings** → **Code security and analysis**
   - Find **Dependabot alerts** and **Dependabot security updates**
   - Click **Enable** for both options

3. **Verify Configuration**

   - Dependabot will automatically detect the configuration file
   - Within 24 hours, you should see the first dependency check run
   - Pull requests will be created automatically for outdated dependencies

### Benefits

- ✅ Automatic security updates
- ✅ Version update PRs with changelinks
- ✅ Automatic CI/CD integration
- ✅ Grouped updates to reduce PR noise
- ✅ Free for public repositories

### Customization Options

#### Update Frequency

```yaml
schedule:
  interval: "daily"     # Options: daily, weekly, monthly
  time: "09:00"
  timezone: "UTC"
```

#### Limit Number of PRs

```yaml
open-pull-requests-limit: 10  # Maximum open PRs at once
```

#### Group Updates

Reduce PR noise by grouping similar updates:

```yaml
groups:
  rust-dependencies:
    patterns:
      - "*"
    update-types:
      - "minor"
      - "patch"
```

#### Ignore Specific Dependencies

```yaml
ignore:
  - dependency-name: "some-crate"
    versions: ["1.x.x", "2.x.x"]
```

#### Assign Reviewers

```yaml
assignees:
  - "gerrydoro"
reviewers:
  - "gerrydoro"
```

## Solution 2: Renovate Bot (Alternative)

Renovate is a more flexible alternative to Dependabot with additional features.

### Setup Instructions

1. **Install Renovate Bot**

   - Go to https://github.com/apps/renovate
   - Click **Configure**
   - Select your repository

2. **Create Renovate Configuration**

   Create `renovate.json` in the root directory:

   ```json
   {
     "$schema": "https://docs.renovatebot.com/renovate-schema.json",
     "extends": [
       "config:recommended"
     ],
     "schedule": ["before 3am on Monday"],
     "packageRules": [
       {
         "matchManagers": ["cargo"],
         "groupName": "Rust dependencies",
         "groupSlug": "rust"
       },
       {
         "matchManagers": ["pip_requirements"],
         "groupName": "Python dependencies",
         "groupSlug": "python",
         "schedule": ["every weekday"]
       },
       {
         "matchPackageNames": ["yt-dlp"],
         "schedule": ["at any time"],
         "automerge": true,
         "automergeType": "pr"
       }
     ],
     "labels": ["dependencies"],
     "commitMessagePrefix": "deps:"
   }
   ```

### Benefits over Dependabot

- ✅ More configuration options
- ✅ Auto-merge support
- ✅ Better monorepo support
- ✅ Custom scheduling per package
- ✅ Works with private repositories (with limitations)

## Special Consideration: yt-dlp

Since `yt-dlp` is critical for VoD2Pod-RSS functionality and updates frequently (often weekly), consider these options:

### Option 1: Daily Updates (Recommended)

```yaml
# In dependabot.yml
- package-ecosystem: "pip"
  directory: "/"
  schedule:
    interval: "daily"
    time: "06:00"
  open-pull-requests-limit: 3
  target-branch: "main"
```

### Option 2: GitHub Actions for Auto-Merge

Create `.github/workflows/auto-merge-ytdlp.yml`:

```yaml
name: Auto-merge yt-dlp updates

on:
  pull_request:
    paths:
      - "requirements.txt"

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    runs-on: [ self-hosted, nixos, vod2pod ]
    if: github.actor == 'dependabot[bot]'
    steps:
      - name: Check if yt-dlp update
        id: check
        run: |
          if git diff --name-only ${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }} | grep -q "requirements.txt"; then
            if git diff ${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }} -- requirements.txt | grep -q "yt-dlp"; then
              echo "is_ytdlp=true" >> $GITHUB_OUTPUT
            fi
          fi
      
      - name: Enable auto-merge for yt-dlp
        if: steps.check.outputs.is_ytdlp == 'true'
        run: |
          gh pr merge --auto --squash "${{ github.event.pull_request.number }}"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Option 3: Direct Update Script

Create a script `.github/scripts/update-ytdlp.sh`:

```bash
#!/bin/bash
set -e

# Get latest yt-dlp version
LATEST_VERSION=$(curl -s https://pypi.org/pypi/yt-dlp/json | jq -r '.info.version')
CURRENT_VERSION=$(grep "yt-dlp==" requirements.txt | cut -d'=' -f3)

if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
  echo "Updating yt-dlp from $CURRENT_VERSION to $LATEST_VERSION"
  sed -i "s/yt-dlp==.*/yt-dlp==$LATEST_VERSION/" requirements.txt
  
  # Create commit
  git config --local user.email "action@github.com"
  git config --local user.name "GitHub Action"
  git add requirements.txt
  git commit -m "deps: Update yt-dlp to $LATEST_VERSION"
  git push
fi
```

Then create a workflow `.github/workflows/update-ytdlp.yml`:

```yaml
name: Update yt-dlp

on:
  schedule:
    - cron: "0 6 * * *"  # Daily at 6 AM UTC
  workflow_dispatch:  # Allow manual trigger

jobs:
  update:
    runs-on: [ self-hosted, nixos, vod2pod ]
    steps:
      - uses: actions/checkout@v4
      
      - name: Update yt-dlp
        run: |
          chmod +x .github/scripts/update-ytdlp.sh
          .github/scripts/update-ytdlp.sh
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Nix Flake Updates

For Nix flake inputs, you can use:

### Option 1: Manual Update Script

Create `scripts/update-flake.sh`:

```bash
#!/bin/bash
nix flake update
git add flake.lock
git commit -m "chore: Update flake inputs"
git push
```

### Option 2: Scheduled GitHub Action

```yaml
name: Update Nix flake inputs

on:
  schedule:
    - cron: "0 7 * * 1"  # Weekly on Monday at 7 AM UTC
  workflow_dispatch:

jobs:
  update:
    runs-on: [ self-hosted, nixos, vod2pod ]
    steps:
      - uses: actions/checkout@v4
      
      - uses: cachix/install-nix-action@v25
      
      - name: Update flake inputs
        run: |
          nix flake update
          git config --local user.email "action@github.com"
          git config --local user.name "GitHub Action"
          git add flake.lock
          git commit -m "chore: Update flake inputs" || echo "No changes to commit"
          git push
```

## Best Practices

1. **Review Updates Regularly**: Check dependency update PRs at least weekly
2. **Test Before Merging**: Ensure CI/CD passes before merging updates
3. **Group Minor Updates**: Group minor and patch updates to reduce noise
4. **Pin Critical Versions**: Pin versions for critical dependencies if needed
5. **Monitor Security Alerts**: Enable Dependabot security alerts
6. **Update Nix Cache**: After updating dependencies, rebuild the Nix cache

## Recommended Configuration for VoD2Pod-RSS

For VoD2Pod-RSS, I recommend:

1. **Dependabot** for most dependencies (simpler, built-in)
2. **Daily updates for yt-dlp** (critical for functionality)
3. **Weekly updates for Rust dependencies** (more stable)
4. **Auto-merge for patch updates** (low risk)
5. **Manual review for major updates** (breaking changes possible)

## Troubleshooting

### Dependabot Not Creating PRs

- Check `.github/dependabot.yml` syntax
- Verify Dependabot is enabled in repository settings
- Check if `open-pull-requests-limit` is too low
- Review Dependabot logs in **Insights** → **Dependency graph** → **Dependabot**

### Too Many PRs

- Increase grouping in configuration
- Reduce `open-pull-requests-limit`
- Change schedule to less frequent updates
- Add ignore rules for non-critical dependencies

### yt-dlp Updates Breaking Changes

- Pin to specific version range if needed
- Add tests for yt-dlp functionality
- Review yt-dlp changelog before merging major updates

## Additional Resources

- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [Dependabot Configuration Options](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [Renovate Bot Documentation](https://docs.renovatebot.com/)
- [yt-dlp Releases](https://github.com/yt-dlp/yt-dlp/releases)
