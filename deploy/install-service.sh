#!/bin/bash
# =============================================================================
# install-service.sh - Install Minecraft Systemd Services
# =============================================================================
# Installs and enables the minecraft.service and minecraft-exporter.service
# Must be run as root or with sudo
#
# Usage: sudo ./deploy/install-service.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}$1${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
}

print_error() {
    echo -e "  ${RED}✗${RESET} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${RESET}"
    echo "Usage: sudo $0"
    exit 1
fi

print_header "Installing Minecraft Systemd Services"

# Check if service files exist
if [[ ! -f "${SCRIPT_DIR}/systemd/minecraft.service" ]]; then
    print_error "minecraft.service not found in ${SCRIPT_DIR}/systemd/"
    exit 1
fi

# Determine user/group for service (the user who ran sudo)
DEPLOY_USER="${SUDO_USER:-$(whoami)}"
DEPLOY_GROUP="$(id -gn "$DEPLOY_USER")"

# Validate user is not root
if [[ "$DEPLOY_USER" == "root" ]]; then
    print_error "Cannot install services for root user!"
    echo -e "       Run as: sudo -u <username> sudo $0"
    echo -e "       Or ensure SUDO_USER is set to a non-root user"
    exit 1
fi

echo -e "${CYAN}Service user: ${BOLD}${DEPLOY_USER}:${DEPLOY_GROUP}${RESET}"

# Stop services if running
echo -e "${CYAN}Stopping existing services...${RESET}"
systemctl stop minecraft-exporter.service 2>/dev/null || true
systemctl stop minecraft.service 2>/dev/null || true
print_ok "Services stopped"

# Update service file paths and user/group
echo -e "${CYAN}Configuring service files...${RESET}"

# Create temporary modified service files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy and modify minecraft.service
# Substitute DEPLOY_USER, DEPLOY_GROUP placeholders
sed -e "s|DEPLOY_USER|${DEPLOY_USER}|g" \
    -e "s|DEPLOY_GROUP|${DEPLOY_GROUP}|g" \
    "${SCRIPT_DIR}/systemd/minecraft.service" > "${TEMP_DIR}/minecraft.service"

# Copy and modify minecraft-exporter.service
sed -e "s|DEPLOY_USER|${DEPLOY_USER}|g" \
    -e "s|DEPLOY_GROUP|${DEPLOY_GROUP}|g" \
    "${SCRIPT_DIR}/systemd/minecraft-exporter.service" > "${TEMP_DIR}/minecraft-exporter.service"

print_ok "User/Group set to ${DEPLOY_USER}:${DEPLOY_GROUP}"

# Install service files
echo -e "${CYAN}Installing service files...${RESET}"
cp "${TEMP_DIR}/minecraft.service" /etc/systemd/system/
cp "${TEMP_DIR}/minecraft-exporter.service" /etc/systemd/system/
print_ok "Service files copied to /etc/systemd/system/"

# Set permissions
chmod 644 /etc/systemd/system/minecraft.service
chmod 644 /etc/systemd/system/minecraft-exporter.service
print_ok "Permissions set"

# Reload systemd
echo -e "${CYAN}Reloading systemd...${RESET}"
systemctl daemon-reload
print_ok "Systemd reloaded"

# Enable services
echo -e "${CYAN}Enabling services...${RESET}"
systemctl enable minecraft.service
systemctl enable minecraft-exporter.service
print_ok "Services enabled for autostart"

# Verify config.env
echo ""
if [[ ! -f "${SCRIPT_DIR}/config.env" ]]; then
    print_warn "config.env not found!"
    echo -e "       Create it from template: cp ${SCRIPT_DIR}/config.env.example ${SCRIPT_DIR}/config.env"
    echo -e "       Then edit and set RCON_PASSWORD"
else
    # Check if RCON password is set
    if grep -q 'RCON_PASSWORD=""' "${SCRIPT_DIR}/config.env"; then
        print_warn "RCON_PASSWORD is empty in config.env"
        echo -e "       Edit ${SCRIPT_DIR}/config.env and set the password"
    else
        print_ok "config.env exists with RCON password"
    fi
fi

# Make scripts executable
echo ""
echo -e "${CYAN}Setting script permissions...${RESET}"
chmod +x "${SERVER_DIR}/launch.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}"/*.sh
chmod +x "${SCRIPT_DIR}/lib"/*.sh 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/prometheus"/*.sh 2>/dev/null || true
print_ok "Scripts made executable"

# Summary
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}${BOLD}Installation Complete!${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}Commands:${RESET}"
echo "  sudo systemctl start minecraft       # Start server"
echo "  sudo systemctl stop minecraft        # Stop server"
echo "  sudo systemctl restart minecraft     # Restart server"
echo "  sudo systemctl status minecraft      # Check status"
echo ""
echo "  sudo journalctl -u minecraft -f      # Live logs"
echo "  sudo journalctl -u minecraft -n 100  # Last 100 lines"
echo ""
echo -e "${BOLD}Service Status:${RESET}"
systemctl is-enabled minecraft.service && echo -e "  minecraft.service:          ${GREEN}enabled${RESET}" || echo -e "  minecraft.service:          ${RED}disabled${RESET}"
systemctl is-enabled minecraft-exporter.service && echo -e "  minecraft-exporter.service: ${GREEN}enabled${RESET}" || echo -e "  minecraft-exporter.service: ${RED}disabled${RESET}"
echo ""
