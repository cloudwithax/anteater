#!/bin/bash
# Anteater - Base Definitions and Utilities
# Core definitions, constants, and basic utility functions used by all modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${ANTEATER_BASE_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_BASE_LOADED=1

# ============================================================================
# Color Definitions
# ============================================================================
readonly ESC=$'\033'
readonly GREEN="${ESC}[0;32m"
readonly BLUE="${ESC}[1;34m"
readonly CYAN="${ESC}[0;36m"
readonly YELLOW="${ESC}[0;33m"
readonly PURPLE="${ESC}[0;35m"
readonly PURPLE_BOLD="${ESC}[1;35m"
readonly RED="${ESC}[0;31m"
readonly GRAY="${ESC}[0;90m"
readonly NC="${ESC}[0m"

# ============================================================================
# Icon Definitions
# ============================================================================
readonly ICON_CONFIRM="◎"
readonly ICON_ADMIN="⚙"
readonly ICON_SUCCESS="✓"
readonly ICON_ERROR="☻"
readonly ICON_WARNING="◎"
readonly ICON_EMPTY="○"
readonly ICON_SOLID="●"
readonly ICON_LIST="•"
readonly ICON_SUBLIST="↳"
readonly ICON_ARROW="➤"
readonly ICON_DRY_RUN="→"
readonly ICON_REVIEW="☞"
readonly ICON_NAV_UP="↑"
readonly ICON_NAV_DOWN="↓"
readonly ICON_INFO="ℹ"

# ============================================================================
# Global Configuration Constants
# ============================================================================
readonly ANTEATER_TEMP_FILE_AGE_DAYS=7       # Temp file retention (days)
readonly ANTEATER_ORPHAN_AGE_DAYS=30         # Orphaned data retention (days)
readonly ANTEATER_MAX_PARALLEL_JOBS=15       # Parallel job limit
readonly ANTEATER_MAIL_DOWNLOADS_MIN_KB=5120 # Mail attachment size threshold
readonly ANTEATER_MAIL_AGE_DAYS=30           # Mail attachment retention (days)
readonly ANTEATER_LOG_AGE_DAYS=7             # Log retention (days)
readonly ANTEATER_CRASH_REPORT_AGE_DAYS=7    # Crash report retention (days)
readonly ANTEATER_SAVED_STATE_AGE_DAYS=30    # Saved state retention (days)
readonly ANTEATER_MAX_ORPHAN_ITERATIONS=100  # Max iterations for orphaned app data scan
readonly ANTEATER_ONE_GIB_KB=$((1024 * 1024))
readonly ANTEATER_ONE_GB_BYTES=1000000000

# ============================================================================
# Whitelist Configuration
# ============================================================================
declare -a DEFAULT_WHITELIST_PATTERNS=(
    "$HOME/.cache/huggingface*"
    "$HOME/.m2/repository/*"
    "$HOME/.gradle/caches/*"
    "$HOME/.gradle/daemon/*"
    "$HOME/.ollama/models/*"
    "$HOME/.cache/JetBrains*"
    "$HOME/.cache/pypoetry/virtualenvs*"
    "$HOME/.cache/ms-playwright*"
    "$HOME/.local/share/JetBrains*"
)

declare -a DEFAULT_OPTIMIZE_WHITELIST_PATTERNS=(
    "check_git_config"
)

# ============================================================================
# Stat Compatibility (GNU on Linux, BSD on OpenBSD)
# ============================================================================

# Detect once which stat dialect this system speaks. GNU stat accepts -c,
# BSD stat accepts -f. Cached in $_ANTEATER_STAT_DIALECT.
_anteater_stat_dialect() {
    if [[ -n "${_ANTEATER_STAT_DIALECT:-}" ]]; then
        printf '%s\n' "$_ANTEATER_STAT_DIALECT"
        return
    fi
    if stat -c '%s' / > /dev/null 2>&1; then
        _ANTEATER_STAT_DIALECT=gnu
    else
        _ANTEATER_STAT_DIALECT=bsd
    fi
    export _ANTEATER_STAT_DIALECT
    printf '%s\n' "$_ANTEATER_STAT_DIALECT"
}

