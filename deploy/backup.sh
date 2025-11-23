#!/bin/bash
# Automated backup script for Minecraft server
# Creates timestamped backups of world files

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${SERVER_DIR}/backups"
BACKUP_RETENTION=7  # Keep last N backups
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="backup_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Create backup directory if it doesn't exist
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
}

# Backup world files
backup_worlds() {
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    log_step "Creating backup: $BACKUP_NAME"
    mkdir -p "$backup_path"

    # Backup main world
    if [ -d "${SERVER_DIR}/world" ]; then
        log_info "Backing up world..."
        tar -czf "${backup_path}/world.tar.gz" -C "$SERVER_DIR" world 2>/dev/null || log_warn "World backup incomplete"
    fi

    # Backup nether
    if [ -d "${SERVER_DIR}/world_nether" ]; then
        log_info "Backing up nether..."
        tar -czf "${backup_path}/world_nether.tar.gz" -C "$SERVER_DIR" world_nether 2>/dev/null || log_warn "Nether backup incomplete"
    fi

    # Backup end
    if [ -d "${SERVER_DIR}/world_the_end" ]; then
        log_info "Backing up end..."
        tar -czf "${backup_path}/world_the_end.tar.gz" -C "$SERVER_DIR" world_the_end 2>/dev/null || log_warn "End backup incomplete"
    fi

    # Backup server properties and configs
    log_info "Backing up configuration files..."
    cp "${SERVER_DIR}/server.properties" "${backup_path}/" 2>/dev/null || log_warn "server.properties not found"
    cp "${SERVER_DIR}/bukkit.yml" "${backup_path}/" 2>/dev/null || log_warn "bukkit.yml not found"
    cp "${SERVER_DIR}/spigot.yml" "${backup_path}/" 2>/dev/null || log_warn "spigot.yml not found"

    # Copy mohist config
    if [ -d "${SERVER_DIR}/mohist-config" ]; then
        cp -r "${SERVER_DIR}/mohist-config" "${backup_path}/" 2>/dev/null || log_warn "mohist-config not found"
    fi

    # Create metadata file
    echo "Backup created: $(date)" > "${backup_path}/backup_info.txt"
    echo "Server directory: ${SERVER_DIR}" >> "${backup_path}/backup_info.txt"
    echo "Git commit: $(cd "$SERVER_DIR" && git rev-parse HEAD 2>/dev/null || echo 'N/A')" >> "${backup_path}/backup_info.txt"

    # Calculate backup size
    local backup_size=$(du -sh "$backup_path" | cut -f1)
    log_info "Backup size: $backup_size"

    echo "$backup_path"
}

# Clean old backups
cleanup_old_backups() {
    local backup_count=$(ls -1d ${BACKUP_DIR}/backup_* 2>/dev/null | wc -l)

    if [ "$backup_count" -gt "$BACKUP_RETENTION" ]; then
        log_step "Cleaning old backups (keeping last $BACKUP_RETENTION)..."

        # Delete oldest backups
        ls -1td ${BACKUP_DIR}/backup_* | tail -n +$((BACKUP_RETENTION + 1)) | while read old_backup; do
            log_info "Removing old backup: $(basename "$old_backup")"
            rm -rf "$old_backup"
        done
    else
        log_info "Total backups: $backup_count (retention: $BACKUP_RETENTION)"
    fi
}

# List existing backups
list_backups() {
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR)" ]; then
        log_info "Existing backups:"
        ls -lht ${BACKUP_DIR}/backup_* 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        log_info "No existing backups found"
    fi
}

# Main backup procedure
main() {
    log_step "Starting backup procedure..."

    # Create backup directory
    create_backup_dir

    # Perform backup
    backup_path=$(backup_worlds)

    # Cleanup old backups
    cleanup_old_backups

    # List all backups
    list_backups

    log_step "Backup completed successfully!"
    log_info "Backup location: $backup_path"
}

# Handle command line arguments
case "${1:-}" in
    --list)
        list_backups
        exit 0
        ;;
    --help)
        echo "Usage: $0 [--list|--help]"
        echo "  --list    List existing backups"
        echo "  --help    Show this help message"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
