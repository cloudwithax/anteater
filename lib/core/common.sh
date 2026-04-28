#!/bin/bash
# Anteater - Common Functions Library
# Main entry point that loads all core modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${ANTEATER_COMMON_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_COMMON_LOADED=1

_ANTEATER_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core modules
source "$_ANTEATER_CORE_DIR/base.sh"
prepare_anteater_tmpdir > /dev/null
source "$_ANTEATER_CORE_DIR/log.sh"

source "$_ANTEATER_CORE_DIR/timeout.sh"
source "$_ANTEATER_CORE_DIR/file_ops.sh"
source "$_ANTEATER_CORE_DIR/ui.sh"

# Load sudo management if available
if [[ -f "$_ANTEATER_CORE_DIR/sudo.sh" ]]; then
    source "$_ANTEATER_CORE_DIR/sudo.sh"
fi

# Normalize a path for comparisons while preserving root.
anteater_normalize_path() {
    local path="$1"
    local normalized="${path%/}"
    [[ -n "$normalized" ]] && printf '%s\n' "$normalized" || printf '%s\n' "$path"
}

# Return a stable identity for an existing path. Prefer dev+inode so aliased
# paths on case-insensitive filesystems or symlinks collapse to one identity.
anteater_path_identity() {
    local path="$1"
    local normalized
    normalized=$(anteater_normalize_path "$path")

    if [[ -e "$normalized" || -L "$normalized" ]]; then
        if command -v stat > /dev/null 2>&1; then
            local fs_id=""
            if [[ "$(_anteater_stat_dialect)" == "gnu" ]]; then
                fs_id=$(stat -L -c '%d:%i' "$normalized" 2> /dev/null || stat -c '%d:%i' "$normalized" 2> /dev/null || true)
            else
                fs_id=$(stat -L -f '%d:%i' "$normalized" 2> /dev/null || stat -f '%d:%i' "$normalized" 2> /dev/null || true)
            fi
            if [[ "$fs_id" =~ ^[0-9]+:[0-9]+$ ]]; then
                printf 'inode:%s\n' "$fs_id"
                return 0
            fi
        fi
    fi

    printf 'path:%s\n' "$normalized"
}

anteater_identity_in_list() {
    local needle="$1"
    shift

    local existing
    for existing in "$@"; do
        [[ "$existing" == "$needle" ]] && return 0
    done
    return 1
}
