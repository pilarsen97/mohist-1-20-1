#!/bin/bash
# Deploy latest changes from Git repository
# Includes Git LFS support and error handling

set -e  # Exit on error

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

# Check if Git LFS is installed and configured
check_git_lfs() {
    if ! command -v git-lfs &> /dev/null; then
        log_error "Git LFS is not installed!"
        log_error "Install with: brew install git-lfs (macOS) or apt install git-lfs (Linux)"
        exit 1
    fi

    if ! git lfs env &> /dev/null; then
        log_error "Git LFS is not initialized in this repository!"
        log_error "Run: git lfs install"
        exit 1
    fi

    log_info "Git LFS is properly configured"
}

# Main deployment
main() {
    log_step "Starting deployment process..."

    # Check Git LFS
    check_git_lfs

    # Fetch all changes including LFS metadata
    log_step "Fetching latest changes from repository..."
    if ! git fetch -a; then
        log_error "Failed to fetch from repository"
        exit 1
    fi
    log_info "Fetch completed successfully"

    # Get current commit for rollback reference
    CURRENT_COMMIT=$(git rev-parse HEAD)
    log_info "Current commit: $CURRENT_COMMIT"

    # Force checkout to match remote
    log_step "Updating working directory to latest version..."
    if ! git checkout --force origin/HEAD; then
        log_error "Failed to checkout origin/HEAD"
        log_error "Attempting rollback to $CURRENT_COMMIT..."
        git checkout --force "$CURRENT_COMMIT"
        exit 1
    fi

    # Verify Git LFS files were downloaded
    log_step "Verifying large files (Git LFS)..."
    if ! git lfs pull &> /dev/null; then
        log_warn "Git LFS pull had issues, but continuing..."
    fi

    # Check if mohist JAR exists and has correct size
    MOHIST_JAR="mohist-1.20.1-2eb79df.jar"
    if [ -f "$MOHIST_JAR" ]; then
        JAR_SIZE=$(stat -f%z "$MOHIST_JAR" 2>/dev/null || stat -c%s "$MOHIST_JAR" 2>/dev/null)
        if [ "$JAR_SIZE" -gt 100000000 ]; then  # > 100MB
            log_info "Main server JAR verified: $(numfmt --to=iec $JAR_SIZE 2>/dev/null || echo "$JAR_SIZE bytes")"
        else
            log_error "Server JAR seems corrupted (size: $JAR_SIZE bytes)"
            exit 1
        fi
    else
        log_error "Server JAR not found: $MOHIST_JAR"
        exit 1
    fi

    log_step "Deployment completed successfully!"
    NEW_COMMIT=$(git rev-parse HEAD)
    log_info "Deployed commit: $NEW_COMMIT"
}

main "$@"