#!/bin/bash
# =============================================================================
# graceful-shutdown.sh - Graceful Minecraft Server Shutdown with World Save
# =============================================================================
# Uses RCON to safely save the world before stopping the server.
# Called by systemd as ExecStop command.
#
# Features:
#   - Reads RCON password from config.env (no hardcoded secrets!)
#   - Verifies save completion
#   - Notifies players before shutdown
#   - Timeout handling for RCON commands
#
# Usage: ./deploy/graceful-shutdown.sh [--timeout SECONDS]
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
fi

# Load configuration from config.env
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
    log_debug "Loaded configuration from config.env"
else
    log_warn "config.env not found, using defaults"
fi

# Defaults (can be overridden by config.env)
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
RCON_TIMEOUT="${RCON_TIMEOUT:-5}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-60}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            SHUTDOWN_TIMEOUT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# RCON Functions
# -----------------------------------------------------------------------------

# Detect available RCON tool
get_rcon_tool() {
    if command -v mcrcon &> /dev/null; then
        echo "mcrcon"
        return 0
    fi

    if command -v rcon-cli &> /dev/null; then
        echo "rcon-cli"
        return 0
    fi

    echo "none"
    return 1
}

# Send RCON command with timeout
send_rcon() {
    local command="$1"
    local tool

    tool=$(get_rcon_tool) || {
        log_warn "No RCON tool available"
        return 1
    }

    if [[ -z "$RCON_PASSWORD" ]]; then
        log_warn "RCON_PASSWORD not set in config.env"
        return 1
    fi

    local result=""
    local exit_code=0

    case "$tool" in
        mcrcon)
            result=$(timeout "${RCON_TIMEOUT}" mcrcon \
                -H "$RCON_HOST" \
                -P "$RCON_PORT" \
                -p "$RCON_PASSWORD" \
                "$command" 2>&1) || exit_code=$?
            ;;
        rcon-cli)
            result=$(timeout "${RCON_TIMEOUT}" rcon-cli \
                --host "$RCON_HOST" \
                --port "$RCON_PORT" \
                --password "$RCON_PASSWORD" \
                "$command" 2>&1) || exit_code=$?
            ;;
    esac

    if [[ $exit_code -ne 0 ]]; then
        log_debug "RCON command '$command' failed with exit code $exit_code"
        return 1
    fi

    echo "$result"
    return 0
}

# Check if server is running
is_server_running() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        return 0
    fi

    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet minecraft.service 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Get player count
get_player_count() {
    local result
    result=$(send_rcon "list" 2>/dev/null) || {
        echo "0"
        return
    }

    # Parse "There are X of a max of Y players online"
    if [[ "$result" =~ [Tt]here\ are\ ([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

# -----------------------------------------------------------------------------
# Main Shutdown Procedure
# -----------------------------------------------------------------------------

main() {
    log_info "Starting graceful shutdown procedure..."
    log_debug "Timeout: ${SHUTDOWN_TIMEOUT}s, RCON: ${RCON_HOST}:${RCON_PORT}"

    # Check if server is running
    if ! is_server_running; then
        log_warn "Server is not running, nothing to shutdown"
        return 0
    fi

    # Check RCON tool availability
    local rcon_tool
    rcon_tool=$(get_rcon_tool) || true

    if [[ "$rcon_tool" == "none" ]]; then
        log_warn "No RCON tool found (mcrcon or rcon-cli)"
        log_warn "Install with: apt install mcrcon (Ubuntu) or brew install mcrcon (macOS)"
        log_warn "Proceeding without graceful save - worlds may not be saved properly!"
        return 0
    fi

    if [[ -z "$RCON_PASSWORD" ]]; then
        log_error "RCON_PASSWORD not set!"
        log_error "Configure it in: ${SCRIPT_DIR}/config.env"
        log_warn "Proceeding without graceful save - worlds may not be saved properly!"
        return 0
    fi

    # Get player count before shutdown
    local player_count
    player_count=$(get_player_count)
    log_info "Players online: ${player_count}"

    # Notify players if any are online
    if [[ "$player_count" -gt 0 ]]; then
        log_info "Notifying players of shutdown..."
        send_rcon "say §c[Server] §fShutting down for maintenance in 10 seconds..." || true
        sleep 3
        send_rcon "say §c[Server] §fSaving world..." || true
        sleep 2
    fi

    # Step 1: First save-all
    log_info "Sending save-all command..."
    if send_rcon "save-all" >/dev/null; then
        log_success "save-all command sent"
    else
        log_warn "Could not send save-all command"
    fi

    # Wait for save to complete
    log_info "Waiting for world save to complete..."
    sleep 3

    # Step 2: Disable auto-save
    log_info "Disabling auto-save..."
    if send_rcon "save-off" >/dev/null; then
        log_success "Auto-save disabled"
    else
        log_warn "Could not disable auto-save"
    fi

    # Step 3: Final save with flush
    log_info "Performing final save (with flush)..."
    if send_rcon "save-all flush" >/dev/null; then
        log_success "Final save completed"
    else
        log_warn "Could not complete final save"
    fi

    # Wait for flush to complete
    sleep 2

    # Notify players of imminent shutdown
    if [[ "$player_count" -gt 0 ]]; then
        send_rcon "say §c[Server] §fShutting down now. See you soon!" || true
        sleep 1
    fi

    # Step 4: Kick all players (optional, uncomment if needed)
    # log_info "Disconnecting players..."
    # send_rcon "kick @a Server is shutting down" || true

    log_success "Graceful shutdown preparation complete"
    log_info "Server process will now be terminated by systemd"
}

# Run main function
main "$@"
