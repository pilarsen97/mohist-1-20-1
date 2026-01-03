#!/bin/bash
# =============================================================================
# start.sh - Start Minecraft Server with Health Checks
# =============================================================================
# Starts the Minecraft server with pre-flight validation and health monitoring.
# Works in both development (direct launch) and production (systemd) environments.
#
# Features:
#   - Pre-start validation (JAR, permissions, disk space)
#   - Environment detection (systemd vs direct)
#   - Health check after startup (port, RCON)
#   - Pretty progress logging
#
# Usage:
#   ./deploy/start.sh              # Start with health check
#   ./deploy/start.sh --no-wait    # Start without waiting for health check
#   ./deploy/start.sh --direct     # Force direct launch (no systemd)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared logging library
if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
    source "${SCRIPT_DIR}/lib/logging.sh"
else
    # Fallback minimal logging
    log_info() { echo "[INFO] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_success() { echo "[OK] $1"; }
    log_step() { echo "[STEP] $1"; }
    log_substep() { echo "  - $1"; }
    log_substep_last() { echo "  - $1"; }
    print_header() { echo "=== $1 ==="; }
    print_footer() { echo "=== $1 ==="; }
    start_timer() { START_TIME=$(date +%s); }
    get_elapsed() { echo "$(($(date +%s) - START_TIME))s"; }
    init_steps() { :; }
fi

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
GAME_PORT="${GAME_PORT:-25565}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-120}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"
SERVICE_NAME="${SERVICE_NAME:-minecraft}"
MIN_JAR_SIZE="${MIN_JAR_SIZE:-100000000}"

# Flags
NO_WAIT=false
FORCE_DIRECT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-wait)
            NO_WAIT=true
            shift
            ;;
        --direct)
            FORCE_DIRECT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Check if server is already running
is_server_running() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        return 0
    fi

    if command -v systemctl &>/dev/null && ! $FORCE_DIRECT; then
        if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check if systemd is available and service is installed
use_systemd() {
    if $FORCE_DIRECT; then
        return 1
    fi

    if ! command -v systemctl &>/dev/null; then
        return 1
    fi

    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        return 0
    fi

    return 1
}

# Get file size (cross-platform)
get_file_size() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# Wait for port to be available
wait_for_port() {
    local port="$1"
    local timeout="$2"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if timeout 1 bash -c "echo > /dev/tcp/localhost/${port}" 2>/dev/null; then
            return 0
        fi

        # Alternative check with nc
        if command -v nc &>/dev/null; then
            if nc -z -w1 localhost "$port" 2>/dev/null; then
                return 0
            fi
        fi

        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        # Show progress
        local progress=$((elapsed * 100 / timeout))
        printf "\r           ├─ Waiting for port %s... %d/%ds (%d%%)" "$port" "$elapsed" "$timeout" "$progress"
    done

    echo ""
    return 1
}

