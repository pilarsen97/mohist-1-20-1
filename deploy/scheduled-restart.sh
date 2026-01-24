#!/bin/bash
# =============================================================================
# scheduled-restart.sh - Scheduled Server Restart with Player Warnings
# =============================================================================
# Performs graceful server restart with countdown warnings to players.
# Designed to be used with systemd timer or cron for automated restarts.
#
# Features:
#   - Player warnings via RCON at 10, 5, and 1 minute before restart
#   - Automatic backup before restart
#   - Health verification after restart
#   - Safe failure handling
#
# Usage:
#   ./deploy/scheduled-restart.sh              # Full restart with warnings
#   ./deploy/scheduled-restart.sh --no-backup  # Skip backup
#   ./deploy/scheduled-restart.sh --now        # Immediate restart (no countdown)
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
    print_header() { echo "=== $1 ==="; }
    print_footer() { echo "=== $1 ==="; }
    start_timer() { START_TIME=$(date +%s); }
    get_elapsed() { echo "$(($(date +%s) - START_TIME))s"; }
fi

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
BACKUP_ENABLED=true
IMMEDIATE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-backup)
            BACKUP_ENABLED=false
            shift
            ;;
        --now)
            IMMEDIATE=true
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

# Send message to all players via RCON
broadcast_message() {
    local message="$1"

    if [[ -z "$RCON_PASSWORD" ]]; then
        log_warn "RCON password not configured - cannot send player warnings"
        return 1
    fi

    if ! command -v mcrcon &>/dev/null; then
        log_warn "mcrcon not installed - cannot send player warnings"
        return 1
    fi

    # Use environment variable for password (security)
    export MCRCON_PASS="$RCON_PASSWORD"

    if timeout 5 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" "say ${message}" &>/dev/null; then
        log_info "Broadcast: ${message}"
        return 0
    else
        log_warn "Failed to broadcast message (server may be down)"
        return 1
    fi
}

# Check if server is running
is_running() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; then
        return 0
    elif systemctl is-active --quiet minecraft.service 2>/dev/null; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Main Restart Procedure
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Scheduled Server Restart"

    # Check if server is running
    if ! is_running; then
        log_warn "Server is not running - nothing to restart"
        exit 0
    fi

    # Countdown warnings (unless --now)
    if ! $IMMEDIATE; then
        log_info "Starting countdown warnings..."

        broadcast_message "§6[СИСТЕМА] §eПерезагрузка сервера через 10 минут!"
        sleep 300  # 5 minutes

        broadcast_message "§6[СИСТЕМА] §eПерезагрузка сервера через 5 минут! Сохраните свой прогресс!"
        sleep 240  # 4 minutes

        broadcast_message "§c[СИСТЕМА] §6Перезагрузка сервера через 1 минуту! Выйдите из опасных зон!"
        sleep 50   # 50 seconds

        broadcast_message "§c[СИСТЕМА] §4Перезагрузка через 10 секунд..."
        sleep 10
    else
        log_info "Immediate restart requested - skipping countdown"
    fi

    # Final warning
    broadcast_message "§4[СИСТЕМА] Сервер перезагружается сейчас!"
    sleep 1

    # Backup (if enabled)
    if $BACKUP_ENABLED; then
        log_info "Creating backup before restart..."
        if [[ -x "${SCRIPT_DIR}/backup.sh" ]]; then
            "${SCRIPT_DIR}/backup.sh" --quiet || {
                log_warn "Backup failed - continuing with restart anyway"
            }
        else
            log_warn "backup.sh not found - skipping backup"
        fi
    fi

    # Stop server
    log_info "Stopping server..."
    if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
        "${SCRIPT_DIR}/stop.sh" || {
            log_error "Failed to stop server gracefully"
            exit 1
        }
    else
        log_error "stop.sh not found!"
        exit 1
    fi

    # Wait a bit for clean shutdown
    sleep 5

    # Start server
    log_info "Starting server..."
    if [[ -x "${SCRIPT_DIR}/start.sh" ]]; then
        "${SCRIPT_DIR}/start.sh" || {
            log_error "Failed to start server"
            exit 1
        }
    else
        log_error "start.sh not found!"
        exit 1
    fi

    # Wait for startup
    log_info "Waiting for server to be ready..."
    sleep 30

    # Health check
    if [[ -x "${SCRIPT_DIR}/health-check.sh" ]]; then
        if "${SCRIPT_DIR}/health-check.sh" &>/dev/null; then
            log_success "Server restarted successfully and is healthy"
            broadcast_message "§a[СИСТЕМА] Сервер успешно перезагружен! Добро пожаловать обратно!"
        else
            log_error "Server started but health check failed!"
            exit 1
        fi
    else
        log_warn "health-check.sh not found - cannot verify server health"
    fi

    print_footer "success" "$(get_elapsed)" "Restart completed"
}

# Run main function
main "$@"
