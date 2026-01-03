#!/bin/bash
# =============================================================================
# health-check.sh - Minecraft Server Health Monitoring
# =============================================================================
# Performs comprehensive health checks on the Minecraft server
# Outputs JSON for Prometheus/monitoring integration
#
# Usage:
#   ./deploy/health-check.sh              # Human-readable output
#   ./deploy/health-check.sh --json       # JSON output for monitoring
#   ./deploy/health-check.sh --quiet      # Exit code only (0=healthy)
#   ./deploy/health-check.sh --prometheus # Prometheus metrics format
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
GAME_PORT="${GAME_PORT:-25565}"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"

# Output mode
OUTPUT_MODE="human"
case "${1:-}" in
    --json)       OUTPUT_MODE="json" ;;
    --quiet)      OUTPUT_MODE="quiet" ;;
    --prometheus) OUTPUT_MODE="prometheus" ;;
esac

# -----------------------------------------------------------------------------
# Health Check Functions
# -----------------------------------------------------------------------------

# Initialize results
declare -A CHECKS
CHECKS[process]=0
CHECKS[port]=0
CHECKS[rcon]=0
CHECKS[disk]=0
CHECKS[memory]=0
OVERALL_HEALTHY=true

# Check if server process is running
check_process() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        CHECKS[process]=1
        return 0
    fi

    if systemctl is-active --quiet minecraft.service 2>/dev/null; then
        CHECKS[process]=1
        return 0
    fi

    OVERALL_HEALTHY=false
    return 1
}

# Check if game port is accepting connections
check_port() {
    if timeout "${HEALTH_CHECK_TIMEOUT}" bash -c "echo > /dev/tcp/localhost/${GAME_PORT}" 2>/dev/null; then
        CHECKS[port]=1
        return 0
    fi

    # Alternative check with nc
    if command -v nc &>/dev/null; then
        if nc -z -w"${HEALTH_CHECK_TIMEOUT}" localhost "${GAME_PORT}" 2>/dev/null; then
            CHECKS[port]=1
            return 0
        fi
    fi

    OVERALL_HEALTHY=false
    return 1
}

# Check RCON connectivity
check_rcon() {
    if [[ -z "$RCON_PASSWORD" ]]; then
        CHECKS[rcon]=0
        return 1
    fi

    # Try mcrcon
    if command -v mcrcon &>/dev/null; then
        if timeout "${HEALTH_CHECK_TIMEOUT}" mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "list" &>/dev/null; then
            CHECKS[rcon]=1
            return 0
        fi
    fi

    # Try rcon-cli
    if command -v rcon-cli &>/dev/null; then
        if timeout "${HEALTH_CHECK_TIMEOUT}" rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "list" &>/dev/null; then
            CHECKS[rcon]=1
            return 0
        fi
    fi

    OVERALL_HEALTHY=false
    return 1
}

# Check disk space
check_disk() {
    local usage
    usage=$(df "${SERVER_DIR}" | tail -1 | awk '{print $5}' | tr -d '%')

    DISK_USAGE_PERCENT="$usage"
    DISK_AVAILABLE=$(df -B1 "${SERVER_DIR}" | tail -1 | awk '{print $4}')

    if [[ $usage -lt 90 ]]; then
        CHECKS[disk]=1
        return 0
    fi

    OVERALL_HEALTHY=false
    return 1
}

# Check memory usage (if server is running)
check_memory() {
    local pid
    pid=$(pgrep -f "mohist-1.20.1.*\.jar" 2>/dev/null | head -1)

    if [[ -n "$pid" ]]; then
        # Get memory in KB, convert to bytes
        MEMORY_RSS_KB=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$MEMORY_RSS_KB" ]]; then
            MEMORY_RSS_BYTES=$((MEMORY_RSS_KB * 1024))
            # Check if under 8GB (reasonable limit)
            if [[ $MEMORY_RSS_BYTES -lt 8589934592 ]]; then
                CHECKS[memory]=1
                return 0
            fi
        fi
    else
        CHECKS[memory]=0
        return 1
    fi

    OVERALL_HEALTHY=false
    return 1
}

