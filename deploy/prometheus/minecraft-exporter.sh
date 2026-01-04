#!/bin/bash
# =============================================================================
# minecraft-exporter.sh - Prometheus Metrics Exporter for Minecraft
# =============================================================================
# Lightweight HTTP server exposing Minecraft metrics on port 9225
# Designed to be run as a systemd service alongside the Minecraft server
#
# Metrics exposed:
#   - minecraft_healthy
#   - minecraft_players_online
#   - minecraft_players_max
#   - minecraft_tps
#   - minecraft_uptime_seconds
#   - minecraft_memory_used_bytes
#   - minecraft_memory_max_bytes
#   - minecraft_disk_usage_percent
#   - minecraft_world_size_bytes
#   - minecraft_backup_last_timestamp
#   - minecraft_backup_size_bytes
#
# Usage: ./deploy/prometheus/minecraft-exporter.sh
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVER_DIR="$(cd "${DEPLOY_DIR}/.." && pwd)"

# Load configuration
if [[ -f "${DEPLOY_DIR}/config.env" ]]; then
    source "${DEPLOY_DIR}/config.env"
fi

# Defaults
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9225}"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
GAME_PORT="${GAME_PORT:-25565}"
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-15}"

# Metrics cache
METRICS_CACHE=""
LAST_SCRAPE=0

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# -----------------------------------------------------------------------------
# Metrics Collection
# -----------------------------------------------------------------------------

