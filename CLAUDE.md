# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Mohist 1.20.1 Minecraft server - a hybrid server software combining Forge mod support with Bukkit/Spigot plugin compatibility. The server runs both Forge mods and Bukkit plugins simultaneously, allowing for extensive customization and gameplay features.

**Core Components:**
- **Server JAR**: `mohist-1.20.1-2eb79df.jar` - The main Mohist server executable
- **Mods Directory**: `/mods/` - Forge mods (45+ installed including Mekanism, Applied Energistics 2, Alex's Mobs)
- **Plugins Directory**: `/plugins/` - Bukkit/Spigot plugins (LuckPerms, TAB, FlectoneChat, SkinsRestorer, etc.)
- **Config Directory**: `/config/` - Forge mod configurations
- **Mohist Config**: `/mohist-config/` - Mohist-specific server settings

## Quick Reference

### Systemd Commands (production)
```bash
sudo systemctl status minecraft      # Check status
sudo systemctl start minecraft       # Start server
sudo systemctl stop minecraft        # Stop server
sudo systemctl restart minecraft     # Restart server
sudo journalctl -u minecraft -f      # Live logs
sudo journalctl -u minecraft -n 200  # Last 200 lines
```

## Server Launch Commands

### Windows
```bash
./launch.bat
# Allocates 1GB min, 3GB max RAM
```

### Linux/macOS
```bash
./launch.sh
# Allocates 1GB min, 2GB max RAM
```

Both scripts launch the Mohist server JAR with the configured memory settings. Wait for "Done" message in console before connecting.

## Configuration Architecture

### Server Properties (`server.properties`)
- **IP Configuration**: Line 49 - `server-ip=82.202.140.197` (must be updated for deployment)
- **RCON**: Enabled on port 25575 with password configured (line 43-44)
- **Game Settings**: Port 25565, max players 69, offline mode enabled
- **Performance**: View distance 10, simulation distance 10

### Bukkit Configuration (`bukkit.yml`)
- Spawn limits for different entity types (monsters: 70, animals: 10)
- Tick rates for spawning and autosave
- Chunk garbage collection settings

### Spigot Configuration (`spigot.yml`)
- Advanced entity activation ranges
- Growth rates for crops and plants
- Item despawn rates and merge radius
- Command restrictions and tab completion

### Mohist Configuration (`mohist-config/mohist.yml`)
- Hybrid server settings (Forge + Bukkit integration)
- Permission system configuration
- Custom features (entity clearing, item bans, MOTD)
- Language: Russian (`lang: ru_RU`)
- Forge permission handler enabled

## Plugin Architecture

**Key Installed Plugins:**
- **LuckPerms** (v5.5.18): Permissions management system
- **TAB** (v4.1.4): Player list and scoreboard customization
- **FlectoneChat** (v4.5.1): Advanced chat management
- **SkinsRestorer**: Custom player skin support
- **PlaceholderAPI** (v2.11.6): Placeholder system for other plugins
- **BetterRTP** (v3.6.13): Random teleportation with configuration
- **Clearlag**: Performance optimization through entity clearing

Each plugin has its own configuration directory under `/plugins/[PluginName]/`.

## Mod Architecture

**Major Mod Categories:**

1. **Technology Mods:**
   - Mekanism suite (v10.4.16.80): Advanced machinery, energy systems, generators
   - Applied Energistics 2 (v15.4.10): Storage network and automation
   - AE2 Wireless Terminal Library: Wireless access to AE2 networks

2. **World Generation:**
   - YUNG's Better Caves/Dungeons/Mineshafts: Enhanced structure generation
   - TerraBlender: Biome blending support
   - Alex's Mobs (v1.22.9): 90+ new creatures with extensive configuration

3. **Quality of Life:**
   - PlayerRevive (v2.0.31): Revive downed players
   - Mouse Tweaks: Inventory management improvements
   - Better Third Person: Enhanced camera controls
   - AppleSkin: Food/hunger information display

4. **Library/Framework Mods:**
   - Citadel (v2.6.2): Animation/entity library
   - CreativeCore (v2.12.32): UI framework
   - Architectury (v9.2.14): Multi-loader support
   - Cloth Config: Configuration screen library

All mod configurations are stored in `/config/` with TOML format files named after each mod.

## Deployment Scripts

The `/deploy/` directory contains automated deployment and management scripts for safe server operations.

### Available Scripts

#### `update.sh` - Complete Update Procedure
Full automated update with safety checks:
```bash
./deploy/update.sh
```
Process: Stop server gracefully → Backup worlds → Deploy from Git → Validate → Start server

Includes automatic rollback on failure.

#### `stop.sh` - Graceful Server Shutdown
Stops server with world save:
```bash
./deploy/stop.sh
```
- Sends `save-all` command via RCON before stopping
- Notifies connected players
- Works in both dev (macOS) and production (systemd) environments

#### `start.sh` - Start Server
Starts the server via systemd (production) or direct launch (dev):
```bash
./deploy/start.sh
```

#### `deploy.sh` - Deploy from Git
Updates server files from Git repository:
```bash
./deploy/deploy.sh
```
- Validates Git LFS is configured
- Fetches all changes including large files (>100MB)
- Verifies server JAR integrity after deployment
- Includes error handling and rollback capability

#### `backup.sh` - Create Backup
Creates timestamped backups of world files:
```bash
./deploy/backup.sh          # Create backup
./deploy/backup.sh --list   # List existing backups
```
- Backs up: world, world_nether, world_the_end
- Includes server configuration files
- Auto-cleanup: keeps last 7 backups
- Compressed tar.gz format

#### `graceful-shutdown.sh` - RCON Shutdown Helper
Used internally by stop.sh for graceful shutdowns:
- Sends save-all command via RCON
- Disables auto-save temporarily
- Notifies players of shutdown
- Waits for save completion

#### `setup-ubuntu.sh` - Ubuntu Production Setup
Complete Ubuntu server setup automation:
```bash
sudo ./deploy/setup-ubuntu.sh
```
- Installs Java 17, mcrcon, and dependencies
- Creates minecraft user and directories
- Configures firewall (UFW) rules
- Sets up systemd services

#### `configure.sh` - Server Configuration Wizard
Interactive configuration of server.properties:
```bash
./deploy/configure.sh
```
- Generates secure 16-character RCON password (or accepts custom)
- Configures server IP and MOTD interactively
- Automatically syncs password to `deploy/config.env`
- Creates `server.properties` from `.example` template if needed

#### `health-check.sh` - Server Health Check
Comprehensive health monitoring:
```bash
./deploy/health-check.sh
```
- Checks server process status
- Validates RCON connectivity
- Reports memory usage and player count
- Returns exit codes for monitoring systems

#### `install-service.sh` - Systemd Service Installer
Installs systemd service files:
```bash
sudo ./deploy/install-service.sh
```
- Copies service files to `/etc/systemd/system/`
- Enables minecraft.service and minecraft-exporter.service
- Configures automatic startup on boot

### Configuration

Scripts use centralized configuration from `deploy/config.env`:
```bash
cp deploy/config.env.example deploy/config.env
# Edit config.env with your settings
```

Key settings: `SERVER_DIR`, `RCON_PASSWORD`, `MIN_RAM`, `MAX_RAM`

### RCON Configuration

Scripts use RCON for safe server communication:
- **Host**: localhost
- **Port**: 25575
- **Password**: See `server.properties` line 43

**Required tool**: Install `mcrcon` for RCON functionality:
```bash
# macOS
brew install mcrcon

# Linux
apt install mcrcon
```

### Git LFS Support

All `.jar` files (including the 135MB server JAR) are tracked via Git LFS:
- Configured in `.gitattributes`
- Deploy script automatically handles LFS files
- Verifies file integrity after deployment

### Backup System

Backups stored in `/backups/` directory:
- Naming format: `backup_YYYYMMDD_HHMMSS`
- Retention: Last 7 backups kept automatically
- Each backup includes metadata file with Git commit info

### Monitoring Infrastructure

Prometheus metrics exporter for server monitoring:

**Components:**
- `deploy/prometheus/minecraft-exporter.sh` - Exports server metrics on port 9225
- `deploy/prometheus/prometheus-target.yml` - Prometheus scrape configuration
- `deploy/systemd/minecraft-exporter.service` - Systemd service for exporter

**Available Metrics:**
- Player count and online status
- Server TPS and memory usage
- World statistics

**Setup Guide:** See `docs/monitoring.md` for complete Prometheus + Grafana setup instructions.

**Pre-configured Dashboard:** Import `docs/grafana-dashboard.json` into Grafana for ready-to-use visualization.

## Development & Maintenance Workflow

### Configuration Changes
1. Modify configuration files in appropriate directories
2. For server properties: Edit `server.properties`, `bukkit.yml`, `spigot.yml`, or `mohist-config/mohist.yml`
3. For mods: Edit TOML files in `/config/` directory
4. For plugins: Edit YAML/configuration files in `/plugins/[PluginName]/` directories
5. Restart server to apply changes (use `./deploy/update.sh` for safe restart)

### Adding Mods
1. Place `.jar` file in `/mods/` directory
2. Configuration files will be auto-generated in `/config/` on first launch
3. Verify compatibility with Minecraft 1.20.1 and Forge
4. Restart server with `./deploy/update.sh`

### Adding Plugins
1. Place `.jar` file in `/plugins/` directory
2. Plugin will auto-generate config folder in `/plugins/[PluginName]/` on first launch
3. Verify compatibility with Bukkit/Spigot API version
4. Restart server with `./deploy/update.sh`

### Deploying Updates
Use the automated update script for safe deployments:
```bash
./deploy/update.sh
```
This ensures proper shutdown, backup, and validation.

### IP/Network Configuration
- Update `server-ip` in `server.properties` (line 49) before deployment
- RCON password should be changed from default (line 43)
- Default port 25565 can be modified if needed (line 50)

## Important Notes

- **Hybrid Server**: This uses Mohist, not vanilla Forge or Bukkit - it runs BOTH mods and plugins
- **Memory Allocation**: Windows launch script allocates 3GB max, Linux/macOS allocates 2GB max - adjust if needed
- **Offline Mode**: Server runs in offline mode (`online-mode=false`) - no Mojang authentication
- **Language**: Server is configured for Russian language (`lang: ru_RU` in mohist.yml)
- **Permissions**: Mohist's Forge-Bukkit permission bridge is enabled for mod permission integration
- **World Management**: Mohist world management enabled - allows better control over dimensions
- **Service Name**: `minecraft.service` for systemd operations
- **Logs**: `/logs/` directory contains server logs (gitignored)
- **Crash Reports**: `/crash-reports/` directory contains crash reports (gitignored)

## File Structure
```
.
├── mohist-1.20.1-2eb79df.jar    # Server executable (135MB, Git LFS)
├── launch.bat / launch.sh        # Launch scripts
├── server.properties             # Core server settings
├── bukkit.yml                    # Bukkit configuration
├── spigot.yml                    # Spigot configuration
├── deploy/                       # Deployment automation scripts
│   ├── update.sh                 # Complete update procedure
│   ├── stop.sh                   # Graceful server stop
│   ├── start.sh                  # Server start
│   ├── deploy.sh                 # Git deployment
│   ├── backup.sh                 # World backup utility
│   ├── graceful-shutdown.sh      # RCON shutdown helper
│   ├── setup-ubuntu.sh           # Ubuntu production setup
│   ├── configure.sh              # Server configuration wizard
│   ├── health-check.sh           # Server health check
│   ├── install-service.sh        # Systemd service installer
│   ├── config.env.example        # Configuration template
│   ├── lib/
│   │   └── logging.sh            # Shared logging library
│   ├── prometheus/
│   │   ├── minecraft-exporter.sh     # Prometheus metrics exporter
│   │   └── prometheus-target.yml     # Prometheus scrape config
│   └── systemd/
│       ├── minecraft.service         # Main server service
│       └── minecraft-exporter.service # Exporter service
├── backups/                      # Automated backups (auto-created)
├── logs/                         # Server logs (gitignored)
├── crash-reports/                # Crash reports (gitignored)
├── docs/
│   ├── deployment.md             # Production systemd setup guide
│   ├── monitoring.md             # Prometheus + Grafana setup guide
│   └── grafana-dashboard.json    # Pre-configured Grafana dashboard
├── mohist-config/
│   └── mohist.yml                # Mohist-specific settings
├── mods/                         # Forge mods (.jar files)
├── plugins/                      # Bukkit plugins (.jar + configs)
├── config/                       # Mod configurations (TOML files)
├── libraries/                    # Dependency libraries (Git LFS)
└── defaultconfigs/               # Default configuration templates
```
