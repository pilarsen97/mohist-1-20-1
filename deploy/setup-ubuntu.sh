#!/bin/bash
# =============================================================================
# setup-ubuntu.sh - Ubuntu VM Initial Setup for Minecraft Server
# =============================================================================
# Automated first-time setup script for Ubuntu VM on Proxmox
# Run as root or with sudo from a non-root user account
#
# Usage: sudo ./deploy/setup-ubuntu.sh
#
# The server will run under the user who invoked sudo ($SUDO_USER)
# Server files are installed to /opt/minecraft
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# User is determined from who ran sudo (not root!)
DEPLOY_USER="${SUDO_USER:-}"
DEPLOY_GROUP=""
SERVER_DIR="/opt/minecraft"
JAVA_VERSION="21"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}$1${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    echo -e "\n${BLUE}[STEP $1/$2]${RESET} ${BOLD}$3${RESET}"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${RESET}"
        echo "Usage: sudo $0"
        exit 1
    fi
}

check_sudo_user() {
    if [[ -z "$DEPLOY_USER" || "$DEPLOY_USER" == "root" ]]; then
        echo -e "${RED}Error: This script must be run via sudo from a non-root user${RESET}"
        echo "Usage: sudo $0"
        echo ""
        echo "Do not run as: sudo su - root && ./setup-ubuntu.sh"
        echo "Instead run:   sudo ./setup-ubuntu.sh"
        exit 1
    fi
    DEPLOY_GROUP="$(id -gn "$DEPLOY_USER")"
}

# -----------------------------------------------------------------------------
# Main Setup
# -----------------------------------------------------------------------------

# Check root first
check_root
check_sudo_user

print_header "Minecraft Server Ubuntu VM Setup"

echo -e "${CYAN}Configuration:${RESET}"
echo "  User:       ${DEPLOY_USER}:${DEPLOY_GROUP}"
echo "  Server:     ${SERVER_DIR}"
echo "  Java:       OpenJDK ${JAVA_VERSION}"
echo ""

read -p "Continue with setup? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

TOTAL_STEPS=12
CURRENT_STEP=0

# -----------------------------------------------------------------------------
# Step 1: System Update
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Updating system packages"

echo "  Updating package lists..."
apt-get update || { print_error "apt-get update failed"; exit 1; }
echo "  Upgrading packages..."
apt-get upgrade -y || { print_error "apt-get upgrade failed"; exit 1; }
print_ok "System updated"

# -----------------------------------------------------------------------------
# Step 2: Install Dependencies
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Installing dependencies"

echo "  Installing: curl wget git git-lfs screen htop iotop net-tools jq bc unzip ufw build-essential..."
apt-get install -y \
    curl \
    wget \
    git \
    git-lfs \
    screen \
    htop \
    iotop \
    net-tools \
    netcat-openbsd \
    jq \
    bc \
    unzip \
    ufw \
    build-essential || { print_error "Failed to install dependencies"; exit 1; }

print_ok "Dependencies installed"

# -----------------------------------------------------------------------------
# Step 3: Install OpenJDK 17
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Installing OpenJDK ${JAVA_VERSION}"

echo "  Installing openjdk-${JAVA_VERSION}-jdk-headless..."
apt-get install -y openjdk-${JAVA_VERSION}-jdk-headless || { print_error "Failed to install Java"; exit 1; }

# Verify installation
if java -version 2>&1 | grep -q "openjdk version \"${JAVA_VERSION}"; then
    JAVA_VER=$(java -version 2>&1 | head -1)
    print_ok "Java installed: $JAVA_VER"
else
    print_warn "Java installed but version check unclear"
fi

# -----------------------------------------------------------------------------
# Step 4: Install mcrcon
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Installing mcrcon (RCON client)"

