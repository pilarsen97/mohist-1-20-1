#!/bin/bash
# =============================================================================
# stop.sh - Stop Minecraft Server with Graceful Shutdown
# =============================================================================
# Stops the Minecraft server with world save and optional backup.
# Works in both development (process kill) and production (systemd) environments.
#
# Features:
#   - Graceful shutdown with world save
#   - Timeout handling with force kill fallback
#   - Optional backup before stop
#   - Player notification
#
# Usage:
#   ./deploy/stop.sh                    # Normal stop
#   ./deploy/stop.sh --timeout 30       # Custom timeout (default: 60s)
#   ./deploy/stop.sh --backup           # Create backup before stopping
#   ./deploy/stop.sh --force            # Skip graceful shutdown, force kill
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
STOP_TIMEOUT="${STOP_TIMEOUT:-60}"
SERVICE_NAME="${SERVICE_NAME:-minecraft}"

# Flags
DO_BACKUP=false
FORCE_KILL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            STOP_TIMEOUT="$2"
            shift 2
            ;;
        --backup)
            DO_BACKUP=true
            shift
            ;;
        --force)
            FORCE_KILL=true
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

# Check if server is running
is_server_running() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        return 0
    fi

    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check if using systemd
use_systemd() {
    if ! command -v systemctl &>/dev/null; then
        return 1
    fi

    if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Wait for server to stop
wait_for_stop() {
    local timeout="$1"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if ! is_server_running; then
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))

        # Show progress every 5 seconds
        if [[ $((elapsed % 5)) -eq 0 ]]; then
            printf "\r           ├─ Waiting for shutdown... %d/%ds" "$elapsed" "$timeout"
        fi
    done

    echo ""
    return 1
}

# Force kill the server
force_kill() {
    log_warn "Force killing server process..."

    # Try SIGTERM first
    pkill -TERM -f "mohist-1.20.1.*\.jar" 2>/dev/null || true
    sleep 2

    # If still running, use SIGKILL
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        pkill -KILL -f "mohist-1.20.1.*\.jar" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Main Stop Procedure
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Minecraft Server Shutdown"

    # Calculate steps
    local total_steps=3
    $DO_BACKUP && total_steps=$((total_steps + 1))
    init_steps $total_steps

    local current_step=0

    # Check if server is running
    if ! is_server_running; then
        log_warn "Server is not running"
        print_footer "success" "$(get_elapsed)" "Status: ALREADY STOPPED"
        exit 0
    fi

    # Step: Backup (optional)
    if $DO_BACKUP; then
        ((current_step++))
        log_step "Creating backup before shutdown"

        if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
            if bash "${SCRIPT_DIR}/backup.sh"; then
                log_substep_last "Backup created successfully" "ok"
            else
                log_substep_last "Backup failed (continuing with shutdown)" "warn"
            fi
        else
            log_substep_last "backup.sh not found" "warn"
        fi
    fi

    # Step: Graceful shutdown
    ((current_step++))
    log_step "Graceful shutdown"

    if $FORCE_KILL; then
        log_substep "Skipping graceful shutdown (--force)" "warn"
    else
        log_substep "Saving world and notifying players..."

        if [[ -f "${SCRIPT_DIR}/graceful-shutdown.sh" ]]; then
            if bash "${SCRIPT_DIR}/graceful-shutdown.sh" --timeout "$STOP_TIMEOUT"; then
                log_substep_last "World saved successfully" "ok"
            else
                log_substep_last "Graceful shutdown had issues (continuing)" "warn"
            fi
        else
            log_substep_last "graceful-shutdown.sh not found" "warn"
        fi
    fi

    # Step: Stop process/service
    ((current_step++))
    log_step "Stopping server"

    if use_systemd; then
        log_substep "Stopping systemd service: ${SERVICE_NAME}.service"

        if sudo systemctl stop "${SERVICE_NAME}.service"; then
            log_substep_last "Systemd service stopped" "ok"
        else
            log_substep "Systemd stop failed, trying force kill..." "warn"
            force_kill
            log_substep_last "Process killed" "ok"
        fi
    else
        log_substep "Stopping process directly..."

        # Send SIGTERM to Java process
        if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
            pkill -TERM -f "mohist-1.20.1.*\.jar" || true

            # Wait for clean shutdown
            if wait_for_stop "$STOP_TIMEOUT"; then
                log_substep_last "Process stopped cleanly" "ok"
            else
                log_substep "Timeout waiting for shutdown" "warn"
                force_kill
                log_substep_last "Process force killed" "ok"
            fi
        else
            log_substep_last "No process found" "ok"
        fi
    fi

    # Step: Verification
    ((current_step++))
    log_step "Verification"

    # Give a moment for process to fully terminate
    sleep 1

    if is_server_running; then
        log_substep_last "Server may still be running!" "error"
        print_footer "failure" "$(get_elapsed)" "Status: MAY BE RUNNING"
        exit 1
    else
        log_substep_last "Server stopped" "ok"
        print_footer "success" "$(get_elapsed)" "Status: STOPPED"
    fi
}

# Run main function
main "$@"
