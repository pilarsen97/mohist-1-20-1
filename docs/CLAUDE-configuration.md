---
title: Server Configuration
purpose: server.properties, bukkit, spigot, mohist configuration
prerequisites: []
related:
  - CLAUDE-deployment.md
  - CLAUDE-mods-plugins.md
---
<!-- CLAUDE INSTRUCTION DOC -->
# Server Configuration

> **Purpose**: Configuration files for Minecraft server settings.
> **Parent**: [CLAUDE.md](../CLAUDE.md)

---

## Configuration Files Overview

| File | Purpose | Format |
|------|---------|--------|
| `server.properties` | Core Minecraft settings | properties |
| `bukkit.yml` | Bukkit API settings | YAML |
| `spigot.yml` | Spigot performance tuning | YAML |
| `mohist-config/mohist.yml` | Mohist hybrid settings | YAML |
| `config/*.toml` | Forge mod configs | TOML |
| `plugins/*/config.yml` | Plugin configs | YAML |

---

## Server Properties

**File**: `server.properties`

### Key Settings

| Line | Property | Value | Description |
|------|----------|-------|-------------|
| 43 | `enable-rcon` | true | Enable RCON for remote commands |
| 44 | `rcon.password` | (configured) | RCON password |
| 45 | `rcon.port` | 25575 | RCON port |
| 49 | `server-ip` | 82.202.140.197 | Bind IP (update for deployment) |
| 50 | `server-port` | 25565 | Game port |
| 51 | `max-players` | 69 | Maximum player slots |
| 52 | `online-mode` | false | Offline mode (no Mojang auth) |
| 53 | `view-distance` | 10 | Chunk render distance |
| 54 | `simulation-distance` | 10 | Entity simulation distance |

### Network Configuration

Before deployment, update:

```properties
# server.properties
server-ip=YOUR_SERVER_IP      # Line 49
server-port=25565             # Line 50 (if non-standard)
rcon.password=SECURE_PASSWORD # Line 44
```

Use `./deploy/configure.sh` for interactive configuration.

---

## Bukkit Configuration

**File**: `bukkit.yml`

### Spawn Limits

```yaml
spawn-limits:
  monsters: 70      # Hostile mobs per world
  animals: 10       # Passive mobs per world
  water-animals: 5  # Fish, dolphins, etc.
  water-ambient: 20 # Tropical fish, etc.
  ambient: 15       # Bats
```

### Tick Rates

```yaml
ticks-per:
  animal-spawns: 400      # Ticks between animal spawn attempts
  monster-spawns: 1       # Ticks between monster spawn attempts
  autosave: 6000          # Ticks between world saves (5 minutes)
```

### Chunk Garbage Collection

```yaml
chunk-gc:
  period-in-ticks: 600    # GC interval
```

---

## Spigot Configuration

**File**: `spigot.yml`

### Entity Activation Ranges

```yaml
entity-activation-range:
  animals: 32           # Blocks from player
  monsters: 32
  raiders: 48
  misc: 16
  water: 16
  villagers: 32
  flying-monsters: 32
```

### Growth Rates

```yaml
growth:
  cactus-modifier: 100     # Percentage of vanilla rate
  cane-modifier: 100
  melon-modifier: 100
  pumpkin-modifier: 100
  sapling-modifier: 100
  wheat-modifier: 100
```

### Item Settings

```yaml
merge-radius:
  item: 2.5              # Blocks - items merge within this radius
  exp: 3.0               # Blocks - XP orbs merge

item-despawn-rate: 6000  # Ticks (5 minutes)
```

---

## Mohist Configuration

**File**: `mohist-config/mohist.yml`

### Core Settings

| Setting | Value | Description |
|---------|-------|-------------|
| `lang` | ru_RU | Server language (Russian) |
| `forge_permissions_handler` | true | Enable Forge-Bukkit permission bridge |
| `world_management` | true | Enhanced dimension control |

### Hybrid Integration

```yaml
# Forge + Bukkit integration
forge_permissions_handler: true  # LuckPerms works with mods
world_management: true           # Better dimension handling

# Entity clearing (performance)
entity_clear:
  enabled: false
  interval: 300  # seconds
```

### Custom Features

```yaml
# Item bans (disable problematic items)
item_bans: []

# Custom MOTD
motd: "KIBERmine Server"

# Player list customization
player_list_format: "%player%"
```

---

## Making Configuration Changes

### Workflow

1. Stop server (or use RCON for hot-reload if supported):
   ```bash
   ./deploy/stop.sh
   ```

2. Edit configuration file(s)

3. Restart server:
   ```bash
   ./deploy/start.sh
   ```

Or use full update cycle:
```bash
./deploy/update.sh --skip-backup
```

### Hot-Reload Commands (RCON)

Some settings can be reloaded without restart:

```bash
# Via mcrcon
mcrcon -H localhost -P 25575 -p PASSWORD "reload confirm"

# Plugin-specific
mcrcon -H localhost -P 25575 -p PASSWORD "lp reload"      # LuckPerms
mcrcon -H localhost -P 25575 -p PASSWORD "tab reload"     # TAB plugin
```

---

## Performance Tuning

### Recommended Settings for 4GB RAM

```properties
# server.properties
view-distance=8
simulation-distance=6
max-players=30
```

```yaml
# bukkit.yml
spawn-limits:
  monsters: 50
  animals: 8

# spigot.yml
entity-activation-range:
  animals: 24
  monsters: 24
  misc: 8
```

### JVM Flags

See `launch.sh` for optimized G1GC settings:

```bash
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
-XX:+UnlockExperimentalVMOptions
-XX:+DisableExplicitGC
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1HeapRegionSize=8M
-XX:G1ReservePercent=20
-XX:G1HeapWastePercent=5
-XX:G1MixedGCCountTarget=4
```

---

## Configuration Directories

| Directory | Contents |
|-----------|----------|
| `/config/` | Forge mod TOML configs (auto-generated) |
| `/plugins/[Name]/` | Plugin YAML configs (auto-generated) |
| `/mohist-config/` | Mohist-specific settings |
| `/defaultconfigs/` | Default templates for new worlds |

---

## See Also

- [Deployment](CLAUDE-deployment.md) — update and restart scripts
- [Mods & Plugins](CLAUDE-mods-plugins.md) — adding and configuring mods/plugins
