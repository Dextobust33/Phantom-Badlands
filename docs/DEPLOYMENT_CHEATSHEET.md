# Phantom Badlands — Deployment Cheat Sheet

## Infrastructure Overview

```
Players → phantombadlands.com (GitHub Pages) → Download Launcher
         ↓
Launcher → GitHub Releases API → Auto-downloads latest client ZIP
         ↓
Client → 129.213.166.185:9080 (Oracle Cloud VM) → Game Server
```

| Component | Where | Cost |
|-----------|-------|------|
| Website | GitHub Pages (`docs/` folder) | Free |
| Domain | phantombadlands.com (Cloudflare) | ~$10/year |
| Game Server | Oracle Cloud VM (129.213.166.185) | Free (Always Free tier) |
| Client Downloads | GitHub Releases | Free |
| Forum | GitHub Discussions | Free |
| Source Code | github.com/Dextobust33/Phantom-Badlands | Free |

---

## Quick Reference — Common Tasks

### Update the game (client + server)

```bash
# 1. Bump version
echo "0.9.XXX" > VERSION.txt

# 2. Commit and push code
git add -A && git commit -m "vX.Y.Z: description" && git push

# 3. Export client
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands" "builds/PhantomBadlandsClient.exe"

# 4. Create ZIPs (BOTH required in every release)
cp VERSION.txt builds/VERSION.txt
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsClient.exe', 'builds/PhantomBadlandsClient.pck', 'builds/libgdsqlite.windows.template_debug.x86_64.dll', 'builds/VERSION.txt' -DestinationPath 'releases/phantom-badlands-client-vX.Y.Z.zip' -Force"
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsLauncher.exe' -DestinationPath 'releases/phantom-badlands-launcher.zip' -Force"

# 5. Create GitHub release
"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y.Z releases/phantom-badlands-client-vX.Y.Z.zip releases/phantom-badlands-launcher.zip --title "vX.Y.Z" --notes "Description"

# 6. Deploy server (if server-side changes)
bash deploy_server.sh
```

### Update ONLY the server (no client changes)

```bash
bash deploy_server.sh
```

Or manually:
```bash
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"

# Export Linux server
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands-Server-Linux" "builds/server/PhantomBadlandsServer.x86_64"

# Upload and restart
scp -i "$SSH_KEY" builds/server/PhantomBadlandsServer.x86_64 ubuntu@129.213.166.185:~/phantom-badlands/
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "chmod +x ~/phantom-badlands/PhantomBadlandsServer.x86_64 && sudo systemctl restart phantom-badlands"
```

### Update ONLY the website

Just edit files in `docs/` (index.html, features.html, download.html, faq.html, style.css), commit, and push. GitHub Pages auto-deploys within 1-2 minutes.

```bash
git add docs/ && git commit -m "Update website" && git push
```

---

## Server Management

```bash
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"

# SSH into server
ssh -i "$SSH_KEY" ubuntu@129.213.166.185

# Check if server is running
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo systemctl status phantom-badlands --no-pager"

# View recent logs (last 50 lines)
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo journalctl -u phantom-badlands -n 50 --no-pager"

# View live logs (stream)
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo journalctl -u phantom-badlands -f"

# Restart server
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo systemctl restart phantom-badlands"

# Stop server
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo systemctl stop phantom-badlands"

# Start server
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "sudo systemctl start phantom-badlands"

# Check RAM/CPU usage
ssh -i "$SSH_KEY" ubuntu@129.213.166.185 "free -h && top -bn1 | head -5"
```

---

## Important Files on the Server

| Path | Purpose |
|------|---------|
| `~/phantom-badlands/PhantomBadlandsServer.x86_64` | Game server binary (replace to update) |
| `~/phantom-badlands/override.cfg` | Sets main scene to server.tscn |
| `~/phantom-badlands/libgdsqlite.linux.template_release.x86_64.so` | SQLite library |
| `/etc/systemd/system/phantom-badlands.service` | Systemd service (auto-restart) |
| `~/.local/share/godot/` | Godot user data (accounts, saves) |

---

## Important Files Locally

| Path | Purpose |
|------|---------|
| `VERSION.txt` | Current version (must bump for every release) |
| `export_presets.cfg` | Godot export presets (client + server) |
| `deploy_server.sh` | One-command server deploy script |
| `server_override.cfg` | Override config uploaded to server |
| `docs/` | Website files (GitHub Pages) |
| `docs/CNAME` | Domain mapping (don't delete!) |
| `builds/PhantomBadlandsLauncher.exe` | Launcher binary (include in every release) |

---

## Key Credentials & Access

| What | Where |
|------|-------|
| SSH Private Key | `C:\Users\Dexto\Desktop\PhantomBadlandsSSH\ssh-key-2026-04-21.key` |
| Oracle Cloud Console | cloud.oracle.com |
| Cloudflare (domain) | dash.cloudflare.com |
| GitHub Repo | github.com/Dextobust33/Phantom-Badlands |
| Server IP | 129.213.166.185 |
| Server Port | 9080 |
| Server User | ubuntu |

---

## Reminders

- **ALWAYS include launcher ZIP** in every GitHub release — the website download link points to `releases/latest/download/phantom-badlands-launcher.zip`
- **NEVER reuse a version number** — the launcher compares versions to decide whether to update
- **Server auto-restarts** on crash (systemd). If it keeps crashing, check logs.
- **Website auto-deploys** when you push changes to `docs/` on master
- **Domain renews annually** (~$10) on Cloudflare — watch for renewal emails
- **Oracle Cloud** is free tier — don't upgrade the VM shape or you'll get charged
- **SSH key** is the only way to access the server — don't lose it!
- After server-side code changes, you must run `deploy_server.sh` — client releases alone don't update the server