if ! command -v mcrcon &> /dev/null; then
    # Clean up any stale build directory from previous attempts
    rm -rf /tmp/mcrcon 2>/dev/null || true

    cd /tmp
    if ! git clone -q https://github.com/Tiiffi/mcrcon.git; then
        print_error "Failed to clone mcrcon repository"
        exit 1
    fi
    cd mcrcon
    if ! make -s; then
        print_error "Failed to build mcrcon (is build-essential installed?)"
        rm -rf /tmp/mcrcon
        exit 1
    fi
    if ! cp mcrcon /usr/local/bin/; then
        print_error "Failed to install mcrcon binary"
        rm -rf /tmp/mcrcon
        exit 1
    fi
    cd /
    rm -rf /tmp/mcrcon
    print_ok "mcrcon installed"
else
    print_ok "mcrcon already installed"
fi

# -----------------------------------------------------------------------------
# Step 5: Create Server Directory
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Creating server directory"

if [[ -d "${SERVER_DIR}" ]]; then
    print_ok "Directory ${SERVER_DIR} already exists"
else
    mkdir -p "${SERVER_DIR}"
    print_ok "Created ${SERVER_DIR}"
fi

# Set ownership to the user who will run the server
chown -R ${DEPLOY_USER}:${DEPLOY_GROUP} "${SERVER_DIR}"
chmod 755 "${SERVER_DIR}"
print_ok "Ownership set to ${DEPLOY_USER}:${DEPLOY_GROUP}"

# -----------------------------------------------------------------------------
# Step 6: Configure Git LFS
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Configuring Git LFS"

# Configure Git LFS for the deploy user
sudo -u "${DEPLOY_USER}" git lfs install 2>/dev/null || git lfs install
print_ok "Git LFS configured for ${DEPLOY_USER}"

# -----------------------------------------------------------------------------
# Step 7: Clone/Update Repository
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Setting up server repository"

if [[ -d "${SERVER_DIR}/.git" ]]; then
    print_ok "Repository already exists at ${SERVER_DIR}"
    echo "  Run './deploy/update.sh' to update"
else
    echo -e "  ${YELLOW}Note:${RESET} Clone the repository to ${SERVER_DIR}:"
    echo "  cd ${SERVER_DIR}"
    echo "  git clone <your-repo-url> ."
    echo "  git lfs pull"
    print_warn "Repository not cloned yet"
fi

# -----------------------------------------------------------------------------
# Step 8: Create Configuration
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Setting up configuration"

if [[ -d "${SERVER_DIR}/deploy" ]]; then
    if [[ ! -f "${SERVER_DIR}/deploy/config.env" ]]; then
        if [[ -f "${SERVER_DIR}/deploy/config.env.example" ]]; then
            cp "${SERVER_DIR}/deploy/config.env.example" "${SERVER_DIR}/deploy/config.env"
            chown ${DEPLOY_USER}:${DEPLOY_GROUP} "${SERVER_DIR}/deploy/config.env"
            chmod 600 "${SERVER_DIR}/deploy/config.env"
            print_warn "config.env created - EDIT IT to set RCON_PASSWORD!"
            echo -e "  ${YELLOW}→${RESET} nano ${SERVER_DIR}/deploy/config.env"
        fi
    else
        print_ok "config.env already exists"
    fi
else
    print_warn "Server directory not ready yet"
fi

# -----------------------------------------------------------------------------
# Step 9: Create Log Directories
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Creating log directories"

mkdir -p "${SERVER_DIR}/logs/deploy" 2>/dev/null || true
mkdir -p "${SERVER_DIR}/backups" 2>/dev/null || true
mkdir -p "${SERVER_DIR}/crash-reports" 2>/dev/null || true

if [[ -d "${SERVER_DIR}" ]]; then
    chown -R ${DEPLOY_USER}:${DEPLOY_GROUP} "${SERVER_DIR}"
    print_ok "Directories created and permissions set"
else
    print_warn "Will create directories after repository clone"
fi

# -----------------------------------------------------------------------------
# Step 10: Install Systemd Services
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Installing systemd services"

if [[ -f "${SERVER_DIR}/deploy/install-service.sh" ]]; then
    # Use install-service.sh which handles user/group substitution
    "${SERVER_DIR}/deploy/install-service.sh"
    print_ok "Services installed via install-service.sh"
