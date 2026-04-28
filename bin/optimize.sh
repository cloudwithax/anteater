#!/bin/bash
# Anteater - Optimize command.
# System maintenance: package caches, journal, fstrim. All require sudo.

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

trap cleanup_temp_files EXIT INT TERM

source "$SCRIPT_DIR/../lib/core/log.sh"
source "$SCRIPT_DIR/../lib/core/sudo.sh"
source "$SCRIPT_DIR/../lib/optimize/tasks.sh"

show_help() {
    echo -e "${PURPLE_BOLD}Anteater Optimize${NC}, Run system maintenance tasks"
    echo ""
    echo -e "${YELLOW}Usage:${NC} aa optimize [options]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --dry-run        Preview commands without running them"
    echo "  --debug          Enable debug logging"
    echo "  --help           Show this help message"
    echo ""
    echo -e "${YELLOW}Tasks (only those with installed tooling are offered):${NC}"
    echo "  * Package caches      pacman / apt / dnf / zypper / xbps / apk / pkg_delete"
    echo "  * Journal vacuum      journalctl --vacuum-time=2weeks"
    echo "  * Failed units        systemctl reset-failed"
    echo "  * Filesystem TRIM     fstrim --all"
    echo ""
    echo -e "${GRAY}All tasks run as root (via sudo) unless ANTEATER_OPTIMIZE_NOSUDO=1.${NC}"
}

main() {
    trap 'show_cursor; exit 130' INT TERM

    for arg in "$@"; do
        case "$arg" in
            --dry-run | -n) export ANTEATER_DRY_RUN=1 ;;
            --debug) export AA_DEBUG=1 ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'aa optimize --help' for usage information."
                exit 1
                ;;
        esac
    done

    export ANTEATER_CURRENT_COMMAND="optimize"
    log_operation_session_start "optimize"

    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
    printf '%sAnteater Optimize%s\n\n' "$PURPLE_BOLD" "$NC"

    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, no commands will be executed"
        echo ""
    fi

    # Pre-flight: surface what's available so the user sees something even if
    # the picker can't run (e.g., no tasks detected).
    local -a available
    mapfile -t available < <(anteater_optimize_available_tasks)
    if [[ ${#available[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No supported maintenance tools detected on this system.${NC}"
        echo "Install one of: pacman, apt-get, dnf, zypper, xbps-remove, apk,"
        echo "or systemd's journalctl/fstrim utilities, then re-run."
        exit 0
    fi

    # Acquire sudo upfront when we'll really run commands. Skip in dry-run
    # and when explicitly bypassed for testing.
    if [[ "${ANTEATER_DRY_RUN:-0}" != "1" && "${ANTEATER_OPTIMIZE_NOSUDO:-0}" != "1" ]]; then
        if ! request_sudo_access "Anteater optimize requires admin access"; then
            log_error "Aborted, admin access denied"
            exit 1
        fi
    fi

    if ! anteater_optimize_run; then
        # User cancelled; exit cleanly without summary.
        exit 0
    fi

    printf '\n'
    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        printf '%s%s%s Dry run complete.%s\n\n' \
            "$GREEN" "$ICON_SUCCESS" "$NC" ""
    else
        local ran="${ANTEATER_OPTIMIZE_RAN:-0}"
        local failed="${ANTEATER_OPTIMIZE_FAILED:-0}"
        if [[ "$failed" -gt 0 ]]; then
            printf '%s%s%s %d task(s) ran, %d failed.%s\n\n' \
                "$YELLOW" "$ICON_WARNING" "$NC" "$ran" "$failed" ""
        else
            printf '%s%s%s %d task(s) completed.%s\n\n' \
                "$GREEN" "$ICON_SUCCESS" "$NC" "$ran" ""
        fi
    fi
}

main "$@"
