#!/bin/bash
# =============================================================================
# configure.sh - Interactive Server Configuration Wizard
# =============================================================================
# Configures server.properties from example file with secure password generation
# Usage: ./deploy/configure.sh
# =============================================================================

set -euo pipefail

# Source logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVER_PROPS="${SERVER_DIR}/server.properties"
SERVER_PROPS_EXAMPLE="${SERVER_DIR}/server.properties.example"
CONFIG_ENV="${SCRIPT_DIR}/config.env"
CONFIG_ENV_EXAMPLE="${SCRIPT_DIR}/config.env.example"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Generate a secure random password (16 alphanumeric characters)
generate_password() {
    if command -v openssl &>/dev/null; then
        openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16
    else
        # Fallback using /dev/urandom
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16
    fi
}

# Prompt for RCON password with generation option
# Note: All user-facing output goes to stderr so only the password is captured by command substitution
prompt_password() {
    local generated
    generated=$(generate_password)

    echo "" >&2
    echo -e "${C_CYAN}RCON Password Configuration${C_RESET}" >&2
    echo -e "  ${C_DIM}Generated suggestion:${C_RESET} ${C_GREEN}${generated}${C_RESET}" >&2
    echo "" >&2

    local user_password
    read -r -p "  Enter password (or press Enter to use generated): " user_password

    if [[ -z "$user_password" ]]; then
        echo "$generated"
    else
        # Validate: minimum 8 characters
        if [[ ${#user_password} -lt 8 ]]; then
            log_warn "Password must be at least 8 characters" >&2
            prompt_password
        else
            echo "$user_password"
        fi
    fi
}

# Prompt with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    read -r -p "  ${prompt} [${default}]: " result
    echo "${result:-$default}"
}

# Escape string for use in sed replacement pattern
# Handles: & \ / $ (all sed special chars in replacement)
escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[&/\$]/\\&/g' -e 's/\\/\\\\/g'
}

# Apply configuration to server.properties using sed
apply_to_server_properties() {
    local password="$1"
    local ip="$2"
    local motd="$3"

    # Escape special characters for sed replacement
    local escaped_password
    local escaped_motd
    escaped_password=$(escape_sed_replacement "$password")
    escaped_motd=$(escape_sed_replacement "$motd")

    # Platform-specific sed (macOS vs Linux)
    if [[ "$(get_platform)" == "macos" ]]; then
        sed -i '' \
            -e "s/^rcon\.password=.*/rcon.password=${escaped_password}/" \
            -e "s/^server-ip=.*/server-ip=${ip}/" \
            -e "s/^motd=.*/motd=${escaped_motd}/" \
            "$SERVER_PROPS"
    else
        sed -i \
            -e "s/^rcon\.password=.*/rcon.password=${escaped_password}/" \
            -e "s/^server-ip=.*/server-ip=${ip}/" \
            -e "s/^motd=.*/motd=${escaped_motd}/" \
            "$SERVER_PROPS"
    fi
}

# Sync RCON password to config.env
sync_config_env() {
    local password="$1"

    # Create config.env from example if it doesn't exist
    if [[ ! -f "$CONFIG_ENV" ]]; then
        if [[ -f "$CONFIG_ENV_EXAMPLE" ]]; then
            cp "$CONFIG_ENV_EXAMPLE" "$CONFIG_ENV"
            chmod 600 "$CONFIG_ENV"
            log_substep "Created config.env from example" "ok"
        else
            log_warn "config.env.example not found, skipping config.env sync"
            return 0
        fi
    fi

    # Escape password for sed using shared function
    local escaped_password
    escaped_password=$(escape_sed_replacement "$password")

    # Update RCON_PASSWORD in config.env
    if [[ "$(get_platform)" == "macos" ]]; then
        sed -i '' "s/^RCON_PASSWORD=.*/RCON_PASSWORD=\"${escaped_password}\"/" "$CONFIG_ENV"
    else
        sed -i "s/^RCON_PASSWORD=.*/RCON_PASSWORD=\"${escaped_password}\"/" "$CONFIG_ENV"
    fi

    log_substep "Synchronized RCON password to config.env" "ok"
}

# Check if server.properties needs values
check_needs_configuration() {
    if [[ ! -f "$SERVER_PROPS" ]]; then
        return 0  # Needs configuration
    fi

    # Check if password is still default placeholder
    if grep -q "^rcon\.password=CHANGE$" "$SERVER_PROPS" 2>/dev/null; then
        return 0  # Needs configuration
    fi

    return 1  # Already configured
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    print_header "Minecraft Server Configuration"

    # Step 1: Copy example file if server.properties doesn't exist
    if [[ ! -f "$SERVER_PROPS" ]]; then
        if [[ -f "$SERVER_PROPS_EXAMPLE" ]]; then
            cp "$SERVER_PROPS_EXAMPLE" "$SERVER_PROPS"
            log_success "Created server.properties from example"
        else
            die "server.properties.example not found at: $SERVER_PROPS_EXAMPLE"
        fi
    else
        log_info "Using existing server.properties"
    fi

    # Check if already configured
    if ! check_needs_configuration; then
        echo ""
        if ! confirm "server.properties appears to be configured. Reconfigure?"; then
            log_info "Configuration skipped"
            exit 0
        fi
    fi

    # Step 2: Gather configuration values
    echo ""
    local password
    password=$(prompt_password)

    local ip
    ip=$(prompt_with_default "Server IP" "localhost")

    local motd
    motd=$(prompt_with_default "Message of the Day" "KIBERmax server")

    # Step 3: Apply configuration
    echo ""
    log_info "Applying configuration..."

    apply_to_server_properties "$password" "$ip" "$motd"
    log_substep "Updated server.properties" "ok"

    # Step 4: Sync with config.env
    sync_config_env "$password"

    # Step 5: Summary
    echo ""
    print_separator "Configuration Complete"
    echo -e "  ${C_GREEN}RCON Password:${C_RESET} ${password:0:4}$( printf '*%.0s' {1..8} )"
    echo -e "  ${C_GREEN}Server IP:${C_RESET}     ${ip}"
    echo -e "  ${C_GREEN}MOTD:${C_RESET}          ${motd}"
    echo ""

    log_success "Server configuration complete!"

    # Reminder about config.env
    if [[ -f "$CONFIG_ENV" ]]; then
        echo -e "${C_DIM}Note: RCON password synced to deploy/config.env for deployment scripts${C_RESET}"
    fi
}

main "$@"