# Get player count via RCON
get_player_count() {
    if [[ -z "$RCON_PASSWORD" ]]; then
        echo "0"
        return
    fi

    local result
    if command -v mcrcon &>/dev/null; then
        result=$(timeout "${HEALTH_CHECK_TIMEOUT}" mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "list" 2>/dev/null || echo "")
    elif command -v rcon-cli &>/dev/null; then
        result=$(timeout "${HEALTH_CHECK_TIMEOUT}" rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "list" 2>/dev/null || echo "")
    fi

    # Parse "There are X of a max of Y players online"
    if [[ "$result" =~ [Tt]here\ are\ ([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

# Get server uptime
get_uptime() {
    if systemctl is-active --quiet minecraft.service 2>/dev/null; then
        local started
        started=$(systemctl show minecraft.service --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [[ -n "$started" ]]; then
            local started_epoch
            started_epoch=$(date -d "$started" +%s 2>/dev/null || echo "0")
            local now_epoch
            now_epoch=$(date +%s)
            echo $((now_epoch - started_epoch))
            return
        fi
    fi

    # Fallback: check process start time
    local pid
    pid=$(pgrep -f "mohist-1.20.1.*\.jar" 2>/dev/null | head -1)
    if [[ -n "$pid" ]]; then
        local etime
        etime=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
        echo "${etime:-0}"
        return
    fi

    echo "0"
}

# Get world sizes
get_world_sizes() {
    local total=0
    for world in world world_nether world_the_end; do
        if [[ -d "${SERVER_DIR}/${world}" ]]; then
            local size
            size=$(du -sb "${SERVER_DIR}/${world}" 2>/dev/null | cut -f1)
            total=$((total + ${size:-0}))
        fi
    done
    echo "$total"
}

# -----------------------------------------------------------------------------
# Run All Checks
# -----------------------------------------------------------------------------

run_checks() {
    check_process || true
    check_port || true
    check_rcon || true
    check_disk || true
    check_memory || true

    PLAYER_COUNT=$(get_player_count)
    UPTIME_SECONDS=$(get_uptime)
    WORLD_SIZE_BYTES=$(get_world_sizes)
}

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------

output_human() {
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Minecraft Server Health Check"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    # Status icon
    local status_icon status_text
    if $OVERALL_HEALTHY; then
        status_icon="✓"
        status_text="HEALTHY"
        echo -e "  Status: \033[0;32m${status_icon} ${status_text}\033[0m"
    else
        status_icon="✗"
        status_text="UNHEALTHY"
        echo -e "  Status: \033[0;31m${status_icon} ${status_text}\033[0m"
    fi

    echo ""
    echo "─── Checks ─────────────────────────────────────────────"

    for check in process port rcon disk memory; do
        local icon
        if [[ ${CHECKS[$check]} -eq 1 ]]; then
            icon="\033[0;32m✓\033[0m"
        else
            icon="\033[0;31m✗\033[0m"
        fi
        printf "  %-10s %b\n" "$check" "$icon"
    done

    echo ""
    echo "─── Metrics ────────────────────────────────────────────"
    printf "  %-20s %s\n" "Players Online:" "${PLAYER_COUNT:-0}"
    printf "  %-20s %s\n" "Uptime:" "$(format_duration ${UPTIME_SECONDS:-0})"
    printf "  %-20s %s\n" "Disk Usage:" "${DISK_USAGE_PERCENT:-0}%"
    printf "  %-20s %s\n" "Memory (RSS):" "$(format_bytes ${MEMORY_RSS_BYTES:-0})"
    printf "  %-20s %s\n" "World Size:" "$(format_bytes ${WORLD_SIZE_BYTES:-0})"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""
}

output_json() {
    local healthy_int=0
    $OVERALL_HEALTHY && healthy_int=1

    cat <<EOF
{
  "healthy": $healthy_int,
  "timestamp": "$(date -Iseconds)",
  "checks": {
    "process": ${CHECKS[process]},
    "port": ${CHECKS[port]},
    "rcon": ${CHECKS[rcon]},
    "disk": ${CHECKS[disk]},
    "memory": ${CHECKS[memory]}
  },
  "metrics": {
    "players_online": ${PLAYER_COUNT:-0},
    "uptime_seconds": ${UPTIME_SECONDS:-0},
    "disk_usage_percent": ${DISK_USAGE_PERCENT:-0},
    "disk_available_bytes": ${DISK_AVAILABLE:-0},
    "memory_rss_bytes": ${MEMORY_RSS_BYTES:-0},
    "world_size_bytes": ${WORLD_SIZE_BYTES:-0}
  }
}
EOF
}

output_prometheus() {
    local healthy_int=0
    $OVERALL_HEALTHY && healthy_int=1

    cat <<EOF
# HELP minecraft_healthy Whether the server is healthy (1=healthy, 0=unhealthy)
# TYPE minecraft_healthy gauge
minecraft_healthy ${healthy_int}

# HELP minecraft_check_status Individual health check status (1=pass, 0=fail)
# TYPE minecraft_check_status gauge
minecraft_check_status{check="process"} ${CHECKS[process]}
minecraft_check_status{check="port"} ${CHECKS[port]}
minecraft_check_status{check="rcon"} ${CHECKS[rcon]}
minecraft_check_status{check="disk"} ${CHECKS[disk]}
minecraft_check_status{check="memory"} ${CHECKS[memory]}

# HELP minecraft_players_online Current number of players online
# TYPE minecraft_players_online gauge
minecraft_players_online ${PLAYER_COUNT:-0}

# HELP minecraft_uptime_seconds Server uptime in seconds
# TYPE minecraft_uptime_seconds gauge
minecraft_uptime_seconds ${UPTIME_SECONDS:-0}

# HELP minecraft_disk_usage_percent Disk usage percentage
# TYPE minecraft_disk_usage_percent gauge
minecraft_disk_usage_percent ${DISK_USAGE_PERCENT:-0}

# HELP minecraft_disk_available_bytes Disk space available in bytes
# TYPE minecraft_disk_available_bytes gauge
minecraft_disk_available_bytes ${DISK_AVAILABLE:-0}

# HELP minecraft_memory_rss_bytes Memory RSS usage in bytes
# TYPE minecraft_memory_rss_bytes gauge
minecraft_memory_rss_bytes ${MEMORY_RSS_BYTES:-0}

# HELP minecraft_world_size_bytes Total world size in bytes
# TYPE minecraft_world_size_bytes gauge
minecraft_world_size_bytes ${WORLD_SIZE_BYTES:-0}
EOF
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

format_bytes() {
    local bytes="$1"
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=1; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=1; $bytes/1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=1; $bytes/1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

format_duration() {
    local seconds="$1"
    if [[ $seconds -ge 86400 ]]; then
        echo "$((seconds/86400))d $((seconds%86400/3600))h"
    elif [[ $seconds -ge 3600 ]]; then
        echo "$((seconds/3600))h $((seconds%3600/60))m"
    elif [[ $seconds -ge 60 ]]; then
        echo "$((seconds/60))m $((seconds%60))s"
    else
        echo "${seconds}s"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

run_checks

case "$OUTPUT_MODE" in
    json)
        output_json
        ;;
    prometheus)
        output_prometheus
        ;;
    quiet)
        # Just exit with appropriate code
        ;;
    *)
        output_human
        ;;
esac

# Exit with appropriate code
if $OVERALL_HEALTHY; then
    exit 0
else
    exit 1
fi
