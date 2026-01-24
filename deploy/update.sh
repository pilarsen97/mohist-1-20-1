#!/bin/bash
# =============================================================================
# update.sh - Complete Server Update Procedure
# =============================================================================
# Full automated update with safety checks, backup, deploy, and rollback.
#
# Features:
#   - Disk space verification before backup
#   - Player notification (maintenance mode)
#   - Git-based deployment with rollback
#   - Health check after startup
#   - Detailed progress logging with timestamps
#
# Usage:
#   ./deploy/update.sh                    # Normal update
#   ./deploy/update.sh --skip-backup      # Skip backup step
#   ./deploy/update.sh --no-start         # Update but don't start server
#   ./deploy/update.sh --dry-run          # Show what would be done
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
fi

# Load configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Defaults
SERVICE_NAME="${SERVICE_NAME:-minecraft}"
MIN_JAR_SIZE="${MIN_JAR_SIZE:-100000000}"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
MIN_DISK_FREE_GB="${MIN_DISK_FREE_GB:-5}"

# Flags
SKIP_BACKUP=false
NO_START=false
DRY_RUN=false

# Rollback info
PREVIOUS_COMMIT=""
BACKUP_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --no-start)
            NO_START=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
# Note: format_bytes() and get_file_size() are in lib/logging.sh

# Get available disk space in bytes
get_disk_free() {
    df -B1 "${SERVER_DIR}" 2>/dev/null | tail -1 | awk '{print $4}'
}

# Get disk usage percentage
get_disk_usage() {
    df "${SERVER_DIR}" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%'
}

# is_server_running() - now in lib/logging.sh

# Send RCON command
send_rcon() {
    local command="$1"

    if [[ -z "$RCON_PASSWORD" ]]; then
        return 1
    fi

    if command -v mcrcon &>/dev/null; then
        timeout 5 mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "$command" 2>/dev/null || true
    fi
}

# Rollback function
rollback() {
    log_error "Update failed! Starting rollback..."

    if [[ -n "$PREVIOUS_COMMIT" ]]; then
        log_warn "Rolling back to: ${PREVIOUS_COMMIT:0:8}"
        cd "$SERVER_DIR"
        git checkout --force "$PREVIOUS_COMMIT" 2>/dev/null || log_error "Git rollback failed!"
    fi

    # Try to start server anyway
    if ! $NO_START; then
        log_warn "Attempting to start server after rollback..."
        bash "${SCRIPT_DIR}/start.sh" --no-wait || log_error "Failed to start server!"
    fi

    exit 1
}

# -----------------------------------------------------------------------------
# Main Update Procedure
# -----------------------------------------------------------------------------