# Get file size in bytes
get_file_size() {
    local file="$1" result
    if [[ "$(_anteater_stat_dialect)" == "gnu" ]]; then
        result=$(stat -c '%s' "$file" 2> /dev/null)
    else
        result=$(stat -f '%z' "$file" 2> /dev/null)
    fi
    echo "${result:-0}"
}

# Get file modification time in epoch seconds
get_file_mtime() {
    local file="$1"
    [[ -z "$file" ]] && {
        echo "0"
        return
    }
    local result
    if [[ "$(_anteater_stat_dialect)" == "gnu" ]]; then
        result=$(stat -c '%Y' "$file" 2> /dev/null || echo "")
    else
        result=$(stat -f '%m' "$file" 2> /dev/null || echo "")
    fi
    if [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "$result"
    else
        echo "0"
    fi
}

# Determine date command once
if [[ -x /bin/date ]]; then
    _DATE_CMD="/bin/date"
else
    _DATE_CMD="date"
fi

# Get current time in epoch seconds (defensive against locale/aliases)
get_epoch_seconds() {
    local result
    result=$($_DATE_CMD +%s 2> /dev/null || echo "")
    if [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "$result"
    else
        echo "0"
    fi
}

# Get file owner username
get_file_owner() {
    local file="$1"
    if [[ "$(_anteater_stat_dialect)" == "gnu" ]]; then
        stat -c '%U' "$file" 2> /dev/null || echo ""
    else
        stat -f '%Su' "$file" 2> /dev/null || echo ""
    fi
}

# Get file mode bits in octal (e.g., 644)
get_file_mode() {
    local file="$1"
    if [[ "$(_anteater_stat_dialect)" == "gnu" ]]; then
        stat -c '%a' "$file" 2> /dev/null || echo ""
    else
        stat -f '%Mp%Lp' "$file" 2> /dev/null || echo ""
    fi
}

# ============================================================================
# System Utilities
# ============================================================================

# Detect CPU architecture (uname -m result, e.g. x86_64, aarch64)
detect_architecture() {
    if [[ -n "${ANTEATER_ARCH_CACHE:-}" ]]; then
        echo "$ANTEATER_ARCH_CACHE"
        return 0
    fi
    export ANTEATER_ARCH_CACHE="$(uname -m 2> /dev/null || echo unknown)"
    echo "$ANTEATER_ARCH_CACHE"
}

# Get free disk space on root volume
# Returns: human-readable string (e.g., "100G")
get_free_space() {
    df -h / | awk 'NR==2 {print $4}'
}

# Get optimal parallel jobs for operation type (scan|io|compute|default)
get_optimal_parallel_jobs() {
    local operation_type="${1:-default}"
    if [[ -z "${ANTEATER_CPU_CORES_CACHE:-}" ]]; then
        local cores=""
        if command -v nproc > /dev/null 2>&1; then
            cores=$(nproc 2> /dev/null || echo "")
        fi
        if [[ -z "$cores" ]]; then
            cores=$(sysctl -n hw.ncpu 2> /dev/null || echo "")
        fi
        if [[ -z "$cores" ]]; then
            cores=$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)
        fi
        export ANTEATER_CPU_CORES_CACHE="$cores"
    fi
    local cpu_cores="$ANTEATER_CPU_CORES_CACHE"
    case "$operation_type" in
        scan | io)
            echo $((cpu_cores * 2))
            ;;
        compute)
            echo "$cpu_cores"
            ;;
        *)
            echo $((cpu_cores + 2))
            ;;
    esac
}

# ============================================================================
# User Context Utilities
# ============================================================================

is_root_user() {
    [[ "$(id -u)" == "0" ]]
}

get_invoking_user() {
    if [[ -n "${_ANTEATER_INVOKING_USER_CACHE:-}" ]]; then
        echo "$_ANTEATER_INVOKING_USER_CACHE"
        return 0
    fi

    local user
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        user="$SUDO_USER"
    else
        user="${USER:-}"
    fi

    export _ANTEATER_INVOKING_USER_CACHE="$user"
    echo "$user"
}

