#!/bin/bash
# =============================================================================
# logging.sh - SuperClaude Deployment Logging Library
# =============================================================================
# Shared logging functions with colors, timestamps, progress bars, and file logging
# Usage: source ./lib/logging.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/../logs/deploy}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/deploy_$(date +%Y%m%d).log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Colors and Formatting
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    # Terminal supports colors
    readonly C_RESET='\033[0m'
    readonly C_BOLD='\033[1m'
    readonly C_DIM='\033[2m'

    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_MAGENTA='\033[0;35m'
    readonly C_CYAN='\033[0;36m'
    readonly C_WHITE='\033[0;37m'

    readonly C_BG_RED='\033[41m'
    readonly C_BG_GREEN='\033[42m'
    readonly C_BG_YELLOW='\033[43m'
    readonly C_BG_BLUE='\033[44m'
else
    # No color support
    readonly C_RESET=''
    readonly C_BOLD=''
    readonly C_DIM=''
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_MAGENTA=''
    readonly C_CYAN=''
    readonly C_WHITE=''
    readonly C_BG_RED=''
    readonly C_BG_GREEN=''
    readonly C_BG_YELLOW=''
    readonly C_BG_BLUE=''
fi

# Symbols
readonly SYM_CHECK="${C_GREEN}✓${C_RESET}"
readonly SYM_CROSS="${C_RED}✗${C_RESET}"
readonly SYM_WARN="${C_YELLOW}⚠${C_RESET}"
readonly SYM_INFO="${C_BLUE}ℹ${C_RESET}"
readonly SYM_ARROW="${C_CYAN}→${C_RESET}"
readonly SYM_TREE_MID="├─"
readonly SYM_TREE_END="└─"
readonly SYM_TREE_LINE="│"

# -----------------------------------------------------------------------------
# Core Logging Functions
# -----------------------------------------------------------------------------

# Get timestamp
_timestamp() {
    date "+%H:%M:%S"
}

_datestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Write to log file (always, regardless of level)
_log_to_file() {
    local level="$1"
    local message="$2"
    if [[ -w "$LOG_DIR" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$(_datestamp)] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Log with level check
_should_log() {
    local level="$1"
    case "$LOG_LEVEL" in
        DEBUG) return 0 ;;
        INFO)  [[ "$level" != "DEBUG" ]] && return 0 ;;
        WARN)  [[ "$level" == "WARN" || "$level" == "ERROR" ]] && return 0 ;;
        ERROR) [[ "$level" == "ERROR" ]] && return 0 ;;
    esac
    return 1
}

# Basic log functions
log_debug() {
    local message="$1"
    _log_to_file "DEBUG" "$message"
    if _should_log "DEBUG"; then
        echo -e "${C_DIM}[$(_timestamp)] [DEBUG] $message${C_RESET}"
    fi
}

log_info() {
    local message="$1"
    _log_to_file "INFO" "$message"
    if _should_log "INFO"; then
        echo -e "${C_GREEN}[$(_timestamp)]${C_RESET} ${C_WHITE}[INFO]${C_RESET}  $message"
    fi
}

log_warn() {
    local message="$1"
    _log_to_file "WARN" "$message"
    if _should_log "WARN"; then
        echo -e "${C_YELLOW}[$(_timestamp)]${C_RESET} ${C_YELLOW}[WARN]${C_RESET}  ${C_YELLOW}$message${C_RESET}"
    fi
}

log_error() {
    local message="$1"
    _log_to_file "ERROR" "$message"
    if _should_log "ERROR"; then
        echo -e "${C_RED}[$(_timestamp)]${C_RESET} ${C_RED}[ERROR]${C_RESET} ${C_RED}$message${C_RESET}" >&2
    fi
}

log_success() {
    local message="$1"
    _log_to_file "SUCCESS" "$message"
    echo -e "${C_GREEN}[$(_timestamp)]${C_RESET} ${C_GREEN}[OK]${C_RESET}    ${C_GREEN}$message${C_RESET}"
}

# -----------------------------------------------------------------------------
# Step-based Logging (for multi-step operations)
# -----------------------------------------------------------------------------

