#!/bin/bash
# =============================================================================
# backup.sh - Minecraft Server Backup with Verification
# =============================================================================
# Creates timestamped, compressed backups of world files and configuration.
#
# Features:
#   - Compressed tar.gz archives
#   - Backup verification (integrity check)
#   - Automatic rotation (keep last N backups)
#   - Metrics file for Prometheus
#   - Pretty progress logging
#
# Usage:
#   ./deploy/backup.sh              # Create backup
#   ./deploy/backup.sh --list       # List existing backups
#   ./deploy/backup.sh --verify     # Verify last backup integrity
#   ./deploy/backup.sh --compact    # Create single archive (faster)
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
    format_bytes() {
        local bytes="$1"
        if [[ $bytes -ge 1073741824 ]]; then
            echo "$(echo "scale=1; $bytes/1073741824" | bc) GB"
        elif [[ $bytes -ge 1048576 ]]; then
            echo "$(echo "scale=1; $bytes/1048576" | bc) MB"
        else
            echo "$bytes bytes"
        fi
    }
fi

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
BACKUP_DIR="${BACKUP_DIR:-${SERVER_DIR}/backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-6}"
BACKUP_WORLDS="${BACKUP_WORLDS:-world world_nether world_the_end}"
BACKUP_CONFIGS="${BACKUP_CONFIGS:-server.properties bukkit.yml spigot.yml mohist-config/mohist.yml}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="backup_${TIMESTAMP}"

# Flags
COMPACT_MODE=false
VERIFY_ONLY=false
LIST_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list)
            LIST_ONLY=true
            shift
            ;;
        --verify)
            VERIFY_ONLY=true
            shift
            ;;
        --compact)
            COMPACT_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --list       List existing backups"
            echo "  --verify     Verify last backup integrity"
            echo "  --compact    Create single archive (faster)"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Get file size (cross-platform)
get_file_size() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# Get directory size
get_dir_size() {
    local dir="$1"
    du -sb "$dir" 2>/dev/null | cut -f1 || echo "0"
}

# Verify tar archive integrity
verify_archive() {
    local archive="$1"

    if ! tar -tzf "$archive" &>/dev/null; then
        return 1
    fi

    return 0
}

# Update metrics file for Prometheus
update_metrics() {
    local backup_file="$1"
    local metrics_file="${BACKUP_DIR}/.metrics"

    local backup_size
    backup_size=$(get_file_size "$backup_file")
    local backup_timestamp
    backup_timestamp=$(date +%s)

    cat > "$metrics_file" <<EOF
# Minecraft backup metrics
backup_last_timestamp ${backup_timestamp}
backup_last_size_bytes ${backup_size}
backup_count $(ls -1 "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
EOF
}

# -----------------------------------------------------------------------------
# Backup Functions
# -----------------------------------------------------------------------------

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_substep "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
}