get_invoking_uid() {
    if [[ -n "${SUDO_UID:-}" ]]; then
        echo "$SUDO_UID"
        return 0
    fi

    local uid
    uid=$(id -u 2> /dev/null || true)
    echo "$uid"
}

get_invoking_gid() {
    if [[ -n "${SUDO_GID:-}" ]]; then
        echo "$SUDO_GID"
        return 0
    fi

    local gid
    gid=$(id -g 2> /dev/null || true)
    echo "$gid"
}

get_invoking_home() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        get_user_home "$SUDO_USER"
        return 0
    fi

    echo "${HOME:-}"
}

get_user_home() {
    local user="$1"
    local home=""

    if [[ -z "$user" ]]; then
        echo ""
        return 0
    fi

    if command -v getent > /dev/null 2>&1; then
        home=$(getent passwd "$user" 2> /dev/null | awk -F: '{print $6}' | head -1 || true)
    fi

    if [[ -z "$home" && -r /etc/passwd ]]; then
        home=$(awk -F: -v u="$user" '$1==u {print $6; exit}' /etc/passwd 2> /dev/null || true)
    fi

    if [[ "$home" == "~"* ]]; then
        home=""
    fi

    echo "$home"
}

ensure_user_dir() {
    local raw_path="$1"
    if [[ -z "$raw_path" ]]; then
        return 0
    fi

    local target_path="$raw_path"
    if [[ "$target_path" == "~"* ]]; then
        target_path="${target_path/#\~/$HOME}"
    fi

    mkdir -p "$target_path" 2> /dev/null || true

    if ! is_root_user; then
        return 0
    fi

    local sudo_user="${SUDO_USER:-}"
    if [[ -z "$sudo_user" || "$sudo_user" == "root" ]]; then
        return 0
    fi

    local user_home
    user_home=$(get_user_home "$sudo_user")
    if [[ -z "$user_home" ]]; then
        return 0
    fi
    user_home="${user_home%/}"

    if [[ "$target_path" != "$user_home" && "$target_path" != "$user_home/"* ]]; then
        return 0
    fi

    local owner_uid="${SUDO_UID:-}"
    local owner_gid="${SUDO_GID:-}"
    if [[ -z "$owner_uid" || -z "$owner_gid" ]]; then
        owner_uid=$(id -u "$sudo_user" 2> /dev/null || true)
        owner_gid=$(id -g "$sudo_user" 2> /dev/null || true)
    fi

    if [[ -z "$owner_uid" || -z "$owner_gid" ]]; then
        return 0
    fi

    local stat_dialect
    stat_dialect=$(_anteater_stat_dialect)
    local dir="$target_path"
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        # Early stop: if ownership is already correct, no need to continue up the tree
        if [[ -d "$dir" ]]; then
            local current_uid
            if [[ "$stat_dialect" == "gnu" ]]; then
                current_uid=$(stat -c '%u' "$dir" 2> /dev/null || echo "")
            else
                current_uid=$(stat -f '%u' "$dir" 2> /dev/null || echo "")
            fi
            if [[ "$current_uid" == "$owner_uid" ]]; then
                break
            fi
        fi

        chown "$owner_uid:$owner_gid" "$dir" 2> /dev/null || true

        if [[ "$dir" == "$user_home" ]]; then
            break
        fi
        dir=$(dirname "$dir")
        if [[ "$dir" == "." ]]; then
            break
        fi
    done
}

ensure_user_file() {
    local raw_path="$1"
    if [[ -z "$raw_path" ]]; then
        return 0
    fi

    local target_path="$raw_path"
    if [[ "$target_path" == "~"* ]]; then
        target_path="${target_path/#\~/$HOME}"
    fi

    ensure_user_dir "$(dirname "$target_path")"
    touch "$target_path" 2> /dev/null || true

    if ! is_root_user; then
        return 0
    fi

    local sudo_user="${SUDO_USER:-}"
    if [[ -z "$sudo_user" || "$sudo_user" == "root" ]]; then
        return 0
    fi

    local user_home
    user_home=$(get_user_home "$sudo_user")
    if [[ -z "$user_home" ]]; then
        return 0
    fi
    user_home="${user_home%/}"

    if [[ "$target_path" != "$user_home" && "$target_path" != "$user_home/"* ]]; then
        return 0
    fi

    local owner_uid="${SUDO_UID:-}"
    local owner_gid="${SUDO_GID:-}"
    if [[ -z "$owner_uid" || -z "$owner_gid" ]]; then
        owner_uid=$(id -u "$sudo_user" 2> /dev/null || true)
        owner_gid=$(id -g "$sudo_user" 2> /dev/null || true)
    fi

    if [[ -n "$owner_uid" && -n "$owner_gid" ]]; then
        chown "$owner_uid:$owner_gid" "$target_path" 2> /dev/null || true
    fi
}

