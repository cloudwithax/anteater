#!/bin/bash
# Anteater - Analyze command (wrapper).
# Lazy-builds the cmd/aa-analyze Go binary on first use, then execs it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common.sh for spinner/log helpers when present, but tolerate its
# absence so this wrapper works in raw checkouts during development.
if [[ -f "$ROOT_DIR/lib/core/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/core/common.sh"
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/anteater/bin"
BINARY="$CACHE_DIR/aa-analyze"
SOURCE_DIR="$ROOT_DIR/cmd/aa-analyze"
INTERNAL_DIR="$ROOT_DIR/internal/analyze"

needs_rebuild() {
    [[ ! -x "$BINARY" ]] && return 0

    # Rebuild if any tracked Go source is newer than the binary.
    local newest
    newest=$(find "$SOURCE_DIR" "$INTERNAL_DIR" "$ROOT_DIR/go.mod" "$ROOT_DIR/go.sum" \
        -type f -newer "$BINARY" 2> /dev/null | head -1)
    [[ -n "$newest" ]]
}

build_binary() {
    if ! command -v go > /dev/null 2>&1; then
        printf '%saa analyze requires Go to build.%s\n' \
            "${RED:-}" "${NC:-}" >&2
        printf 'Install Go (https://go.dev/dl/) and re-run.\n' >&2
        exit 1
    fi

    mkdir -p "$CACHE_DIR"

    local building_msg="Building aa-analyze..."
    if [[ -t 1 ]] && declare -F start_inline_spinner > /dev/null 2>&1; then
        start_inline_spinner "$building_msg"
        local rc=0
        (cd "$ROOT_DIR" && go build -trimpath -o "$BINARY" ./cmd/aa-analyze) || rc=$?
        stop_inline_spinner
        if [[ $rc -ne 0 ]]; then
            printf '%sBuild failed.%s Re-run with go build for details.\n' \
                "${RED:-}" "${NC:-}" >&2
            exit 1
        fi
    else
        echo "$building_msg" >&2
        if ! (cd "$ROOT_DIR" && go build -trimpath -o "$BINARY" ./cmd/aa-analyze); then
            echo "Build failed." >&2
            exit 1
        fi
    fi
}

if [[ "${1:-}" == "--rebuild" ]]; then
    rm -f "$BINARY"
    shift
fi

if needs_rebuild; then
    build_binary
fi

exec "$BINARY" "$@"