# Backup worlds (compact mode - single archive)
backup_compact() {
    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    local items_to_backup=()

    # Collect world directories
    for world in $BACKUP_WORLDS; do
        if [[ -d "${SERVER_DIR}/${world}" ]]; then
            items_to_backup+=("$world")
        fi
    done

    # Collect config files
    for config in $BACKUP_CONFIGS; do
        if [[ -f "${SERVER_DIR}/${config}" ]]; then
            items_to_backup+=("$config")
        elif [[ -d "${SERVER_DIR}/${config}" ]]; then
            items_to_backup+=("$config")
        fi
    done

    if [[ ${#items_to_backup[@]} -eq 0 ]]; then
        log_substep_last "No files to backup!" "error"
        return 1
    fi

    log_substep "Creating archive: ${BACKUP_NAME}.tar.gz"

    # Create archive
    cd "$SERVER_DIR"
    if tar -czf "$backup_file" --warning=no-file-changed \
        -I "gzip -${BACKUP_COMPRESSION}" \
        "${items_to_backup[@]}" 2>/dev/null; then
        log_substep "Archive created successfully" "ok"
    else
        # tar returns 1 if files changed during archive, which is ok
        log_substep "Archive created (some files may have changed)" "warn"
    fi

    # Verify
    log_substep "Verifying archive integrity..."
    if verify_archive "$backup_file"; then
        log_substep "Integrity check passed" "ok"
    else
        log_substep_last "Integrity check FAILED!" "error"
        rm -f "$backup_file"
        return 1
    fi

    # Size info
    local backup_size
    backup_size=$(get_file_size "$backup_file")
    log_substep_last "Size: $(format_bytes $backup_size)" "ok"

    # Update metrics
    update_metrics "$backup_file"

    echo "$backup_file"
}

# Backup worlds (separate archives per world)
backup_separate() {
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    mkdir -p "$backup_path"

    local total_size=0

    # Backup each world
    for world in $BACKUP_WORLDS; do
        if [[ -d "${SERVER_DIR}/${world}" ]]; then
            local world_size
            world_size=$(get_dir_size "${SERVER_DIR}/${world}")
            log_substep "Backing up ${world} ($(format_bytes $world_size))..."

            if tar -czf "${backup_path}/${world}.tar.gz" \
                -I "gzip -${BACKUP_COMPRESSION}" \
                -C "$SERVER_DIR" "$world" 2>/dev/null; then
                log_substep "${world} backed up" "ok"
                total_size=$((total_size + $(get_file_size "${backup_path}/${world}.tar.gz")))
            else
                log_substep "${world} backup had issues" "warn"
            fi
        else
            log_substep "${world} not found, skipping" "warn"
        fi
    done

    # Backup configs
    log_substep "Backing up configuration files..."
    for config in $BACKUP_CONFIGS; do
        if [[ -f "${SERVER_DIR}/${config}" ]]; then
            local config_dir
            config_dir=$(dirname "${backup_path}/${config}")
            mkdir -p "$config_dir"
            cp "${SERVER_DIR}/${config}" "${backup_path}/${config}" 2>/dev/null || true
        elif [[ -d "${SERVER_DIR}/${config}" ]]; then
            cp -r "${SERVER_DIR}/${config}" "${backup_path}/" 2>/dev/null || true
        fi
    done
    log_substep "Configs backed up" "ok"

    # Create metadata
    cat > "${backup_path}/backup_info.txt" <<EOF
Backup created: $(date)
Server directory: ${SERVER_DIR}
Git commit: $(cd "$SERVER_DIR" && git rev-parse HEAD 2>/dev/null || echo 'N/A')
Worlds: ${BACKUP_WORLDS}
Compression level: ${BACKUP_COMPRESSION}
EOF

    # Create final archive from the backup directory
    local final_archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    log_substep "Creating final archive..."

    cd "$BACKUP_DIR"
    tar -czf "$final_archive" -I "gzip -${BACKUP_COMPRESSION}" "$BACKUP_NAME" 2>/dev/null
    rm -rf "$backup_path"

    local final_size
    final_size=$(get_file_size "$final_archive")
    log_substep_last "Final size: $(format_bytes $final_size)" "ok"

    # Update metrics
    update_metrics "$final_archive"

    echo "$final_archive"
}

# Clean old backups
cleanup_old_backups() {
    local backup_count
    backup_count=$(ls -1 "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')

    if [[ $backup_count -gt $BACKUP_RETENTION ]]; then
        log_substep "Cleaning old backups (keeping last $BACKUP_RETENTION)..."

        local to_delete=$((backup_count - BACKUP_RETENTION))
        ls -1t "${BACKUP_DIR}"/backup_*.tar.gz | tail -n "$to_delete" | while read old_backup; do
            log_substep "Removing: $(basename "$old_backup")"
            rm -f "$old_backup"
        done

        log_substep_last "Cleaned $to_delete old backup(s)" "ok"
    else
        log_substep_last "Backup count: $backup_count (retention: $BACKUP_RETENTION)" "ok"
    fi
}

# List existing backups
list_backups() {
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Existing Backups"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    if [[ -d "$BACKUP_DIR" ]] && ls "${BACKUP_DIR}"/backup_*.tar.gz &>/dev/null; then
        printf "  %-30s %12s  %s\n" "FILENAME" "SIZE" "DATE"
        echo "  ───────────────────────────────────────────────────"

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
        local total_size
        total_size=$(du -sb "${BACKUP_DIR}" 2>/dev/null | cut -f1)
        echo "  Total: $total_count backup(s), $(format_bytes $total_size)"
    else
        echo "  No backups found in $BACKUP_DIR"
    fi

    echo ""
}

# Verify last backup
verify_last_backup() {
    echo ""
    log_info "Verifying last backup..."

    local last_backup
    last_backup=$(ls -t "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | head -1)

    if [[ -z "$last_backup" ]]; then
        log_error "No backups found!"
        exit 1
    fi

    log_info "Checking: $(basename "$last_backup")"

    if verify_archive "$last_backup"; then
        log_success "Backup integrity verified!"
        echo ""
        echo "Archive contents:"
        tar -tzf "$last_backup" | head -20
        local file_count
        file_count=$(tar -tzf "$last_backup" | wc -l | tr -d ' ')
        echo "  ... ($file_count total files)"
    else
        log_error "Backup is CORRUPTED!"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Minecraft Server Backup"
    init_steps 3

    # Create backup directory
    create_backup_dir

    # Step 1: Create backup
    log_step "Creating backup"

    local backup_file
    if $COMPACT_MODE; then
        backup_file=$(backup_compact)
    else
        backup_file=$(backup_separate)
    fi

    # Step 2: Cleanup
    log_step "Cleanup"
    cleanup_old_backups

    # Step 3: Summary
    log_step "Summary"

    local backup_size
    backup_size=$(get_file_size "$backup_file")

    log_substep "Backup: $(basename "$backup_file")" "ok"
    log_substep "Size: $(format_bytes $backup_size)" "ok"
    log_substep_last "Location: $BACKUP_DIR" "ok"

    print_footer "success" "$(get_elapsed)" "Size: $(format_bytes $backup_size)"
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

if $LIST_ONLY; then
    list_backups
    exit 0
fi

if $VERIFY_ONLY; then
    verify_last_backup
    exit 0
fi

main "$@"