# Check RCON connectivity
check_rcon() {
    if [[ -z "$RCON_PASSWORD" ]]; then
        return 1
    fi

    if command -v mcrcon &>/dev/null; then
        if timeout 5 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "list" &>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Main Start Procedure
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Minecraft Server Startup"
    init_steps 4

    # Step 1: Pre-flight checks
    log_step "Pre-flight validation"

    # Check if already running
    if is_server_running; then
        log_substep "Server is already running" "warn"
        log_info "Use 'sudo systemctl restart ${SERVICE_NAME}' to restart"
        exit 0
    fi
    log_substep "Server not running" "ok"

    # Find and validate server JAR
    cd "$SERVER_DIR"
    local jar_file
    jar_file=$(ls mohist-1.20.1-*.jar 2>/dev/null | head -1)

    if [[ -z "$jar_file" ]]; then
        log_substep "Server JAR not found!" "error"
        log_error "Expected mohist-1.20.1-*.jar in ${SERVER_DIR}"
        exit 1
    fi

    local jar_size
    jar_size=$(get_file_size "$jar_file")

    if [[ $jar_size -lt $MIN_JAR_SIZE ]]; then
        log_substep "JAR file too small (${jar_size} bytes) - may be corrupted" "error"
        exit 1
    fi

    local jar_size_mb=$((jar_size / 1048576))
    log_substep "Server JAR: ${jar_file} (${jar_size_mb} MB)" "ok"

    # Check disk space
    local disk_usage
    disk_usage=$(df "${SERVER_DIR}" | tail -1 | awk '{print $5}' | tr -d '%')

    if [[ $disk_usage -gt 95 ]]; then
        log_substep "Disk usage critical: ${disk_usage}%" "error"
        exit 1
    elif [[ $disk_usage -gt 85 ]]; then
        log_substep "Disk usage: ${disk_usage}% (warning)" "warn"
    else
        log_substep "Disk usage: ${disk_usage}%" "ok"
    fi

    # Check launch script
    if [[ ! -f "launch.sh" ]]; then
        log_substep "launch.sh not found!" "error"
        exit 1
    fi

    if [[ ! -x "launch.sh" ]]; then
        chmod +x launch.sh
        log_substep "Made launch.sh executable" "ok"
    else
        log_substep_last "launch.sh ready" "ok"
    fi

    # Step 2: Start server
    log_step "Starting server"

    if use_systemd; then
        log_substep "Using systemd service: ${SERVICE_NAME}.service"

        if ! sudo systemctl start "${SERVICE_NAME}.service"; then
            log_substep_last "Failed to start systemd service" "error"
            exit 1
        fi

        log_substep_last "Systemd service started" "ok"
    else
        log_substep "Using direct launch (no systemd)"

        # Start in background using screen or nohup
        if command -v screen &>/dev/null; then
            screen -dmS minecraft bash -c "cd '$SERVER_DIR' && ./launch.sh"
            log_substep_last "Started in screen session 'minecraft'" "ok"
        else
            nohup ./launch.sh > "${SERVER_DIR}/logs/server.log" 2>&1 &
            log_substep_last "Started with nohup (PID: $!)" "ok"
        fi
    fi

    # Step 3: Health check
    if $NO_WAIT; then
        log_step "Skipping health check (--no-wait)"
        log_substep_last "Server starting in background" "ok"
    else
        log_step "Health check"
        log_substep "Waiting for server to start (timeout: ${STARTUP_TIMEOUT}s)"

        # Wait for game port
        if wait_for_port "$GAME_PORT" "$STARTUP_TIMEOUT"; then
            log_substep "Port ${GAME_PORT} accepting connections" "ok"
        else
            log_substep "Port ${GAME_PORT} not available after ${STARTUP_TIMEOUT}s" "error"
            log_error "Server may have failed to start. Check logs:"
            log_error "  sudo journalctl -u ${SERVICE_NAME} -n 50"
            exit 1
        fi

        # Wait a bit more for RCON to be ready
        sleep 3

        # Check RCON
        if [[ -n "$RCON_PASSWORD" ]]; then
            if check_rcon; then
                log_substep_last "RCON responding on port ${RCON_PORT}" "ok"
            else
                log_substep_last "RCON not responding (may still be initializing)" "warn"
            fi
        else
            log_substep_last "RCON check skipped (password not configured)" "warn"
        fi
    fi

    # Step 4: Final status
    log_step "Verification"

    if is_server_running; then
        log_substep_last "Server is running" "ok"
        print_footer "success" "$(get_elapsed)" "Status: RUNNING"
    else
        log_substep_last "Server may not be running properly" "warn"
        print_footer "success" "$(get_elapsed)" "Status: UNKNOWN"
    fi

    echo ""
    log_info "Useful commands:"
    if use_systemd; then
        echo "  sudo systemctl status ${SERVICE_NAME}   # Check status"
        echo "  sudo journalctl -u ${SERVICE_NAME} -f   # Live logs"
    else
        echo "  screen -r minecraft                     # Attach to console"
        echo "  tail -f ${SERVER_DIR}/logs/latest.log   # View logs"
    fi
}

# Run main function
main "$@"