# ============================================================================
# Formatting Utilities
# ============================================================================

# Convert bytes to human-readable format (e.g., 1.5GB), Base-10 (1 KB = 1000 B)
bytes_to_human() {
    local bytes="$1"
    [[ "$bytes" =~ ^[0-9]+$ ]] || {
        echo "0B"
        return 1
    }

    # GB: >= 1,000,000,000 bytes
    if ((bytes >= 1000000000)); then
        local scaled=$(((bytes * 100 + 500000000) / 1000000000))
        printf "%d.%02dGB\n" $((scaled / 100)) $((scaled % 100))
    # MB: >= 1,000,000 bytes
    elif ((bytes >= 1000000)); then
        local scaled=$(((bytes * 10 + 500000) / 1000000))
        printf "%d.%01dMB\n" $((scaled / 10)) $((scaled % 10))
    # KB: >= 1,000 bytes (round up to nearest KB instead of decimal)
    elif ((bytes >= 1000)); then
        printf "%dKB\n" $(((bytes + 500) / 1000))
    else
        printf "%dB\n" "$bytes"
    fi
}

# Convert kilobytes to human-readable format
# Args: $1 - size in KB
# Returns: formatted string
bytes_to_human_kb() {
    bytes_to_human "$((${1:-0} * 1024))"
}

# Pick a cleanup result color using the displayed decimal 1 GB threshold.
cleanup_result_color_kb() {
    printf '%s' "$GREEN"
}

# ============================================================================
# Temporary File Management
# ============================================================================

# Tracked temporary files and directories
declare -a ANTEATER_TEMP_FILES=()
declare -a ANTEATER_TEMP_DIRS=()

normalize_temp_root() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1

    if [[ "$path" == "~"* ]]; then
        path="${path/#\~/$HOME}"
    fi

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done

    [[ -n "$path" ]] || return 1
    printf '%s\n' "$path"
}

probe_temp_root() {
    local raw_path="$1"
    local allow_create="${2:-false}"
    local path
    local probe=""

    path=$(normalize_temp_root "$raw_path") || return 1

    if [[ "$allow_create" == "true" ]]; then
        ensure_user_dir "$path"
    fi

    [[ -d "$path" ]] || return 1

    probe=$(mktemp "$path/anteater.probe.XXXXXX" 2> /dev/null) || return 1
    rm -f "$probe" 2> /dev/null || true

    printf '%s\n' "$path"
}

ensure_anteater_temp_root() {
    if [[ -n "${ANTEATER_RESOLVED_TMPDIR:-}" ]]; then
        return 0
    fi

    local resolved=""
    local candidate="${TMPDIR:-}"
    local invoking_home=""

    if [[ -n "$candidate" ]]; then
        resolved=$(probe_temp_root "$candidate" false || true)
    fi

    if [[ -z "$resolved" ]]; then
        invoking_home=$(get_invoking_home)
        if [[ -n "$invoking_home" ]]; then
            resolved=$(probe_temp_root "$invoking_home/.cache/anteater/tmp" true || true)
        fi
    fi

    if [[ -z "$resolved" ]]; then
        resolved=$(probe_temp_root "/tmp" false || true)
    fi

    [[ -n "$resolved" ]] || resolved="/tmp"
    ANTEATER_RESOLVED_TMPDIR="$resolved"
    export ANTEATER_RESOLVED_TMPDIR
}

