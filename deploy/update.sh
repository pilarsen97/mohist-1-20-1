#!/bin/bash
# Complete server update procedure with backup and rollback
# Stops server gracefully, backs up, deploys, and restarts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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

log_success() {
    echo -e "${MAGENTA}[SUCCESS]${NC} $1"
}

# Rollback function
rollback() {
    log_error "Update failed! Starting rollback procedure..."

    # If deployment failed, try to checkout previous commit
    if [ -n "${PREVIOUS_COMMIT}" ]; then
        log_warn "Rolling back to previous commit: ${PREVIOUS_COMMIT}"
        cd "$SERVER_DIR"
        git checkout --force "${PREVIOUS_COMMIT}" || log_error "Rollback failed!"
    fi

    # Restart server even after failure
    log_warn "Attempting to start server after rollback..."
    bash "${SCRIPT_DIR}/start.sh" || log_error "Failed to start server!"

    exit 1
}

# Main update procedure
main() {
    echo ""
    echo "======================================"
    echo "  Minecraft Server Update Procedure  "
    echo "======================================"
    echo ""

    # Save current commit for rollback
    cd "$SERVER_DIR"
    PREVIOUS_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
    log_info "Current commit: ${PREVIOUS_COMMIT:-N/A}"

    # Step 1: Stop server gracefully
    log_step "1/5 - Stopping server gracefully..."
    if ! bash "${SCRIPT_DIR}/stop.sh"; then
        log_error "Failed to stop server gracefully"
        exit 1
    fi
    sleep 2

    # Step 2: Create backup
    log_step "2/5 - Creating backup before update..."
    if ! bash "${SCRIPT_DIR}/backup.sh"; then
        log_warn "Backup failed, but continuing with update..."
    fi
    sleep 1

    # Step 3: Deploy updates
    log_step "3/5 - Deploying updates from repository..."
    if ! bash "${SCRIPT_DIR}/deploy.sh"; then
        rollback
    fi
    sleep 1

    # Step 4: Validate deployment
    log_step "4/5 - Validating deployment..."

    # Check if server JAR exists
    MOHIST_JAR="${SERVER_DIR}/mohist-1.20.1-2eb79df.jar"
    if [ ! -f "$MOHIST_JAR" ]; then
        log_error "Server JAR not found after deployment!"
        rollback
    fi

    # Check JAR size
    JAR_SIZE=$(stat -f%z "$MOHIST_JAR" 2>/dev/null || stat -c%s "$MOHIST_JAR" 2>/dev/null)
    if [ "$JAR_SIZE" -lt 100000000 ]; then
        log_error "Server JAR seems corrupted (size: $JAR_SIZE bytes)"
        rollback
    fi

    log_info "Deployment validation passed"
    sleep 1

    # Step 5: Start server
    log_step "5/5 - Starting server..."
    if ! bash "${SCRIPT_DIR}/start.sh"; then
        log_error "Failed to start server after update"
        rollback
    fi

    echo ""
    log_success "======================================"
    log_success "  Update completed successfully!     "
    log_success "======================================"
    echo ""

    NEW_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "N/A")
    log_info "Previous commit: ${PREVIOUS_COMMIT:-N/A}"
    log_info "Current commit:  $NEW_COMMIT"
    log_info "Server should be starting up now..."
    echo ""
}

main "$@"
