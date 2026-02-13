# Auto-Update System Setup

This guide explains how to set up the auto-updating launcher for Phantom Badlands.

## Overview

The system consists of:
1. **Launcher** - A small app that checks for updates and downloads them
2. **GitHub Releases** - Where you upload new client versions
3. **VERSION.txt** - Tracks the current version

## Initial Setup

### 1. Create a GitHub Repository

1. Go to [github.com](https://github.com) and create a new repository
2. Name it `phantom-badlands` (or your preferred name)
3. Make it **public** (required for unauthenticated API access)

### 2. Connect Your Local Repository

```bash
cd "C:\Users\Dexto\Documents\phantasia-revival"
git remote add origin https://github.com/YOUR_USERNAME/phantom-badlands.git
git push -u origin master
```

### 3. Configure the Launcher

Edit `launcher/launcher.gd` and update these lines:
```gdscript
const GITHUB_OWNER = "YOUR_GITHUB_USERNAME"  # Your GitHub username
const GITHUB_REPO = "phantom-badlands"       # Your repo name
```

### 4. Export the Launcher

1. Open `launcher/project.godot` in Godot
2. Go to Project → Export
3. Add "Windows Desktop" preset
4. Export to `launcher/builds/PhantomBadlandsLauncher.exe`
5. This launcher rarely needs updating - share it once with friends

## Creating a Release

### Quick Method (Manual)

1. Update `VERSION.txt` with new version (e.g., `1.0.1`)
2. Export the client in Godot (Project → Export → Windows Desktop)
3. Create a ZIP containing:
   - `phantom-badlands-client.exe`
   - `phantom-badlands-client.pck`
   - `VERSION.txt`
4. Name the ZIP: `phantom-badlands-client-v1.0.1.zip`
5. Go to GitHub → Releases → Create new release
6. Set tag: `v1.0.1` (or just `1.0.1`)
7. Upload the ZIP file
8. Publish

### Script Method

Run the PowerShell script:
```powershell
.\scripts\create_release.ps1 -Version "1.0.1"
```

This will:
- Update VERSION.txt
- Export the client
- Create the ZIP package
- Tell you what to upload to GitHub

## How It Works

1. User runs `PhantomBadlandsLauncher.exe`
2. Launcher checks GitHub API: `api.github.com/repos/OWNER/REPO/releases/latest`
3. Compares release tag with local `VERSION.txt`
4. If newer version exists:
   - Downloads the ZIP from GitHub
   - Extracts to the same folder
   - Updates local VERSION.txt
5. Launches `PhantomBadlandsClient.exe`

## Directory Structure for Friends

Friends should have a folder like:
```
PhantomBadlands/
├── PhantomBadlandsLauncher.exe    <- They run this
├── PhantomBadlandsClient.exe      <- Downloaded automatically
├── PhantomBadlandsClient.pck      <- Downloaded automatically
└── VERSION.txt                    <- Downloaded automatically
```

## Troubleshooting

### "Could not reach update server"
- Check internet connection
- Verify GitHub repo is public
- Check GITHUB_OWNER and GITHUB_REPO are correct

### "No download found in release"
- Make sure your ZIP filename contains "client" and ends with ".zip"
- Example: `phantom-badlands-client-v1.0.0.zip`

### Windows Security Warning
See the section below about code signing.

## About Windows Security Warnings

Windows SmartScreen warns about unsigned executables. Options:

1. **Tell friends to bypass**: Click "More info" → "Run anyway"
2. **Add to antivirus exceptions**: Right-click → Properties → Unblock
3. **Code signing certificate** (~$200-500/year): Eliminates warnings entirely
4. **Build reputation**: After many users run it, warnings decrease

For a small group of friends, option 1 is usually fine.
