#!/bin/bash
# Graceful Minecraft server shutdown with world save
# Uses RCON to send save-all command before stopping

set -e  # Exit on error

# Configuration
RCON_HOST="localhost"
RCON_PORT="25575"
RCON_PASSWORD="29123537"  # From server.properties
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if mcrcon is available
check_rcon_tool() {
    if command -v mcrcon &> /dev/null; then
        echo "mcrcon"
        return 0
    fi

    # Check if rcon-cli is available
    if command -v rcon-cli &> /dev/null; then
        echo "rcon-cli"
        return 0
    fi

    log_warn "No RCON tool found (mcrcon or rcon-cli)"
    log_warn "Install with: brew install mcrcon (macOS) or apt install mcrcon (Linux)"
    log_warn "Skipping graceful save, proceeding with shutdown..."
    echo "none"
    return 1
}

# Send RCON command
send_rcon_command() {
    local command="$1"
    local tool=$(check_rcon_tool)

    if [ "$tool" = "none" ]; then
        return 1
    fi

    if [ "$tool" = "mcrcon" ]; then
        mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "$command" 2>/dev/null || true
    elif [ "$tool" = "rcon-cli" ]; then
        rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "$command" 2>/dev/null || true
    fi
}

# Check if server is running
is_server_running() {
    if pgrep -f "mohist-1.20.1.*\.jar" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Main graceful shutdown procedure
main() {
    log_info "Starting graceful shutdown procedure..."

    # Check if server is running
    if ! is_server_running; then
        log_warn "Server is not running"
        return 0
    fi

    # Send save-all command
    log_info "Sending save-all command to server..."
    send_rcon_command "save-all" || log_warn "Could not send save-all via RCON"

    # Wait for save to complete
    log_info "Waiting for world save to complete..."
    sleep 3

    # Send save-off to prevent further changes
    log_info "Disabling auto-save..."
    send_rcon_command "save-off" || log_warn "Could not send save-off via RCON"

    # Notify players (if any)
    log_info "Notifying players of shutdown..."
    send_rcon_command "say Server is shutting down for maintenance..." || true
    sleep 1

    # Final save
    log_info "Performing final save..."
    send_rcon_command "save-all flush" || true
    sleep 2

    log_info "Graceful shutdown preparation complete"
}

main "$@"