# Current step tracking
_CURRENT_STEP=0
_TOTAL_STEPS=0

# Initialize step counter
init_steps() {
    _TOTAL_STEPS="$1"
    _CURRENT_STEP=0
    _log_to_file "INFO" "Starting operation with $_TOTAL_STEPS steps"
}

# Log a step start
log_step() {
    local step_name="$1"
    ((_CURRENT_STEP++))
    _log_to_file "STEP" "Step $_CURRENT_STEP/$_TOTAL_STEPS: $step_name"
    echo -e "\n${C_BLUE}[$(_timestamp)]${C_RESET} ${C_BOLD}${C_CYAN}[STEP $_CURRENT_STEP/$_TOTAL_STEPS]${C_RESET} ${C_BOLD}$step_name${C_RESET}"
}

# Log sub-step (indented)
log_substep() {
    local message="$1"
    local status="${2:-}"  # optional: ok, error, warn
    local prefix="           ${SYM_TREE_MID} "

    case "$status" in
        ok)    echo -e "$prefix$message $SYM_CHECK" ;;
        error) echo -e "$prefix${C_RED}$message${C_RESET} $SYM_CROSS" ;;
        warn)  echo -e "$prefix${C_YELLOW}$message${C_RESET} $SYM_WARN" ;;
        *)     echo -e "$prefix$message" ;;
    esac
    _log_to_file "SUBSTEP" "$message [$status]"
}

# Log last sub-step (uses different tree character)
log_substep_last() {
    local message="$1"
    local status="${2:-}"
    local prefix="           ${SYM_TREE_END} "

    case "$status" in
        ok)    echo -e "$prefix$message $SYM_CHECK" ;;
        error) echo -e "$prefix${C_RED}$message${C_RESET} $SYM_CROSS" ;;
        warn)  echo -e "$prefix${C_YELLOW}$message${C_RESET} $SYM_WARN" ;;
        *)     echo -e "$prefix$message" ;;
    esac
    _log_to_file "SUBSTEP" "$message [$status]"
}

# -----------------------------------------------------------------------------
# Progress Bar
# -----------------------------------------------------------------------------

# Show a progress bar
# Usage: show_progress current total [width]
show_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-20}"
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r           ${SYM_TREE_MID} Progress: ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# Spinner for indefinite operations
# Usage: start_spinner "Message"
#        ... do work ...
#        stop_spinner [ok|error]
_SPINNER_PID=""
_SPINNER_MSG=""

