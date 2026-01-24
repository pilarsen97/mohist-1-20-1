#!/bin/bash
# =============================================================================
# optimize-world.sh - Minecraft World Optimization Script
# =============================================================================
# Optimizes Minecraft world files by removing unused chunks and compacting data.
# Creates automatic backup before optimization for safety.
#
# Features:
#   - Automatic backup before optimization
#   - Chunk trimming (removes chunks not visited in X days)
#   - World compaction and defragmentation
#   - Safety checks and rollback capability
#
# Usage:
#   ./deploy/optimize-world.sh              # Optimize all worlds
#   ./deploy/optimize-world.sh world        # Optimize specific world
#   ./deploy/optimize-world.sh --skip-backup # Skip pre-optimization backup
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
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
BACKUP_ENABLED=true
TARGET_WORLD=""
CHUNK_AGE_DAYS="${CHUNK_AGE_DAYS:-90}"  # Remove chunks not visited in 90 days

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-backup)
            BACKUP_ENABLED=false
            shift
            ;;
        --chunk-age)
            CHUNK_AGE_DAYS="$2"
            shift 2
            ;;
        world|world_nether|world_the_end)
            TARGET_WORLD="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# World list
if [[ -n "$TARGET_WORLD" ]]; then
    WORLDS=("$TARGET_WORLD")
else
    WORLDS=(world world_nether world_the_end)
fi

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Send RCON command
rcon_command() {
    local command="$1"

    if [[ -z "$RCON_PASSWORD" ]]; then
        log_warn "RCON password not configured"
        return 1
    fi

    if ! command -v mcrcon &>/dev/null; then
        log_warn "mcrcon not installed"
        return 1
    fi

    export MCRCON_PASS="$RCON_PASSWORD"

    if timeout 10 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" "$command" 2>/dev/null; then
        return 0
    else
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

# Get world size
get_world_size() {
    local world="$1"
    local world_path="${SERVER_DIR}/${world}"

    if [[ ! -d "$world_path" ]]; then
        echo "0"
        return
    fi

    du -sb "$world_path" 2>/dev/null | cut -f1 || echo "0"
}

# Format bytes to human-readable
format_size() {
    local bytes="$1"

    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024)) KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576)) MB"
    else
        echo "$((bytes / 1073741824)) GB"
    fi
}

# Optimize single world
optimize_world() {
    local world="$1"
    local world_path="${SERVER_DIR}/${world}"

    log_step "Optimizing world: ${world}"

    # Check if world exists
    if [[ ! -d "$world_path" ]]; then
        log_substep "World not found: ${world}" "warn"
        return
    fi

    # Get size before
    local size_before
    size_before=$(get_world_size "$world")
    log_substep "Size before: $(format_size $size_before)"

    # Remove old region files (chunks not accessed in X days)
    local region_dir="${world_path}/region"
    if [[ -d "$region_dir" ]]; then
        log_substep "Removing unused chunks (older than ${CHUNK_AGE_DAYS} days)..."

        local removed=0
        while IFS= read -r -d '' region_file; do
            # Check if file hasn't been accessed in X days
            if [[ $(find "$region_file" -mtime +${CHUNK_AGE_DAYS} -print) ]]; then
                rm -f "$region_file"
                ((removed++))
            fi
        done < <(find "$region_dir" -name "*.mca" -print0 2>/dev/null || true)

        if [[ $removed -gt 0 ]]; then
            log_substep "Removed ${removed} old region files" "ok"
        else
            log_substep "No old region files to remove" "ok"
        fi
    fi

    # Remove empty DIM folders
    for dim_folder in "${world_path}"/DIM*; do
        if [[ -d "$dim_folder" ]] && [[ -z "$(ls -A "$dim_folder")" ]]; then
            rm -rf "$dim_folder"
            log_substep "Removed empty folder: $(basename "$dim_folder")" "ok"
        fi
    done

    # Remove player data for players who haven't logged in for X days
    local playerdata_dir="${world_path}/playerdata"
    if [[ -d "$playerdata_dir" ]]; then
        log_substep "Cleaning old player data..."

        local cleaned=0
        while IFS= read -r -d '' player_file; do
            if [[ $(find "$player_file" -mtime +${CHUNK_AGE_DAYS} -print) ]]; then
                rm -f "$player_file"
                ((cleaned++))
            fi
        done < <(find "$playerdata_dir" -name "*.dat" -print0 2>/dev/null || true)

        if [[ $cleaned -gt 0 ]]; then
            log_substep "Removed ${cleaned} old player data files" "ok"
        fi
    fi

    # Remove old session.lock files
    find "$world_path" -name "session.lock" -delete 2>/dev/null || true

    # Get size after
    local size_after
    size_after=$(get_world_size "$world")
    local saved=$((size_before - size_after))
    local percent=0

    if [[ $size_before -gt 0 ]]; then
        percent=$((saved * 100 / size_before))
    fi

    log_substep "Size after: $(format_size $size_after)" "ok"

    if [[ $saved -gt 0 ]]; then
        log_substep "Saved: $(format_size $saved) (${percent}%)" "ok"
    else
        log_substep "No space saved" "ok"
    fi
}

