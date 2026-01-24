#!/bin/bash
# =============================================================================
# restore.sh - Minecraft Server World/Config Restore
# =============================================================================
# Restores world files and configuration from backup archives created by backup.sh.
#
# Features:
#   - Restore from specific backup or latest
#   - Pre-restore validation (integrity check)
#   - Automatic server stop/start
#   - Safety backup before restore
#   - Dry-run mode
#
# Usage:
#   ./deploy/restore.sh                    # Restore from latest backup
#   ./deploy/restore.sh --latest           # Same as above
#   ./deploy/restore.sh backup_file.tar.gz # Restore specific backup
#   ./deploy/restore.sh --list             # List available backups
#   ./deploy/restore.sh --dry-run          # Show what would be restored
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
    format_bytes() { echo "$1 bytes"; }
    get_file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo "0"; }
    is_server_running() { pgrep -f "mohist-1.20.1.*\.jar" > /dev/null 2>&1; }
fi

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
BACKUP_DIR="${BACKUP_DIR:-${SERVER_DIR}/backups}"
BACKUP_WORLDS="${BACKUP_WORLDS:-world world_nether world_the_end}"
BACKUP_CONFIGS="${BACKUP_CONFIGS:-server.properties bukkit.yml spigot.yml mohist-config/mohist.yml}"
SERVICE_NAME="${SERVICE_NAME:-minecraft}"

# Flags
DRY_RUN=false
FORCE=false
NO_START=false
LIST_ONLY=false
BACKUP_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --latest)
            BACKUP_FILE="latest"
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-start)
            NO_START=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [BACKUP_FILE]"
            echo ""
            echo "Arguments:"
            echo "  BACKUP_FILE    Path to backup archive or 'latest'"
            echo ""
            echo "Options:"
            echo "  --latest       Restore from most recent backup"
            echo "  --list         List available backups"
            echo "  --dry-run      Show what would be restored without doing it"
            echo "  --force        Skip confirmation prompts"
            echo "  --no-start     Don't start server after restore"
            echo "  --help         Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --latest                      # Restore latest backup"
            echo "  $0 backups/backup_20250108.tar.gz  # Restore specific backup"
            echo "  $0 --dry-run --latest            # Preview restore"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
# Note: format_bytes() and get_file_size() are in lib/logging.sh

# Verify tar archive integrity
verify_archive() {
    local archive="$1"
    tar -tzf "$archive" &>/dev/null
}