start_spinner() {
    local message="$1"
    _SPINNER_MSG="$message"

    # Spinner characters
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    (
        i=0
        while true; do
            printf "\r           ${SYM_TREE_MID} %s ${C_CYAN}%s${C_RESET}" "$message" "${spin:i++%${#spin}:1}"
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown
}

stop_spinner() {
    local status="${1:-ok}"

    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi

    # Clear the line and show final status
    printf "\r\033[K"  # Clear line
    log_substep "$_SPINNER_MSG" "$status"
}

# -----------------------------------------------------------------------------
# Header and Footer Boxes
# -----------------------------------------------------------------------------

# Print a header box
# Usage: print_header "Title"
print_header() {
    local title="$1"
    local timestamp="$(_datestamp)"
    local width=64
    local title_with_ts="$title - $timestamp"
    local padding=$(( (width - ${#title_with_ts} - 4) / 2 ))

    echo ""
    echo -e "${C_CYAN}╔$(printf '═%.0s' $(seq 1 $width))╗${C_RESET}"
    printf "${C_CYAN}║${C_RESET}  ${C_BOLD}%-${width}s${C_RESET}${C_CYAN}║${C_RESET}\n" "$title_with_ts"
    echo -e "${C_CYAN}╚$(printf '═%.0s' $(seq 1 $width))╝${C_RESET}"
    echo ""

    _log_to_file "HEADER" "$title"
}

# Print a footer box with summary
# Usage: print_footer status duration [extra_info]
print_footer() {
    local status="$1"
    local duration="$2"
    local extra="${3:-}"
    local width=64

    echo ""
    echo -e "${C_CYAN}╔$(printf '═%.0s' $(seq 1 $width))╗${C_RESET}"

    if [[ "$status" == "success" ]]; then
        printf "${C_CYAN}║${C_RESET}  ${C_GREEN}${C_BOLD}✓ COMPLETE${C_RESET}%-54s${C_CYAN}║${C_RESET}\n" ""
    else
        printf "${C_CYAN}║${C_RESET}  ${C_RED}${C_BOLD}✗ FAILED${C_RESET}%-56s${C_CYAN}║${C_RESET}\n" ""
    fi

    local summary="Duration: ${duration}"
    [[ -n "$extra" ]] && summary="$summary | $extra"
    printf "${C_CYAN}║${C_RESET}  %-62s${C_CYAN}║${C_RESET}\n" "$summary"

    echo -e "${C_CYAN}╚$(printf '═%.0s' $(seq 1 $width))╝${C_RESET}"
    echo ""

    _log_to_file "FOOTER" "Status: $status, Duration: $duration, $extra"
}

# Print a section separator
print_separator() {
    local title="${1:-}"
    if [[ -n "$title" ]]; then
        echo -e "\n${C_DIM}─── $title ───${C_RESET}\n"
    else
        echo -e "\n${C_DIM}$(printf '─%.0s' $(seq 1 50))${C_RESET}\n"
    fi
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1f GB" "$(echo "scale=1; $bytes/1073741824" | bc)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.1f KB" "$(echo "scale=1; $bytes/1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Format seconds to human readable duration
format_duration() {
    local seconds="$1"
    if [[ $seconds -ge 3600 ]]; then
        printf "%dh %dm %ds" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
    elif [[ $seconds -ge 60 ]]; then
        printf "%dm %ds" $((seconds/60)) $((seconds%60))
    else
        printf "%ds" "$seconds"
    fi
}

# Track operation start time
_OP_START_TIME=""

start_timer() {
    _OP_START_TIME=$(date +%s)
}

get_elapsed() {
    if [[ -n "$_OP_START_TIME" ]]; then
        local now=$(date +%s)
        format_duration $((now - _OP_START_TIME))
    else
        echo "0s"
    fi
}

# -----------------------------------------------------------------------------
# Error Handling
# -----------------------------------------------------------------------------

# Die with error message
die() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    exit "$code"
}

# Run command with error handling
run_cmd() {
    local cmd="$*"
    log_debug "Running: $cmd"

    if ! eval "$cmd"; then
        log_error "Command failed: $cmd"
        return 1
    fi
    return 0
}

# Run command silently (only show on error)
run_silent() {
    local cmd="$*"
    local output
    log_debug "Running (silent): $cmd"

    if ! output=$(eval "$cmd" 2>&1); then
        log_error "Command failed: $cmd"
        log_error "Output: $output"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Environment Detection
# -----------------------------------------------------------------------------

is_production() {
    [[ -f /etc/systemd/system/minecraft.service ]] && systemctl is-active --quiet minecraft.service 2>/dev/null
}

is_systemd_available() {
    command -v systemctl &>/dev/null
}

is_root() {
    [[ $EUID -eq 0 ]]
}

get_platform() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       echo "unknown" ;;
    esac
}

# -----------------------------------------------------------------------------
# Confirmation Prompts
# -----------------------------------------------------------------------------

# Ask yes/no question
# Usage: confirm "Do you want to continue?"
confirm() {
    local prompt="$1"
    local default="${2:-n}"  # default to no

    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi

    read -r -p "$(echo -e "${C_YELLOW}$prompt${C_RESET} $yn_prompt ")" response
    response="${response:-$default}"

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Ask for input with default
# Usage: ask_input "Enter value" "default_value"
ask_input() {
    local prompt="$1"
    local default="$2"
    local result

    read -r -p "$(echo -e "${C_CYAN}$prompt${C_RESET} [${default}]: ")" result
    echo "${result:-$default}"
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

log_debug "Logging library loaded. Log file: $LOG_FILE"
