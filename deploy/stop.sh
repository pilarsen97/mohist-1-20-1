#!/bin/bash
# Stop Minecraft server with graceful shutdown

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Perform graceful shutdown (save world)
log_info "Performing graceful shutdown..."
bash "$SCRIPT_DIR/graceful-shutdown.sh"

# Check if running in systemd environment (production)
if command -v systemctl &> /dev/null && systemctl is-active --quiet minecraft.service 2>/dev/null; then
    log_info "Stopping systemd service..."
    sudo systemctl stop minecraft.service
else
    # Development environment - kill process directly
    log_warn "Not running under systemd, killing process directly..."
    pkill -f "mohist-1.20.1.*\.jar" || log_warn "No server process found"
fi

log_info "Server stopped successfully"