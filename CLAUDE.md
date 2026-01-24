# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Task-Based Navigation

| Task | Read First | Then | Reference |
|------|------------|------|-----------|
| Update server | [Deployment](docs/CLAUDE-deployment.md) | — | — |
| Fix startup issue | [Deployment](docs/CLAUDE-deployment.md) | [Configuration](docs/CLAUDE-configuration.md) | — |
| Add mod/plugin | [Mods & Plugins](docs/CLAUDE-mods-plugins.md) | [Configuration](docs/CLAUDE-configuration.md) | — |
| Configure settings | [Configuration](docs/CLAUDE-configuration.md) | — | — |
| Setup monitoring | [Monitoring](docs/CLAUDE-monitoring.md) | [monitoring.md](docs/monitoring.md) | [loki-setup.md](docs/loki-setup.md) |
| Backup/restore | [Deployment](docs/CLAUDE-deployment.md#backup--restore) | — | — |
| Production deploy | [Deployment](docs/CLAUDE-deployment.md#setup--installation) | [Configuration](docs/CLAUDE-configuration.md) | — |

## Quick Answers

**Q: How to update server from Git?**
`./deploy/update.sh` or `./deploy/update.sh --skip-backup` — See [Deployment](docs/CLAUDE-deployment.md#update-scripts)

**Q: How to restart server?**
`sudo systemctl restart minecraft` or `./deploy/stop.sh && ./deploy/start.sh` — See [Deployment](docs/CLAUDE-deployment.md#systemd-commands-production)

**Q: How to add a new mod?**
Place `.jar` in `/mods/`, restart server — See [Mods & Plugins](docs/CLAUDE-mods-plugins.md#adding-new-mods)

**Q: How to add a new plugin?**
Place `.jar` in `/plugins/`, restart server — See [Mods & Plugins](docs/CLAUDE-mods-plugins.md#adding-new-plugins)

**Q: Where is RCON password?**
`server.properties` line 43-44, synced to `deploy/config.env` — See [Configuration](docs/CLAUDE-configuration.md#server-properties)

**Q: How to check server health?**
`./deploy/health-check.sh` — See [Deployment](docs/CLAUDE-deployment.md#health--monitoring)

**Q: How to view logs?**
`sudo journalctl -u minecraft -f` — See [Deployment](docs/CLAUDE-deployment.md#systemd-commands-production)

## Documentation Index

| Category | Document | Description |
|----------|----------|-------------|
| **Operations** | [Deployment](docs/CLAUDE-deployment.md) | update, stop, start, backup, restore |
| **Operations** | [Monitoring](docs/CLAUDE-monitoring.md) | Prometheus, Grafana, Loki |
| **Settings** | [Configuration](docs/CLAUDE-configuration.md) | server.properties, bukkit, spigot, mohist |
| **Content** | [Mods & Plugins](docs/CLAUDE-mods-plugins.md) | Adding and configuring mods/plugins |
| **Reference** | [monitoring.md](docs/monitoring.md) | Detailed Prometheus + Grafana setup |
| **Reference** | [loki-setup.md](docs/loki-setup.md) | Loki installation & troubleshooting |

---

## Project Overview

**KIBERmine** — Mohist 1.20.1 Minecraft server (Forge + Bukkit hybrid).

| Component | Description |
|-----------|-------------|
| **Server JAR** | `mohist-1.20.1-*.jar` (135MB, Git LFS) |
| **Mods** | `/mods/` — 45+ Forge mods (Mekanism, AE2, Alex's Mobs) |
| **Plugins** | `/plugins/` — Bukkit plugins (LuckPerms, TAB, FlectoneChat) |
| **Config** | `/config/` — Mod configs (TOML), `/mohist-config/` — Mohist settings |

---

## Quick Reference

### Systemd Commands (Production)

```bash
sudo systemctl status minecraft      # Check status
sudo systemctl start minecraft       # Start server
sudo systemctl stop minecraft        # Stop server
sudo systemctl restart minecraft     # Restart server
sudo journalctl -u minecraft -f      # Live logs
sudo journalctl -u minecraft -n 200  # Last 200 lines
```

### Deploy Scripts

```bash
./deploy/update.sh                # Full update (stop → backup → git pull → start)
./deploy/update.sh --skip-backup  # Update without backup
./deploy/stop.sh                  # Graceful shutdown
./deploy/start.sh                 # Start server
./deploy/backup.sh                # Create backup
./deploy/health-check.sh          # Check server health
```

### Local Development

```bash
./launch.sh   # Linux/macOS (2GB RAM)
./launch.bat  # Windows (3GB RAM)
```

---

## Important Notes

| Note | Description |
|------|-------------|
| **Hybrid Server** | Mohist runs BOTH Forge mods and Bukkit plugins |
| **Offline Mode** | `online-mode=false` — no Mojang authentication |
| **Language** | Russian (`lang: ru_RU` in mohist.yml) |
| **Service Name** | `minecraft.service` for systemd |
| **Git LFS** | All `.jar` files tracked via Git LFS |

---

## File Structure

```
.
├── mohist-1.20.1-*.jar           # Server executable (Git LFS)
├── launch.sh / launch.bat        # Launch scripts
├── server.properties             # Core server settings
├── bukkit.yml / spigot.yml       # Bukkit/Spigot config
├── deploy/                       # Deployment scripts
│   ├── update.sh                 # Complete update
│   ├── stop.sh / start.sh        # Server control
│   ├── backup.sh / restore.sh    # Backup management
│   ├── health-check.sh           # Health monitoring
│   ├── configure.sh              # Configuration wizard
│   ├── setup-ubuntu.sh           # Ubuntu setup
│   ├── config.env.example        # Config template
│   ├── lib/logging.sh            # Shared logging
│   ├── prometheus/               # Metrics exporter
│   └── systemd/                  # Service files
├── docs/                         # Documentation
│   ├── CLAUDE-deployment.md      # Deployment guide
│   ├── CLAUDE-monitoring.md      # Monitoring guide
│   ├── CLAUDE-configuration.md   # Configuration guide
│   ├── CLAUDE-mods-plugins.md    # Mods/plugins guide
│   ├── monitoring.md             # Prometheus setup
│   ├── loki-setup.md             # Loki troubleshooting
│   └── grafana-dashboard.json    # Grafana dashboard
├── mohist-config/mohist.yml      # Mohist settings
├── mods/                         # Forge mods (.jar)
├── plugins/                      # Bukkit plugins (.jar + config)
├── config/                       # Mod configs (TOML)
├── backups/                      # World backups
├── logs/                         # Server logs (gitignored)
└── crash-reports/                # Crash reports (gitignored)
```
