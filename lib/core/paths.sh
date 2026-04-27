#!/bin/bash
# Anteater - Path Constants
# XDG-aware path resolution. All paths used by Anteater for its own
# state, config, cache, logs, and trash flow through here so callers
# don't hardcode `~/Library/...` or `~/.config/anteater/...`.
#
# After sourcing, the following readonly globals are populated:
#
#   ANTEATER_XDG_CONFIG_HOME    $XDG_CONFIG_HOME or $HOME/.config
#   ANTEATER_XDG_CACHE_HOME     $XDG_CACHE_HOME  or $HOME/.cache
#   ANTEATER_XDG_DATA_HOME      $XDG_DATA_HOME   or $HOME/.local/share
#   ANTEATER_XDG_STATE_HOME     $XDG_STATE_HOME  or $HOME/.local/state
#
#   ANTEATER_CONFIG_DIR         $ANTEATER_XDG_CONFIG_HOME/anteater
#   ANTEATER_CACHE_DIR          $ANTEATER_XDG_CACHE_HOME/anteater
#   ANTEATER_DATA_DIR           $ANTEATER_XDG_DATA_HOME/anteater
#   ANTEATER_STATE_DIR          $ANTEATER_XDG_STATE_HOME/anteater
#   ANTEATER_LOG_DIR            $ANTEATER_STATE_DIR/logs
#
#   ANTEATER_TRASH_DIR          $ANTEATER_XDG_DATA_HOME/Trash (FreeDesktop spec)
#   ANTEATER_TMP                $TMPDIR or /tmp
#   ANTEATER_VAR_TMP            /var/tmp
#
# Helpers:
#   paths_user_home             Echoes a validated $HOME (errors if unset)
#   paths_resolve <path>        Expands leading ~ and prints absolute form
#   paths_ensure_dir <path>     mkdir -p with tight perms (700)

set -euo pipefail

if [[ -n "${ANTEATER_PATHS_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_PATHS_LOADED=1

# ============================================================================
# Helpers
# ============================================================================

paths_user_home() {
    local h="${HOME:-}"
    if [[ -z "$h" ]]; then
        echo "anteater: \$HOME is not set" >&2
        return 1
    fi
    printf '%s\n' "$h"
}

paths_resolve() {
    local p="$1"
    case "$p" in
        "~") p="$HOME" ;;
        "~/"*) p="$HOME/${p#~/}" ;;
    esac
    printf '%s\n' "$p"
}

paths_ensure_dir() {
    local d="$1"
    [[ -z "$d" ]] && return 1
    if [[ ! -d "$d" ]]; then
        mkdir -p "$d"
        chmod 700 "$d" 2> /dev/null || true
    fi
}

# ============================================================================
# Resolve XDG base directories
# ============================================================================

_paths_home="${HOME:-/root}"

ANTEATER_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$_paths_home/.config}"
ANTEATER_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$_paths_home/.cache}"
ANTEATER_XDG_DATA_HOME="${XDG_DATA_HOME:-$_paths_home/.local/share}"
ANTEATER_XDG_STATE_HOME="${XDG_STATE_HOME:-$_paths_home/.local/state}"

ANTEATER_CONFIG_DIR="$ANTEATER_XDG_CONFIG_HOME/anteater"
ANTEATER_CACHE_DIR="$ANTEATER_XDG_CACHE_HOME/anteater"
ANTEATER_DATA_DIR="$ANTEATER_XDG_DATA_HOME/anteater"
ANTEATER_STATE_DIR="$ANTEATER_XDG_STATE_HOME/anteater"
ANTEATER_LOG_DIR="$ANTEATER_STATE_DIR/logs"

ANTEATER_TRASH_DIR="$ANTEATER_XDG_DATA_HOME/Trash"
ANTEATER_TMP="${TMPDIR:-/tmp}"
ANTEATER_VAR_TMP="/var/tmp"

unset _paths_home

readonly ANTEATER_XDG_CONFIG_HOME ANTEATER_XDG_CACHE_HOME \
    ANTEATER_XDG_DATA_HOME ANTEATER_XDG_STATE_HOME \
    ANTEATER_CONFIG_DIR ANTEATER_CACHE_DIR ANTEATER_DATA_DIR \
    ANTEATER_STATE_DIR ANTEATER_LOG_DIR ANTEATER_TRASH_DIR \
    ANTEATER_TMP ANTEATER_VAR_TMP