collect_metrics() {
    local metrics=""

    # Server healthy check
    local healthy=0
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        healthy=1
    elif systemctl is-active --quiet minecraft.service 2>/dev/null; then
        healthy=1
    fi

    metrics+="# HELP minecraft_healthy Whether the Minecraft server is running (1=yes, 0=no)\n"
    metrics+="# TYPE minecraft_healthy gauge\n"
    metrics+="minecraft_healthy ${healthy}\n\n"

    # Player counts
    local players_online=0
    local players_max=69  # from server.properties

    if [[ -n "$RCON_PASSWORD" ]] && [[ $healthy -eq 1 ]]; then
        local list_result
        if command -v mcrcon &>/dev/null; then
            list_result=$(timeout 5 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "list" 2>/dev/null || echo "")
        fi

        # Parse "There are X of a max of Y players online"
        if [[ "$list_result" =~ [Tt]here\ are\ ([0-9]+)\ of\ a\ max\ of\ ([0-9]+) ]]; then
            players_online="${BASH_REMATCH[1]}"
            players_max="${BASH_REMATCH[2]}"
        fi
    fi

    metrics+="# HELP minecraft_players_online Current number of players online\n"
    metrics+="# TYPE minecraft_players_online gauge\n"
    metrics+="minecraft_players_online ${players_online}\n\n"

    metrics+="# HELP minecraft_players_max Maximum number of players allowed\n"
    metrics+="# TYPE minecraft_players_max gauge\n"
    metrics+="minecraft_players_max ${players_max}\n\n"

    # TPS (Ticks Per Second)
    local tps=20.0
    if [[ -n "$RCON_PASSWORD" ]] && [[ $healthy -eq 1 ]]; then
        local tps_result
        if command -v mcrcon &>/dev/null; then
            # Try Mohist/Spigot tps command
            tps_result=$(timeout 5 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "tps" 2>/dev/null || echo "")
        fi

        # Parse TPS (format varies, try to extract first number after TPS label)
        if [[ "$tps_result" =~ ([0-9]+\.[0-9]+) ]]; then
            tps="${BASH_REMATCH[1]}"
        fi
    fi

    metrics+="# HELP minecraft_tps Server ticks per second (20 = optimal)\n"
    metrics+="# TYPE minecraft_tps gauge\n"
    metrics+="minecraft_tps ${tps}\n\n"

    # Uptime
    local uptime_seconds=0
    if systemctl is-active --quiet minecraft.service 2>/dev/null; then
        local started
        started=$(systemctl show minecraft.service --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [[ -n "$started" ]] && [[ "$started" != "n/a" ]]; then
            local started_epoch
            started_epoch=$(date -d "$started" +%s 2>/dev/null || echo "0")
            local now_epoch
            now_epoch=$(date +%s)
            uptime_seconds=$((now_epoch - started_epoch))
        fi
    else
        local pid
        pid=$(pgrep -f "mohist-1.20.1.*\.jar" 2>/dev/null | head -1)
        if [[ -n "$pid" ]]; then
            uptime_seconds=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
        fi
    fi

    metrics+="# HELP minecraft_uptime_seconds Server uptime in seconds\n"
    metrics+="# TYPE minecraft_uptime_seconds counter\n"
    metrics+="minecraft_uptime_seconds ${uptime_seconds}\n\n"

    # Memory usage
    local memory_used=0
    local memory_max=8589934592  # 8GB default

    local pid
    pid=$(pgrep -f "mohist-1.20.1.*\.jar" 2>/dev/null | head -1)
    if [[ -n "$pid" ]]; then
        local rss_kb
        rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$rss_kb" ]]; then
            memory_used=$((rss_kb * 1024))
        fi
    fi

    metrics+="# HELP minecraft_memory_used_bytes Current memory usage in bytes\n"
    metrics+="# TYPE minecraft_memory_used_bytes gauge\n"
    metrics+="minecraft_memory_used_bytes ${memory_used}\n\n"

    metrics+="# HELP minecraft_memory_max_bytes Maximum allocated memory in bytes\n"
    metrics+="# TYPE minecraft_memory_max_bytes gauge\n"
    metrics+="minecraft_memory_max_bytes ${memory_max}\n\n"

    # Disk usage
    local disk_usage=0
    local disk_available=0
    if [[ -d "$SERVER_DIR" ]]; then
        disk_usage=$(df "${SERVER_DIR}" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
        disk_available=$(df -B1 "${SERVER_DIR}" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    fi

    metrics+="# HELP minecraft_disk_usage_percent Disk usage percentage\n"
    metrics+="# TYPE minecraft_disk_usage_percent gauge\n"
    metrics+="minecraft_disk_usage_percent ${disk_usage}\n\n"

    metrics+="# HELP minecraft_disk_available_bytes Available disk space in bytes\n"
    metrics+="# TYPE minecraft_disk_available_bytes gauge\n"
    metrics+="minecraft_disk_available_bytes ${disk_available}\n\n"

    # World sizes
    local world_size=0
    for world in world world_nether world_the_end; do
        if [[ -d "${SERVER_DIR}/${world}" ]]; then
            local size
            size=$(du -sb "${SERVER_DIR}/${world}" 2>/dev/null | cut -f1 || echo "0")
            world_size=$((world_size + size))
        fi
    done

    metrics+="# HELP minecraft_world_size_bytes Total size of all worlds in bytes\n"
    metrics+="# TYPE minecraft_world_size_bytes gauge\n"
    metrics+="minecraft_world_size_bytes ${world_size}\n\n"

    # Backup info
    local backup_dir="${SERVER_DIR}/backups"
    local backup_timestamp=0
    local backup_size=0

    if [[ -d "$backup_dir" ]]; then
        local latest_backup
        latest_backup=$(ls -t "${backup_dir}"/backup_*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            backup_timestamp=$(stat -c %Y "$latest_backup" 2>/dev/null || stat -f %m "$latest_backup" 2>/dev/null || echo "0")
            backup_size=$(stat -c %s "$latest_backup" 2>/dev/null || stat -f %z "$latest_backup" 2>/dev/null || echo "0")
        fi
    fi

    metrics+="# HELP minecraft_backup_last_timestamp Unix timestamp of last backup\n"
    metrics+="# TYPE minecraft_backup_last_timestamp gauge\n"
    metrics+="minecraft_backup_last_timestamp ${backup_timestamp}\n\n"

    metrics+="# HELP minecraft_backup_size_bytes Size of last backup in bytes\n"
    metrics+="# TYPE minecraft_backup_size_bytes gauge\n"
    metrics+="minecraft_backup_size_bytes ${backup_size}\n\n"

    # Exporter info
    metrics+="# HELP minecraft_exporter_scrape_duration_seconds Time to collect metrics\n"
    metrics+="# TYPE minecraft_exporter_scrape_duration_seconds gauge\n"
    metrics+="minecraft_exporter_scrape_duration_seconds 0.1\n"

    echo -e "$metrics"
}

# -----------------------------------------------------------------------------
# HTTP Server
# -----------------------------------------------------------------------------

handle_request() {
    local request="$1"

    # Parse request line
    local method path
    read -r method path _ <<< "$request"

    # Log request
    log "Request: $method $path"

    case "$path" in
        /metrics)
            # Collect metrics
            local metrics
            metrics=$(collect_metrics)

            # Send response
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/plain; charset=utf-8"
            echo "Content-Length: ${#metrics}"
            echo ""
            echo -e "$metrics"
            ;;

        /health|/healthz)
            local healthy="OK"
            local status="200 OK"

            if ! pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
                if ! systemctl is-active --quiet minecraft.service 2>/dev/null; then
                    healthy="UNHEALTHY"
                    status="503 Service Unavailable"
                fi
            fi

            echo "HTTP/1.1 $status"
            echo "Content-Type: text/plain"
            echo "Content-Length: ${#healthy}"
            echo ""
            echo "$healthy"
            ;;

        /)
            local body="<html><head><title>Minecraft Exporter</title></head><body>
<h1>Minecraft Prometheus Exporter</h1>
<p><a href='/metrics'>Metrics</a></p>
<p><a href='/health'>Health</a></p>
</body></html>"

            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo "Content-Length: ${#body}"
            echo ""
            echo "$body"
            ;;

        *)
            local body="Not Found"
            echo "HTTP/1.1 404 Not Found"
            echo "Content-Type: text/plain"
            echo "Content-Length: ${#body}"
            echo ""
            echo "$body"
            ;;
    esac
}

