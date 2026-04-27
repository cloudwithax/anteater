#!/bin/bash
# Anteater - Clean command.
# Removes user-owned caches (thumbnails, browsers, dev tools, trash).

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

trap cleanup_temp_files EXIT INT TERM

source "$SCRIPT_DIR/../lib/core/log.sh"
source "$SCRIPT_DIR/../lib/clean/user.sh"

show_help() {
    echo -e "${PURPLE_BOLD}Anteater Clean${NC}, Remove user-owned caches"
    echo ""
    echo -e "${YELLOW}Usage:${NC} aa clean [options]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --include-cache  Also offer 'Other ~/.cache entries' as a category"
    echo "  --dry-run        Preview clean actions without making changes"
    echo "  --debug          Enable debug logging"
    echo "  --help           Show this help message"
    echo ""
    echo -e "${YELLOW}Default categories:${NC}"
    echo "  * Thumbnail caches  (~/.cache/thumbnails)"
    echo "  * Browser caches    (Chrome, Firefox, Chromium, Brave)"
    echo "  * Developer caches  (npm, pip, yarn, cargo, go-build)"
    echo "  * Trash             (~/.local/share/Trash)"
}

main() {
    trap 'show_cursor; exit 130' INT TERM

    local include_cache=false
    for arg in "$@"; do
        case "$arg" in
            --include-cache) include_cache=true ;;
            --dry-run | -n) export ANTEATER_DRY_RUN=1 ;;
            --debug) export AA_DEBUG=1 ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'aa clean --help' for usage information."
                exit 1
                ;;
        esac
    done

    export ANTEATER_CURRENT_COMMAND="clean"
    log_operation_session_start "clean"

    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
    printf '%sAnteater Clean%s\n\n' "$PURPLE_BOLD" "$NC"

    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, No files will be removed"
        echo ""
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "Measuring categories..."
    fi
    # Pre-warm size lookups so the spinner reflects real work.
    local id
    for id in "${ANTEATER_CLEAN_CATEGORY_IDS[@]}"; do
        anteater_clean_category_size_kb "$id" > /dev/null
    done
    if [[ "$include_cache" == "true" ]]; then
        for id in "${ANTEATER_CLEAN_OPTIONAL_CATEGORY_IDS[@]}"; do
            anteater_clean_category_size_kb "$id" > /dev/null
        done
    fi
    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if ! anteater_clean_run "$include_cache"; then
        echo ""
        printf '%sCancelled.%s\n' "$YELLOW" "$NC"
        log_operation_session_end "clean" 0 0
        exit 0
    fi

    local bytes="${ANTEATER_CLEAN_BYTES:-0}"
    local items="${ANTEATER_CLEAN_ITEMS:-0}"

    local heading="Clean complete"
    [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]] && heading="Dry run complete - no changes made"

    local -a details=()
    if [[ $bytes -gt 0 ]]; then
        local human
        human=$(bytes_to_human "$bytes")
        local line="Space freed: ${GREEN}${human}${NC}"
        [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]] && line="Would free: ${GREEN}${human}${NC}"
        [[ $items -gt 0 ]] && line+=" | Items: $items"
        line+=" | Free: $(get_free_space)"
        details+=("$line")
    else
        details+=("Nothing to clean.")
        details+=("Free space: $(get_free_space)")
    fi

    log_operation_session_end "clean" "$items" "$((bytes / 1024))"
    print_summary_block "$heading" "${details[@]}"
    printf '\n'
}

if [[ "${ANTEATER_SKIP_MAIN:-0}" == "1" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return 0
    else
        exit 0
    fi
fi

main "$@"