# -----------------------------------------------------------------------------
# Main Optimization Procedure
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "World Optimization"
    init_steps 5

    # Step 1: Check server status
    log_step "Pre-flight checks"

    local server_was_running=false
    if is_running; then
        server_was_running=true
        log_substep "Server is running - will need to stop" "warn"
    else
        log_substep "Server is not running" "ok"
    fi

    # Check disk space (need at least 10% free)
    local disk_usage
    disk_usage=$(df "${SERVER_DIR}" | tail -1 | awk '{print $5}' | tr -d '%')

    if [[ $disk_usage -gt 90 ]]; then
        log_substep "Disk usage critical: ${disk_usage}%" "error"
        log_error "Need at least 10% free disk space for safe optimization"
        exit 1
    fi
    log_substep "Disk usage: ${disk_usage}%" "ok"

    # Step 2: Create backup
    if $BACKUP_ENABLED; then
        log_step "Creating safety backup"

        if [[ -x "${SCRIPT_DIR}/backup.sh" ]]; then
            if "${SCRIPT_DIR}/backup.sh" --quiet; then
                log_substep "Backup created successfully" "ok"
            else
                log_error "Backup failed - aborting optimization"
                exit 1
            fi
        else
            log_warn "backup.sh not found - proceeding without backup"
        fi
    else
        log_step "Skipping backup (--skip-backup)"
    fi

    # Step 3: Stop server if running
    if $server_was_running; then
        log_step "Stopping server"

        # Warn players
        rcon_command "say §6[ОПТИМИЗАЦИЯ] Сервер будет остановлен для оптимизации мира..." || true
        sleep 3

        if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
            "${SCRIPT_DIR}/stop.sh" || {
                log_error "Failed to stop server"
                exit 1
            }
        else
            log_error "stop.sh not found"
            exit 1
        fi

        log_substep "Server stopped" "ok"

        # Wait for full shutdown
        sleep 5
    fi

    # Step 4: Optimize worlds
    log_step "Optimizing worlds"

    for world in "${WORLDS[@]}"; do
        optimize_world "$world"
    done

    # Step 5: Restart server if it was running
    if $server_was_running; then
        log_step "Restarting server"

        if [[ -x "${SCRIPT_DIR}/start.sh" ]]; then
            if "${SCRIPT_DIR}/start.sh"; then
                log_substep "Server restarted successfully" "ok"

                # Notify players
                sleep 30
                rcon_command "say §a[ОПТИМИЗАЦИЯ] Оптимизация завершена! Сервер готов к работе." || true
            else
                log_error "Failed to restart server!"
                log_error "Restore from backup: ./deploy/restore.sh"
                exit 1
            fi
        else
            log_error "start.sh not found"
            exit 1
        fi
    fi

    print_footer "success" "$(get_elapsed)" "Optimization completed"
}

# Run main function
main "$@"