else
    print_warn "Service installer not found - will install after repository clone"
    echo "  Run: sudo ${SERVER_DIR}/deploy/install-service.sh"
fi

# -----------------------------------------------------------------------------
# Step 11: Configure Firewall
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Configuring firewall"

# Enable UFW if not enabled
if ! ufw status | grep -q "active"; then
    ufw --force enable
fi

# Allow SSH (if not already)
ufw allow ssh

# Allow Minecraft ports
ufw allow 25565/tcp comment 'Minecraft Game'
ufw allow 25565/udp comment 'Minecraft Query'

# Allow RCON only from localhost (more secure)
# If you need external RCON, uncomment the next line
# ufw allow 25575/tcp comment 'Minecraft RCON'

# Allow Prometheus metrics
ufw allow 9225/tcp comment 'Minecraft Prometheus'

ufw reload
print_ok "Firewall configured (ports 25565, 9225)"

# -----------------------------------------------------------------------------
# Step 12: Final Validation
# -----------------------------------------------------------------------------
((++CURRENT_STEP))
print_step $CURRENT_STEP $TOTAL_STEPS "Validating setup"

echo ""
echo -e "${CYAN}Validation Results:${RESET}"

# Check Java
if command -v java &> /dev/null; then
    print_ok "Java: $(java -version 2>&1 | head -1 | cut -d'"' -f2)"
else
    print_error "Java not found"
fi

# Check mcrcon
if command -v mcrcon &> /dev/null; then
    print_ok "mcrcon: installed"
else
    print_error "mcrcon not found"
fi

# Check git-lfs
if git lfs version &> /dev/null; then
    print_ok "git-lfs: $(git lfs version | head -1)"
else
    print_error "git-lfs not found"
fi

# Check user
if id "${DEPLOY_USER}" &>/dev/null; then
    print_ok "User: ${DEPLOY_USER} (service owner)"
else
    print_error "User: ${DEPLOY_USER} not found"
fi

# Check server directory
if [[ -d "${SERVER_DIR}" ]]; then
    print_ok "Server directory: ${SERVER_DIR}"
else
    print_error "Server directory: ${SERVER_DIR} not found"
fi

# Check services
if systemctl is-enabled minecraft.service &>/dev/null; then
    print_ok "Service: minecraft.service enabled"
else
    print_warn "Service: minecraft.service not enabled yet"
fi

# Check firewall
if ufw status | grep -q "25565"; then
    print_ok "Firewall: port 25565 open"
else
    print_warn "Firewall: port 25565 not configured"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}${BOLD}Setup Complete!${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}Next Steps:${RESET}"
echo ""

if [[ ! -d "${SERVER_DIR}/.git" ]]; then
    echo "1. Clone the repository:"
    echo "   cd ${SERVER_DIR}"
    echo "   git clone <your-repo-url> ."
    echo "   git lfs pull"
    echo ""
    echo "2. Configure RCON password:"
    echo "   cp deploy/config.env.example deploy/config.env"
    echo "   nano deploy/config.env  # Set RCON_PASSWORD"
    echo ""
    echo "3. Install services:"
    echo "   sudo ./deploy/install-service.sh"
    echo ""
    echo "4. Start the server:"
    echo "   sudo systemctl start minecraft"
else
    echo "1. Configure RCON password (if not done):"
    echo "   nano ${SERVER_DIR}/deploy/config.env"
    echo ""
    echo "2. Start the server:"
    echo "   sudo systemctl start minecraft"
    echo ""
    echo "3. Check status:"
    echo "   sudo systemctl status minecraft"
    echo "   sudo journalctl -u minecraft -f"
fi

echo ""
echo -e "${CYAN}Useful Commands:${RESET}"
echo "  sudo systemctl status minecraft     # Check status"
echo "  sudo systemctl start minecraft      # Start server"
echo "  sudo systemctl stop minecraft       # Stop server"
echo "  sudo systemctl restart minecraft    # Restart server"
echo "  sudo journalctl -u minecraft -f     # Live logs"
echo ""
