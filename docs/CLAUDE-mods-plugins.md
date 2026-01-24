---
title: Mods & Plugins
purpose: Forge mods and Bukkit plugins management
prerequisites: []
related:
  - CLAUDE-configuration.md
  - CLAUDE-deployment.md
---
<!-- CLAUDE INSTRUCTION DOC -->
# Mods & Plugins

> **Purpose**: Managing Forge mods and Bukkit plugins on the hybrid Mohist server.
> **Parent**: [CLAUDE.md](../CLAUDE.md)

---

## Hybrid Architecture

Mohist is a **hybrid server** that runs both:

- **Forge mods** (`/mods/`) — client-side and server-side modifications
- **Bukkit plugins** (`/plugins/`) — server-side plugins with API access

Both systems work together with Mohist's permission bridge.

---

## Installed Plugins

### Core Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| **LuckPerms** | 5.5.18 | Permissions management |
| **TAB** | 4.1.4 | Player list & scoreboard |
| **FlectoneChat** | 4.5.1 | Chat formatting & management |
| **PlaceholderAPI** | 2.11.6 | Placeholder system |

### Utility Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| **SkinsRestorer** | — | Custom player skins |
| **BetterRTP** | 3.6.13 | Random teleportation |
| **Clearlag** | — | Performance optimization |

### Plugin Configuration

Each plugin creates its config in `/plugins/[PluginName]/`:

```
plugins/
├── LuckPerms/
│   ├── config.yml
│   └── storage-method.yml
├── TAB/
│   ├── config.yml
│   └── animations.yml
├── FlectoneChat/
│   └── config.yml
└── PlaceholderAPI/
    └── config.yml
```

---

## Installed Mods

### Technology Mods

| Mod | Version | Description |
|-----|---------|-------------|
| **Mekanism** | 10.4.16.80 | Advanced machinery, energy, generators |
| **Mekanism Generators** | — | Power generation addon |
| **Mekanism Tools** | — | Specialized tools addon |
| **Applied Energistics 2** | 15.4.10 | Storage networks, automation |
| **AE2 Wireless Terminal** | — | Wireless AE2 access |

### World Generation

| Mod | Version | Description |
|-----|---------|-------------|
| **YUNG's Better Caves** | — | Enhanced cave generation |
| **YUNG's Better Dungeons** | — | Improved dungeon structures |
| **YUNG's Better Mineshafts** | — | Redesigned mineshafts |
| **TerraBlender** | — | Biome blending support |
| **Alex's Mobs** | 1.22.9 | 90+ new creatures |

### Quality of Life

| Mod | Version | Description |
|-----|---------|-------------|
| **PlayerRevive** | 2.0.31 | Revive downed players |
| **Mouse Tweaks** | — | Inventory improvements |
| **Better Third Person** | — | Enhanced camera |
| **AppleSkin** | — | Food/hunger info |

### Library Mods (Required)

| Mod | Version | Description |
|-----|---------|-------------|
| **Citadel** | 2.6.2 | Animation/entity library |
| **CreativeCore** | 2.12.32 | UI framework |
| **Architectury** | 9.2.14 | Multi-loader support |
| **Cloth Config** | — | Configuration screens |

---

## Adding New Plugins

### Installation

1. Download `.jar` file (verify Bukkit/Spigot compatibility)

2. Place in `/plugins/` directory:
   ```bash
   cp MyPlugin.jar /path/to/server/plugins/
   ```

3. Restart server:
   ```bash
   ./deploy/update.sh --skip-backup
   ```

4. Configure plugin:
   ```bash
   # Config auto-generated in:
   nano plugins/MyPlugin/config.yml
   ```

5. Reload or restart:
   ```bash
   # Via RCON (if plugin supports)
   mcrcon -H localhost -P 25575 -p PASSWORD "myplugin reload"

   # Or full restart
   ./deploy/update.sh --skip-backup
   ```

### Compatibility Check

- Verify API version matches Mohist (Bukkit 1.20.1)
- Check for Forge mod conflicts
- Test with small player count first

---

## Adding New Mods

### Installation

1. Download `.jar` file (verify Forge 1.20.1 compatibility)

2. Check dependencies (library mods)

3. Place in `/mods/` directory:
   ```bash
   cp MyMod.jar /path/to/server/mods/
   ```

4. Restart server:
   ```bash
   ./deploy/update.sh --skip-backup
   ```

5. Configure mod:
   ```bash
   # Config auto-generated in:
   nano config/mymod-common.toml
   ```

### Mod Configuration

Mod configs use TOML format in `/config/`:

```toml
# config/mekanism-common.toml

[general]
    # Energy unit to display
    energyUnit = "FE"

[miner]
    # Max radius for digital miner
    maxRadius = 32
```

### Client vs Server Mods

| Type | Location | Example |
|------|----------|---------|
| Server-only | `/mods/` | Mekanism, AE2 |
| Client-only | Client `/mods/` | Shaders, OptiFine |
| Both | Both locations | Most content mods |

---

## Troubleshooting

### Plugin Not Loading

```bash
# Check server logs
grep -i "plugin_name" logs/latest.log

# Common issues:
# - Wrong API version
# - Missing dependencies
# - Duplicate plugins
```

### Mod Crash on Startup

```bash
# Check crash report
ls -la crash-reports/

# Read latest crash
cat crash-reports/crash-*.txt | head -100

# Common issues:
# - Missing library mod
# - Version mismatch
# - Forge version incompatibility
```

### Mod/Plugin Conflict

Mohist's permission bridge can cause issues:

```yaml
# mohist-config/mohist.yml
# Try disabling if conflicts occur:
forge_permissions_handler: false
```

### Performance Issues

1. Check entity counts:
   ```bash
   mcrcon -H localhost -P 25575 -p PASSWORD "forge entity list"
   ```

2. Review Clearlag settings:
   ```yaml
   # plugins/Clearlag/config.yml
   auto-removal:
     enabled: true
     interval: 300  # seconds
   ```

3. Adjust spawn limits in `bukkit.yml`

---

## Updating Mods/Plugins

### Safe Update Process

1. Create backup:
   ```bash
   ./deploy/backup.sh
   ```

2. Stop server:
   ```bash
   ./deploy/stop.sh
   ```

3. Replace `.jar` file(s)

4. Start and test:
   ```bash
   ./deploy/start.sh
   ```

5. Check logs for errors:
   ```bash
   sudo journalctl -u minecraft -n 100
   ```

### Version Compatibility

| Component | Version |
|-----------|---------|
| Minecraft | 1.20.1 |
| Forge | (check mohist) |
| Bukkit API | 1.20.1-R0.1 |
| Java | 21 |

---

## See Also

- [Configuration](CLAUDE-configuration.md) — server.properties, bukkit, spigot settings
- [Deployment](CLAUDE-deployment.md) — update and restart scripts