# List existing backups
list_backups() {
    echo ""
    echo "==============================================================="
    echo "  Available Backups"
    echo "==============================================================="
    echo ""

    if [[ -d "$BACKUP_DIR" ]] && ls "${BACKUP_DIR}"/backup_*.tar.gz &>/dev/null 2>&1; then
        printf "  %-30s %12s  %s\n" "FILENAME" "SIZE" "DATE"
        echo "  ─────────────────────────────────────────────────────"

        ls -lt "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | while read -r _ _ _ _ size _ month day time filename; do
            local name
            name=$(basename "$filename")
            local formatted_size
            formatted_size=$(format_bytes "$size")
            printf "  %-30s %12s  %s %s %s\n" "$name" "$formatted_size" "$month" "$day" "$time"
        done

        echo ""
        local total_count
        total_count=$(ls -1 "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        echo "  Total: $total_count backup(s) available"
        echo ""
        echo "  To restore: $0 --latest"
        echo "              $0 backups/backup_XXXXXXXX_XXXXXX.tar.gz"
    else
        echo "  No backups found in $BACKUP_DIR"
        echo ""
        echo "  Create a backup first: ./deploy/backup.sh"
    fi

    echo ""
}

# Find latest backup
find_latest_backup() {
    ls -t "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | head -1
}

# Stop server gracefully
stop_server() {
    if is_server_running; then
        log_substep "Stopping server..."

        if [[ -x "${SCRIPT_DIR}/graceful-shutdown.sh" ]]; then
            "${SCRIPT_DIR}/graceful-shutdown.sh" --timeout 60 || true
        elif [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
            "${SCRIPT_DIR}/stop.sh" || true
        else
            # Fallback: direct systemctl
            if command -v systemctl &>/dev/null; then
                sudo systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
            fi
        fi

        # Wait for server to stop
        local timeout=30
        while is_server_running && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done

        if is_server_running; then
            log_substep "Server still running after timeout" "warn"
            return 1
        fi

        log_substep "Server stopped" "ok"
    else
        log_substep "Server not running" "ok"
    fi
    return 0
}

# Start server
start_server() {
    if $NO_START; then
        log_substep "Skipping server start (--no-start)" "ok"
        return 0
    fi

    log_substep "Starting server..."

    if [[ -x "${SCRIPT_DIR}/start.sh" ]]; then
        "${SCRIPT_DIR}/start.sh" --no-wait || true
    elif command -v systemctl &>/dev/null; then
        sudo systemctl start "${SERVICE_NAME}.service" 2>/dev/null || true
    fi

    # Wait a moment for startup
    sleep 3

    if is_server_running; then
        log_substep "Server started" "ok"
    else
        log_substep "Server may not have started properly" "warn"
    fi
}

# Create safety backup before restore
create_safety_backup() {
    local safety_dir="${BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S)"

    log_substep "Creating safety backup..."
    mkdir -p "$safety_dir"

    # Backup current worlds
    for world in $BACKUP_WORLDS; do
        if [[ -d "${SERVER_DIR}/${world}" ]]; then
            cp -r "${SERVER_DIR}/${world}" "${safety_dir}/" 2>/dev/null || true
        fi
    done

    log_substep "Safety backup: $safety_dir" "ok"
    echo "$safety_dir"
}

# Detect backup format (compact vs separate)
detect_backup_format() {
    local archive="$1"

    # Check if archive contains nested directory with .tar.gz files
    if tar -tzf "$archive" 2>/dev/null | grep -q '\.tar\.gz$'; then
        echo "separate"
    else
        echo "compact"
    fi
}

# Restore from compact backup (direct world/config files)
restore_compact() {
    local archive="$1"

    log_substep "Extracting to server directory..."

    if $DRY_RUN; then
        log_substep "[DRY-RUN] Would extract to: $SERVER_DIR"
        tar -tzf "$archive" | head -20
        return 0
    fi

    cd "$SERVER_DIR"
    tar -xzf "$archive" --overwrite

    log_substep "Extraction complete" "ok"
}

# Restore from separate backup (nested archives)
restore_separate() {
    local archive="$1"
    local temp_dir="${BACKUP_DIR}/.restore_temp_$$"

    log_substep "Extracting backup structure..."

    if $DRY_RUN; then
        log_substep "[DRY-RUN] Would extract nested archives"
        tar -tzf "$archive" | head -20
        return 0
    fi

    # Extract outer archive to temp dir
    mkdir -p "$temp_dir"
    tar -xzf "$archive" -C "$temp_dir"

    # Find the backup directory inside
    local backup_subdir
    backup_subdir=$(ls -d "${temp_dir}"/backup_* 2>/dev/null | head -1)

    if [[ -z "$backup_subdir" ]]; then
        log_substep "Invalid backup structure" "error"
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract each world archive
    for world in $BACKUP_WORLDS; do
        local world_archive="${backup_subdir}/${world}.tar.gz"
        if [[ -f "$world_archive" ]]; then
            log_substep "Restoring ${world}..."

            # Remove existing world
            rm -rf "${SERVER_DIR:?}/${world}"

            # Extract world
            tar -xzf "$world_archive" -C "$SERVER_DIR"
            log_substep "${world} restored" "ok"
        else
            log_substep "${world} not in backup" "warn"
        fi
    done

    # Restore configs
    log_substep "Restoring configuration files..."
    for config in $BACKUP_CONFIGS; do
        if [[ -f "${backup_subdir}/${config}" ]]; then
            local config_dir
            config_dir=$(dirname "${SERVER_DIR}/${config}")
            mkdir -p "$config_dir"
            cp "${backup_subdir}/${config}" "${SERVER_DIR}/${config}"
        elif [[ -d "${backup_subdir}/${config}" ]]; then
            cp -r "${backup_subdir}/${config}" "${SERVER_DIR}/"
        fi
    done
    log_substep "Configs restored" "ok"

    # Show backup info if available
    if [[ -f "${backup_subdir}/backup_info.txt" ]]; then
        log_substep "Backup info:"
        cat "${backup_subdir}/backup_info.txt" | while read line; do
            echo "           $line"
        done
    fi

    # Cleanup
    rm -rf "$temp_dir"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Minecraft Server Restore"
    init_steps 5

    # Resolve backup file
    if [[ -z "$BACKUP_FILE" ]] || [[ "$BACKUP_FILE" == "latest" ]]; then
        BACKUP_FILE=$(find_latest_backup)
        if [[ -z "$BACKUP_FILE" ]]; then
            log_error "No backups found in $BACKUP_DIR"
            echo "Create a backup first: ./deploy/backup.sh"
            exit 1
        fi
        log_info "Using latest backup: $(basename "$BACKUP_FILE")"
    fi

    # Resolve relative path
    if [[ ! -f "$BACKUP_FILE" ]]; then
        # Try relative to backup dir
        if [[ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
            BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
        # Try relative to server dir
        elif [[ -f "${SERVER_DIR}/${BACKUP_FILE}" ]]; then
            BACKUP_FILE="${SERVER_DIR}/${BACKUP_FILE}"
        else
            log_error "Backup file not found: $BACKUP_FILE"
            exit 1
        fi
    fi

    local backup_size
    backup_size=$(get_file_size "$BACKUP_FILE")

    # Step 1: Validate backup
    log_step "Validating backup"

    log_substep "File: $(basename "$BACKUP_FILE")"
    log_substep "Size: $(format_bytes $backup_size)"

    if ! verify_archive "$BACKUP_FILE"; then
        log_substep_last "Backup integrity check FAILED!" "error"
        exit 1
    fi
    log_substep "Integrity check passed" "ok"

    # Detect format
    local backup_format
    backup_format=$(detect_backup_format "$BACKUP_FILE")
    log_substep_last "Format: ${backup_format}" "ok"

    # Step 2: Confirmation
    log_step "Confirmation"

    if $DRY_RUN; then
        log_substep "[DRY-RUN MODE] No changes will be made" "warn"
    fi

    log_substep "Worlds to restore: ${BACKUP_WORLDS}"
    log_substep "Configs to restore: ${BACKUP_CONFIGS}"

    if ! $FORCE && ! $DRY_RUN; then
        echo ""
        read -r -p "$(echo -e "\033[1;33mRestore will OVERWRITE existing worlds! Continue? [y/N]\033[0m ")" response
        if [[ ! "$response" =~ ^[yY]$ ]]; then
            log_info "Restore cancelled."
            exit 0
        fi
    fi
    log_substep_last "Proceeding with restore" "ok"

    # Step 3: Prepare
    log_step "Preparation"

    if ! $DRY_RUN; then
        # Stop server
        if ! stop_server; then
            log_error "Could not stop server safely"
            exit 1
        fi

        # Create safety backup
        create_safety_backup
    else
        log_substep "[DRY-RUN] Would stop server"
        log_substep "[DRY-RUN] Would create safety backup"
    fi

    # Step 4: Restore
    log_step "Restoring data"

    if [[ "$backup_format" == "compact" ]]; then
        restore_compact "$BACKUP_FILE"
    else
        restore_separate "$BACKUP_FILE"
    fi

    # Step 5: Finalize
    log_step "Finalization"

    if ! $DRY_RUN; then
        start_server
    else
        log_substep "[DRY-RUN] Would start server"
    fi

    log_substep_last "Restore complete!" "ok"

    if $DRY_RUN; then
        print_footer "success" "$(get_elapsed)" "DRY-RUN - No changes made"
    else
        print_footer "success" "$(get_elapsed)" "Restored from: $(basename "$BACKUP_FILE")"
    fi
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

if $LIST_ONLY; then
    list_backups
    exit 0
fi

# Default to latest if no backup specified
if [[ -z "$BACKUP_FILE" ]]; then
    BACKUP_FILE="latest"
fi

main "$@"