main() {
    start_timer
    print_header "Minecraft Server Update"

    # Calculate steps
    local total_steps=5
    $SKIP_BACKUP && total_steps=$((total_steps - 1))
    $NO_START && total_steps=$((total_steps - 1))
    init_steps $total_steps

    local current_step=0

    if $DRY_RUN; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    cd "$SERVER_DIR"

    # Save current commit for rollback
    PREVIOUS_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
    log_info "Current commit: ${PREVIOUS_COMMIT:0:8}"

    # Pre-flight checks
    log_info "Running pre-flight checks..."

    # Check disk space
    local disk_free
    disk_free=$(get_disk_free)
    local disk_free_gb=$((disk_free / 1073741824))
    local disk_usage
    disk_usage=$(get_disk_usage)

    if [[ $disk_free_gb -lt $MIN_DISK_FREE_GB ]]; then
        log_error "Not enough disk space! Free: ${disk_free_gb}GB, Required: ${MIN_DISK_FREE_GB}GB"
        exit 1
    fi
    log_substep "Disk space: ${disk_free_gb}GB free (${disk_usage}% used)" "ok"

    # Check if Git repo is clean
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        log_warn "Working directory has uncommitted changes"
        log_substep "Some files may be overwritten during deploy" "warn"
    else
        log_substep "Git working directory clean" "ok"
    fi

    echo ""

    # Step 1: Stop server gracefully
    ((current_step++))
    log_step "Stopping server"

    if is_server_running; then
        # Notify players
        if [[ -n "$RCON_PASSWORD" ]]; then
            log_substep "Notifying players of maintenance..."
            send_rcon "say §6[Maintenance] §fServer update starting in 30 seconds..." || true
            $DRY_RUN || sleep 5
            send_rcon "say §6[Maintenance] §fServer will restart shortly..." || true
        fi

        log_substep "Stopping server..."

        if ! $DRY_RUN; then
            if ! bash "${SCRIPT_DIR}/stop.sh"; then
                log_substep_last "Failed to stop server gracefully" "error"
                exit 1
            fi
            sleep 2
        fi

        log_substep_last "Server stopped" "ok"
    else
        log_substep_last "Server was not running" "ok"
    fi

    # Step 2: Create backup (unless skipped)
    if ! $SKIP_BACKUP; then
        ((current_step++))
        log_step "Creating backup"

        log_substep "Running backup script..."

        if ! $DRY_RUN; then
            if bash "${SCRIPT_DIR}/backup.sh"; then
                # Get latest backup file for info
                BACKUP_FILE=$(ls -t "${SERVER_DIR}/backups"/backup_*.tar.gz 2>/dev/null | head -1)
                if [[ -n "$BACKUP_FILE" ]]; then
                    local backup_size
                    backup_size=$(get_file_size "$BACKUP_FILE")
                    log_substep_last "Backup created: $(basename "$BACKUP_FILE") ($(format_bytes $backup_size))" "ok"
                else
                    log_substep_last "Backup completed" "ok"
                fi
            else
                log_substep_last "Backup failed (continuing anyway)" "warn"
            fi
        else
            log_substep_last "Would create backup" "ok"
        fi
    fi

    # Step 3: Deploy updates
    ((current_step++))
    log_step "Deploying from Git"

    log_substep "Fetching latest changes..."

    if ! $DRY_RUN; then
        if ! bash "${SCRIPT_DIR}/deploy.sh"; then
            log_substep_last "Deploy failed!" "error"
            rollback
        fi
    fi

    # Show what changed
    local new_commit
    new_commit=$(git rev-parse HEAD 2>/dev/null || echo "")

    if [[ "$new_commit" != "$PREVIOUS_COMMIT" ]]; then
        local commit_count
        commit_count=$(git rev-list --count "${PREVIOUS_COMMIT}..${new_commit}" 2>/dev/null || echo "?")
        log_substep "Updated: ${PREVIOUS_COMMIT:0:8} → ${new_commit:0:8} (${commit_count} commits)" "ok"
    else
        log_substep "Already up to date" "ok"
    fi

    log_substep_last "Deploy complete" "ok"

    # Step 4: Validate deployment
    ((current_step++))
    log_step "Validating deployment"

    # Find and check server JAR
    local jar_file
    jar_file=$(ls mohist-1.20.1-*.jar 2>/dev/null | head -1)

    if [[ -z "$jar_file" ]]; then
        log_substep_last "Server JAR not found!" "error"
        rollback
    fi

    local jar_size
    jar_size=$(get_file_size "$jar_file")

    if [[ $jar_size -lt $MIN_JAR_SIZE ]]; then
        log_substep "JAR size: ${jar_size} bytes (expected >${MIN_JAR_SIZE})" "error"
        log_substep_last "Server JAR may be corrupted!" "error"
        rollback
    fi

    local jar_size_mb=$((jar_size / 1048576))
    log_substep "Server JAR: ${jar_file} (${jar_size_mb} MB)" "ok"

    # Check essential config files
    local configs_ok=true
    for config in server.properties bukkit.yml spigot.yml; do
        if [[ ! -f "$config" ]]; then
            log_substep "Missing: $config" "warn"
            configs_ok=false
        fi
    done

    if $configs_ok; then
        log_substep "Config files present" "ok"
    fi

    log_substep_last "Validation passed" "ok"

    # Step 5: Start server (unless skipped)
    if ! $NO_START; then
        ((current_step++))
        log_step "Starting server"

        log_substep "Launching server..."

        if ! $DRY_RUN; then
            if ! bash "${SCRIPT_DIR}/start.sh"; then
                log_substep_last "Failed to start server!" "error"
                rollback
            fi

            # Health verification after start
            log_substep "Waiting for server initialization (30s)..."
            sleep 30

            if [[ -x "${SCRIPT_DIR}/health-check.sh" ]]; then
                log_substep "Verifying server health..."
                if bash "${SCRIPT_DIR}/health-check.sh" --quiet 2>/dev/null; then
                    log_substep "Server health verified" "ok"
                else
                    log_warn "Server started but health check failed - verify manually"
                fi
            fi
        fi

        log_substep_last "Server started" "ok"
    fi

    # Summary
    echo ""

    local new_commit_short="${new_commit:0:8}"
    local prev_commit_short="${PREVIOUS_COMMIT:0:8}"
    local backup_info=""

    if [[ -n "$BACKUP_FILE" ]]; then
        backup_info="Backup: $(basename "$BACKUP_FILE")"
    fi

    if $DRY_RUN; then
        print_footer "success" "$(get_elapsed)" "DRY RUN - No changes made"
    else
        local status="RUNNING"
        $NO_START && status="STOPPED"
        print_footer "success" "$(get_elapsed)" "Status: $status | $prev_commit_short → $new_commit_short"
    fi

    echo ""
    log_info "Commits: ${prev_commit_short} → ${new_commit_short}"
    [[ -n "$backup_info" ]] && log_info "$backup_info"

    if ! $NO_START && ! $DRY_RUN; then
        echo ""
        log_info "Monitor logs: sudo journalctl -u ${SERVICE_NAME} -f"
    fi
}

# Trap for cleanup on error
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