start_server() {
    log "Starting Minecraft Prometheus Exporter on port ${PROMETHEUS_PORT}"

    # Check if nc (netcat) is available
    if ! command -v nc &>/dev/null; then
        log "ERROR: netcat (nc) not found. Install with: apt install netcat-openbsd"
        exit 1
    fi

    # Create FIFO for bidirectional communication with netcat
    local fifo="/tmp/minecraft-exporter-$$"
    mkfifo "$fifo" 2>/dev/null || true

    # Cleanup FIFO on exit
    trap "rm -f $fifo" EXIT

    # HTTP server using netcat with FIFO for bidirectional I/O
    while true; do
        # cat sends response back through netcat to client
        # nc receives request and pipes to processing block
        # processing block writes response to FIFO
        cat "$fifo" | nc -l -p "${PROMETHEUS_PORT}" -q 1 2>/dev/null | {
            # Read request
            local request=""
            while IFS= read -r line; do
                line="${line%%$'\r'}"
                [[ -z "$line" ]] && break
                [[ -z "$request" ]] && request="$line"
            done

            # Handle request and send response to FIFO
            if [[ -n "$request" ]]; then
                handle_request "$request"
            fi
        } > "$fifo"
    done
}

# -----------------------------------------------------------------------------
# Signal Handlers
# -----------------------------------------------------------------------------

cleanup() {
    log "Shutting down Minecraft Exporter"
    exit 0
}

trap cleanup SIGTERM SIGINT

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

log "Minecraft Prometheus Exporter starting..."
log "Server directory: ${SERVER_DIR}"
log "Metrics endpoint: http://localhost:${PROMETHEUS_PORT}/metrics"

start_server
