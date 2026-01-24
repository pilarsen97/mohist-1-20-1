---
title: Deployment Scripts
purpose: Server deployment, updates, backups, and operations
prerequisites: []
related:
  - CLAUDE-monitoring.md
  - CLAUDE-configuration.md
---
<!-- CLAUDE INSTRUCTION DOC -->
# Deployment Scripts

> **Purpose**: Automated deployment and management scripts for safe server operations.
> **Parent**: [CLAUDE.md](../CLAUDE.md)

---

## Quick Reference

| Script | Purpose | Flags |
|--------|---------|-------|
| `update.sh` | Full update cycle | `--skip-backup`, `--no-start`, `--dry-run` |
| `stop.sh` | Graceful shutdown | — |
| `start.sh` | Start server | `--no-wait` |
| `deploy.sh` | Git pull + validate | — |
| `backup.sh` | Create backup | `--list` |
| `restore.sh` | Restore from backup | — |
| `health-check.sh` | Check server health | `--quiet` |
| `configure.sh` | Interactive config wizard | — |
| `setup-ubuntu.sh` | Ubuntu production setup | — |
| `install-service.sh` | Install systemd services | — |

---

## Update Scripts

### `update.sh` - Complete Update Procedure

Full automated update with safety checks:

```bash
./deploy/update.sh                # Normal update (with backup)
./deploy/update.sh --skip-backup  # Skip backup step
./deploy/update.sh --no-start     # Update but don't start server
./deploy/update.sh --dry-run      # Show what would be done
```

**Process**: Stop server → Backup worlds → Deploy from Git → Validate → Start server

Includes automatic rollback on failure.

### `deploy.sh` - Deploy from Git

Updates server files from Git repository:

```bash
./deploy/deploy.sh
```

- Validates Git LFS is configured
- Fetches all changes including large files (>100MB)
- Verifies server JAR integrity after deployment
- Includes error handling and rollback capability

---

## Server Control

### `stop.sh` - Graceful Server Shutdown

```bash
./deploy/stop.sh
```

- Sends `save-all` command via RCON before stopping
- Notifies connected players
- Works in both dev (macOS) and production (systemd) environments

### `start.sh` - Start Server

```bash
./deploy/start.sh
./deploy/start.sh --no-wait  # Don't wait for startup
```

Starts via systemd (production) or direct launch (dev).

### `graceful-shutdown.sh` - RCON Shutdown Helper

Used internally by `stop.sh`:

- Sends save-all command via RCON
- Disables auto-save temporarily
- Notifies players of shutdown
- Waits for save completion

---

## Backup & Restore

### `backup.sh` - Create Backup

```bash
./deploy/backup.sh          # Create backup
./deploy/backup.sh --list   # List existing backups
```

**Features**:
- Backs up: `world`, `world_nether`, `world_the_end`
- Includes server configuration files
- Auto-cleanup: keeps last 7 backups
- Compressed `tar.gz` format
- Disk space validation before backup

**Storage**: `/backups/` directory
- Naming format: `backup_YYYYMMDD_HHMMSS`
- Each backup includes metadata file with Git commit info

### `restore.sh` - Restore from Backup

```bash
./deploy/restore.sh                    # Interactive selection
./deploy/restore.sh backup_20240115_120000  # Specific backup
```

---

## Health & Monitoring

### `health-check.sh` - Server Health Check

```bash
./deploy/health-check.sh
./deploy/health-check.sh --quiet  # Exit codes only
```

**Checks**:
- Server process status
- RCON connectivity
- Memory usage
- Player count

Returns exit codes for monitoring systems.

---

## Setup & Installation

### `setup-ubuntu.sh` - Ubuntu Production Setup

```bash
sudo ./deploy/setup-ubuntu.sh
```

**Installs**:
- Java 21 and dependencies
- mcrcon for RCON communication
- Creates minecraft user and directories
- Configures firewall (UFW) rules
- Sets up systemd services

### `install-service.sh` - Systemd Service Installer

```bash
sudo ./deploy/install-service.sh
```

- Copies service files to `/etc/systemd/system/`
- Enables `minecraft.service` and `minecraft-exporter.service`
- Configures automatic startup on boot

### `configure.sh` - Server Configuration Wizard

```bash
./deploy/configure.sh
```

**Features**:
- Generates secure 16-character RCON password (or accepts custom)
- Configures server IP and MOTD interactively
- Automatically syncs password to `deploy/config.env`
- Creates `server.properties` from `.example` template if needed

---

## Configuration

### `config.env` - Centralized Settings

```bash
cp deploy/config.env.example deploy/config.env
# Edit config.env with your settings
```

**Key settings**:

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_DIR` | Server root directory | auto-detected |
| `RCON_PASSWORD` | RCON password | from server.properties |
| `MIN_RAM` | Minimum heap size | 1G |
| `MAX_RAM` | Maximum heap size | 2G |
| `SERVICE_NAME` | Systemd service name | minecraft |

### RCON Configuration

Scripts use RCON for safe server communication:

| Setting | Value |
|---------|-------|
| Host | localhost |
| Port | 25575 |
| Password | See `server.properties` line 43 |

**Required tool**: Install `mcrcon`:

```bash
# macOS
brew install mcrcon

# Linux
apt install mcrcon
```

---

## Git LFS Support

All `.jar` files (including the 135MB server JAR) are tracked via Git LFS:

- Configured in `.gitattributes`
- Deploy script automatically handles LFS files
- Verifies file integrity after deployment

---

## Systemd Commands (Production)

```bash
sudo systemctl status minecraft      # Check status
sudo systemctl start minecraft       # Start server
sudo systemctl stop minecraft        # Stop server
sudo systemctl restart minecraft     # Restart server
sudo journalctl -u minecraft -f      # Live logs
sudo journalctl -u minecraft -n 200  # Last 200 lines
```

---

## See Also

- [Monitoring](CLAUDE-monitoring.md) — Prometheus, Grafana, Loki
- [Configuration](CLAUDE-configuration.md) — server.properties, bukkit, spigot