get_anteater_temp_root() {
    ensure_anteater_temp_root
    printf '%s\n' "$ANTEATER_RESOLVED_TMPDIR"
}

prepare_anteater_tmpdir() {
    ensure_anteater_temp_root
    export TMPDIR="$ANTEATER_RESOLVED_TMPDIR"
    printf '%s\n' "$ANTEATER_RESOLVED_TMPDIR"
}

anteater_temp_path_template() {
    local prefix="${1:-anteater}"
    ensure_anteater_temp_root
    printf '%s/%s.XXXXXX\n' "$ANTEATER_RESOLVED_TMPDIR" "$prefix"
}

# Create tracked temporary file
create_temp_file() {
    local temp
    ensure_anteater_temp_root
    temp=$(mktemp "$ANTEATER_RESOLVED_TMPDIR/anteater.XXXXXX") || return 1
    register_temp_file "$temp"
    echo "$temp"
}

# Create tracked temporary directory
create_temp_dir() {
    local temp
    ensure_anteater_temp_root
    temp=$(mktemp -d "$ANTEATER_RESOLVED_TMPDIR/anteater.XXXXXX") || return 1
    register_temp_dir "$temp"
    echo "$temp"
}

# Register existing file for cleanup
register_temp_file() {
    ANTEATER_TEMP_FILES+=("$1")
}

# Register existing directory for cleanup
register_temp_dir() {
    ANTEATER_TEMP_DIRS+=("$1")
}

# Create temp file with prefix.
# Compatible with both GNU mktemp (coreutils) and BSD mktemp (OpenBSD).
mktemp_file() {
    local prefix="${1:-anteater}"
    local temp
    local error_msg
    # Add .XXXXXX suffix to work with both BSD and GNU mktemp
    if ! error_msg=$(mktemp "$(anteater_temp_path_template "$prefix")" 2>&1); then
        echo "Error: Failed to create temporary file: $error_msg" >&2
        return 1
    fi
    temp="$error_msg"
    register_temp_file "$temp"
    echo "$temp"
}

