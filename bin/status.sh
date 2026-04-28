#!/bin/bash
# Anteater - Status command.
# Snapshot of system + anteater health.

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/core/platform.sh"
source "$SCRIPT_DIR/../lib/status/report.sh"

trap cleanup_temp_files EXIT INT TERM

# Make $VERSION discoverable for the report (the main entrypoint exports it,
# but bin/status.sh may be invoked standalone).
if [[ -z "${VERSION:-}" && -f "$SCRIPT_DIR/../anteater" ]]; then
    VERSION=$(grep '^VERSION=' "$SCRIPT_DIR/../anteater" | head -1 \
        | sed 's/VERSION="\(.*\)"/\1/')
fi

show_help() {
    echo -e "${PURPLE_BOLD}Anteater Status${NC}, Snapshot of system health"
    echo ""
    echo -e "${YELLOW}Usage:${NC} aa status [options]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --help    Show this help message"
    echo ""
    echo -e "${YELLOW}Sections:${NC}"
    echo "  * System    Distro, kernel, init, uptime, load avg"
    echo "  * Memory    RAM and swap utilization"
    echo "  * Disks     Real filesystem usage"
    echo "  * Anteater  Cache/log paths and last operation"
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                show_help
                exit 0
                ;;
            --debug) export AA_DEBUG=1 ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'aa status --help' for usage information."
                exit 1
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
    printf '%sAnteater Status%s\n' "$PURPLE_BOLD" "$NC"

    status_render_all
}

main "$@"