# Cleanup all tracked temp files and directories
cleanup_temp_files() {
    if declare -F stop_inline_spinner > /dev/null 2>&1; then
        stop_inline_spinner || true
    fi
    local file
    if [[ ${#ANTEATER_TEMP_FILES[@]} -gt 0 ]]; then
        for file in "${ANTEATER_TEMP_FILES[@]}"; do
            [[ -f "$file" ]] && rm -f "$file" 2> /dev/null || true
        done
    fi

    if [[ ${#ANTEATER_TEMP_DIRS[@]} -gt 0 ]]; then
        for file in "${ANTEATER_TEMP_DIRS[@]}"; do
            [[ -d "$file" ]] && rm -rf "$file" 2> /dev/null || true # SAFE: cleanup_temp_files
        done
    fi

    ANTEATER_TEMP_FILES=()
    ANTEATER_TEMP_DIRS=()
}

# ============================================================================
# Section Tracking (for progress indication)
# ============================================================================

# Global section tracking variables
TRACK_SECTION=0
SECTION_ACTIVITY=0

# Start a new section
# Args: $1 - section title
start_section() {
    TRACK_SECTION=1
    SECTION_ACTIVITY=0
    echo ""
    echo -e "${PURPLE_BOLD}${ICON_ARROW} $1${NC}"
}

# End a section
# Shows "Nothing to tidy" if no activity was recorded
end_section() {
    if [[ "${TRACK_SECTION:-0}" == "1" && "${SECTION_ACTIVITY:-0}" == "0" ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Nothing to tidy"
    fi
    TRACK_SECTION=0
}

# Mark activity in current section
note_activity() {
    if [[ "${TRACK_SECTION:-0}" == "1" ]]; then
        SECTION_ACTIVITY=1
    fi
}

# Start a section spinner with optional message
# Usage: start_section_spinner "message"
start_section_spinner() {
    local message="${1:-Scanning...}"
    stop_inline_spinner || true
    if [[ -t 1 ]]; then
        ANTEATER_SPINNER_PREFIX="  " start_inline_spinner "$message"
    fi
}

# Stop spinner and clear the line
# Usage: stop_section_spinner
stop_section_spinner() {
    # Always try to stop spinner (function handles empty PID gracefully)
    stop_inline_spinner || true
    # Always clear line to handle edge cases where spinner output remains
    # (e.g., spinner was stopped elsewhere but line not cleared)
    if [[ -t 1 ]]; then
        printf "\r\033[2K" >&2 || true
    fi
}

# Safe terminal line clearing with terminal type detection
# Usage: safe_clear_lines <num_lines> [tty_device]
# Returns: 0 on success, 1 if terminal doesn't support ANSI
safe_clear_lines() {
    local lines="${1:-1}"
    local tty_device="${2:-/dev/tty}"

    # Use centralized ANSI support check (defined below)
    # Note: This forward reference works because functions are parsed before execution
    is_ansi_supported 2> /dev/null || return 1

    # Clear lines one by one (more reliable than multi-line sequences)
    local i
    for ((i = 0; i < lines; i++)); do
        printf "\033[1A\r\033[2K" > "$tty_device" 2> /dev/null || return 1
    done

    return 0
}

# Safe single line clear with fallback
# Usage: safe_clear_line [tty_device]
safe_clear_line() {
    local tty_device="${1:-/dev/tty}"

    # Use centralized ANSI support check
    is_ansi_supported 2> /dev/null || return 1

    printf "\r\033[2K" > "$tty_device" 2> /dev/null || return 1
    return 0
}

# Update progress spinner if enough time has elapsed
# Usage: update_progress_if_needed <completed> <total> <last_update_time_var> [interval]
# Example: update_progress_if_needed "$completed" "$total" last_progress_update 2
# Returns: 0 if updated, 1 if skipped
update_progress_if_needed() {
    local completed="$1"
    local total="$2"
    local last_update_var="$3" # Name of variable holding last update time
    local interval="${4:-2}"   # Default: update every 2 seconds

    # Get current time
    local current_time
    current_time=$(get_epoch_seconds)

    # Get last update time from variable
    local last_time
    eval "last_time=\${$last_update_var:-0}"
    [[ "$last_time" =~ ^[0-9]+$ ]] || last_time=0

    # Check if enough time has elapsed
    if [[ $((current_time - last_time)) -ge $interval ]]; then
        # Update the spinner with progress
        stop_section_spinner
        start_section_spinner "Scanning items... $completed/$total"

        # Update the last_update_time variable
        eval "$last_update_var=$current_time"
        return 0
    fi

    return 1
}

# ============================================================================
# Terminal Compatibility Checks
# ============================================================================

# Check if terminal supports ANSI escape codes
# Usage: is_ansi_supported
# Returns: 0 if supported, 1 if not
is_ansi_supported() {
    if [[ -n "${ANTEATER_ANSI_SUPPORTED_CACHE:-}" ]]; then
        return "$ANTEATER_ANSI_SUPPORTED_CACHE"
    fi

    # Check if running in interactive terminal
    if ! [[ -t 1 ]]; then
        export ANTEATER_ANSI_SUPPORTED_CACHE=1
        return 1
    fi

    # Check TERM variable
    if [[ -z "${TERM:-}" ]]; then
        export ANTEATER_ANSI_SUPPORTED_CACHE=1
        return 1
    fi

    # Check for known ANSI-compatible terminals
    case "$TERM" in
        xterm* | vt100 | vt220 | screen* | tmux* | ansi | linux | rxvt* | konsole*)
            export ANTEATER_ANSI_SUPPORTED_CACHE=0
            return 0
            ;;
        dumb | unknown)
            export ANTEATER_ANSI_SUPPORTED_CACHE=1
            return 1
            ;;
        *)
            # Check terminfo database if available
            if command -v tput > /dev/null 2>&1; then
                # Test if terminal supports colors (good proxy for ANSI support)
                local colors=$(tput colors 2> /dev/null || echo "0")
                if [[ "$colors" -ge 8 ]]; then
                    export ANTEATER_ANSI_SUPPORTED_CACHE=0
                    return 0
                fi
            fi
            export ANTEATER_ANSI_SUPPORTED_CACHE=1
            return 1
            ;;
    esac
}
