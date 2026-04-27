#!/bin/bash
# User-cache cleaning categories for `aa clean`.
# Linux user-owned paths only. No sudo.

set -euo pipefail

if [[ -n "${ANTEATER_CLEAN_USER_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_CLEAN_USER_LOADED=1

# Stable IDs (order = display order in the picker).
ANTEATER_CLEAN_CATEGORY_IDS=(
    thumbnails
    browser
    dev
    trash
)

# Includes ~/.cache catch-all when --include-cache is passed.
ANTEATER_CLEAN_OPTIONAL_CATEGORY_IDS=(
    misc_cache
)

anteater_clean_category_label() {
    case "$1" in
        thumbnails) printf 'Thumbnail caches' ;;
        browser) printf 'Browser caches' ;;
        dev) printf 'Developer tool caches' ;;
        trash) printf 'Trash' ;;
        misc_cache) printf 'Other ~/.cache entries' ;;
        *) printf '%s' "$1" ;;
    esac
}

anteater_clean_category_description() {
    case "$1" in
        thumbnails) printf '~/.cache/thumbnails' ;;
        browser) printf 'Chrome, Firefox, Chromium, Brave (per-user)' ;;
        dev) printf 'npm, pip, yarn, cargo, go-build' ;;
        trash) printf '~/.local/share/Trash contents' ;;
        misc_cache) printf 'Catch-all under ~/.cache (opt-in)' ;;
        *) printf '' ;;
    esac
}

# Emit candidate paths for a category, one per line.
# Globs are expanded; non-existent paths are filtered.
anteater_clean_category_paths() {
    local id="$1"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

    local -a globs=()
    case "$id" in
        thumbnails)
            globs=("$cache_dir/thumbnails")
            ;;
        browser)
            globs=(
                "$cache_dir/google-chrome"/*/Cache
                "$cache_dir/google-chrome"/*/Code\ Cache
                "$cache_dir/google-chrome"/*/GPUCache
                "$cache_dir/chromium"/*/Cache
                "$cache_dir/chromium"/*/Code\ Cache
                "$cache_dir/chromium"/*/GPUCache
                "$cache_dir/BraveSoftware/Brave-Browser"/*/Cache
                "$cache_dir/BraveSoftware/Brave-Browser"/*/Code\ Cache
                "$cache_dir/BraveSoftware/Brave-Browser"/*/GPUCache
                "$cache_dir/mozilla/firefox"/*/cache2
                "$cache_dir/mozilla/firefox"/*/startupCache
            )
            ;;
        dev)
            globs=(
                "$cache_dir/pip"
                "$cache_dir/yarn"
                "$cache_dir/go-build"
                "$HOME/.npm/_cacache"
                "$HOME/.yarn/cache"
                "$HOME/.cargo/registry/cache"
                "$HOME/.cargo/git/db"
            )
            ;;
        trash)
            globs=(
                "$data_dir/Trash/files"
                "$data_dir/Trash/info"
                "$data_dir/Trash/expunged"
            )
            ;;
        misc_cache)
            anteater_clean_misc_cache_paths
            return 0
            ;;
        *)
            return 0
            ;;
    esac

    local p
    for p in "${globs[@]}"; do
        # Skip unexpanded literal globs (no matches).
        [[ "$p" == *'*'* ]] && continue
        [[ -e "$p" ]] || continue
        printf '%s\n' "$p"
    done
}

# misc_cache: every immediate child of ~/.cache that isn't already covered
# by another category. Skips well-known paths we don't want to touch.
anteater_clean_misc_cache_paths() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    [[ -d "$cache_dir" ]] || return 0

    # Names handled by other categories or known to be unsafe to wipe.
    local -a skip=(
        thumbnails
        google-chrome
        chromium
        BraveSoftware
        mozilla
        pip
        yarn
        go-build
        anteater
        JetBrains
        pypoetry
        ms-playwright
        huggingface
    )

    local entry name match s
    for entry in "$cache_dir"/*; do
        [[ -d "$entry" ]] || continue
        name="${entry##*/}"
        match=false
        for s in "${skip[@]}"; do
            if [[ "$name" == "$s" || "$name" == "$s"* ]]; then
                match=true
                break
            fi
        done
        [[ "$match" == "true" ]] && continue
        printf '%s\n' "$entry"
    done
}

# Sum size in KB across the paths a category resolves to.
anteater_clean_category_size_kb() {
    local id="$1"
    local total=0
    local p kb
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        kb=$(get_path_size_kb "$p" 2> /dev/null || echo 0)
        [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
        total=$((total + kb))
    done < <(anteater_clean_category_paths "$id")
    printf '%s\n' "$total"
}

# Interactive checkbox picker. Reads category IDs from positional args.
# Reads selection state from / writes to global ANTEATER_CLEAN_SELECTED_<id>.
# Returns 0 with selections set, 1 if user cancels.
anteater_clean_select_categories() {
    local -a ids=("$@")
    local n=${#ids[@]}
    [[ $n -eq 0 ]] && return 1

    local -a checked=()
    local -a sizes_kb=()
    local i kb size_str label desc
    for ((i = 0; i < n; i++)); do
        kb=$(anteater_clean_category_size_kb "${ids[i]}")
        sizes_kb+=("$kb")
        # Default-enable categories that found something to clean.
        if [[ $kb -gt 0 ]]; then
            checked+=(true)
        else
            checked+=(false)
        fi
    done

    if [[ ! -t 0 || ! -t 1 ]]; then
        # Non-interactive: pick everything that has data.
        for ((i = 0; i < n; i++)); do
            if [[ "${checked[i]}" == "true" ]]; then
                eval "ANTEATER_CLEAN_SELECTED_${ids[i]}=1"
            else
                eval "ANTEATER_CLEAN_SELECTED_${ids[i]}=0"
            fi
        done
        return 0
    fi

    local original_stty=""
    if command -v stty > /dev/null 2>&1; then
        original_stty=$(stty -g 2> /dev/null || echo "")
    fi
    local restored=false
    _clean_restore() {
        [[ "$restored" == "true" ]] && return
        restored=true
        show_cursor
        if [[ -n "$original_stty" ]]; then
            stty "$original_stty" 2> /dev/null || stty sane 2> /dev/null || true
        fi
    }
    # shellcheck disable=SC2329
    _clean_interrupt() {
        _clean_restore
        exit 130
    }
    trap _clean_interrupt INT TERM
    hide_cursor

    local cursor=0
    local first_draw=true

    _clean_draw() {
        if [[ "$first_draw" == "true" ]]; then
            first_draw=false
        else
            # header(2) + n rows + footer(1) trailing blank
            printf '\033[%dA' $((n + 3))
        fi
        printf '\r\033[2K%s%s%s\n' "$BLUE" "Select categories to clean" "$NC"
        printf '\r\033[2K%sSpace toggles · Enter confirms · q cancels%s\n' "$GRAY" "$NC"
        for ((i = 0; i < n; i++)); do
            local marker="$ICON_EMPTY"
            [[ "${checked[i]}" == "true" ]] && marker="$ICON_SOLID"
            label="$(anteater_clean_category_label "${ids[i]}")"
            desc="$(anteater_clean_category_description "${ids[i]}")"
            if [[ "${sizes_kb[i]}" -gt 0 ]]; then
                size_str="$(bytes_to_human_kb "${sizes_kb[i]}")"
            else
                size_str="empty"
            fi
            local prefix="  "
            local style=""
            if [[ $i -eq $cursor ]]; then
                prefix="${PURPLE}${ICON_ARROW}${NC} "
                style="${PURPLE_BOLD}"
            fi
            printf '\r\033[2K%s%s%s %s%-26s%s %s(%s)%s %s%s%s\n' \
                "$prefix" "$style" "$marker" "$NC" "$label" "$NC" \
                "$GRAY" "$size_str" "$NC" \
                "$GRAY" "$desc" "$NC"
        done
        printf '\r\033[2K\n'
    }

    while true; do
        _clean_draw
        local key
        if ! key=$(read_key); then
            continue
        fi
        case "$key" in
            UP) ((cursor > 0)) && ((cursor--)) ;;
            DOWN) ((cursor < n - 1)) && ((cursor++)) ;;
            SPACE)
                if [[ "${checked[cursor]}" == "true" ]]; then
                    checked[cursor]=false
                else
                    checked[cursor]=true
                fi
                ;;
            ENTER) break ;;
            QUIT)
                _clean_restore
                trap - INT TERM
                return 1
                ;;
        esac
    done

    _clean_restore
    trap - INT TERM

    local any_selected=false
    for ((i = 0; i < n; i++)); do
        if [[ "${checked[i]}" == "true" ]]; then
            eval "ANTEATER_CLEAN_SELECTED_${ids[i]}=1"
            any_selected=true
        else
            eval "ANTEATER_CLEAN_SELECTED_${ids[i]}=0"
        fi
    done

    [[ "$any_selected" == "true" ]] || return 1
    return 0
}

# Apply selection: delete paths under each selected category.
# Writes totals to globals ANTEATER_CLEAN_BYTES / ANTEATER_CLEAN_ITEMS.
anteater_clean_apply() {
    local -a ids=("$@")
    local total_kb=0
    local total_items=0
    local id selected p kb
    local stats_dir="${XDG_CACHE_HOME:-$HOME/.cache}/anteater"
    ensure_user_dir "$stats_dir"

    for id in "${ids[@]}"; do
        selected=""
        eval "selected=\${ANTEATER_CLEAN_SELECTED_${id}:-0}"
        [[ "$selected" == "1" ]] || continue

        local label
        label="$(anteater_clean_category_label "$id")"
        printf '\n%s━━━ %s ━━━%s\n' "$BLUE" "$label" "$NC"

        while IFS= read -r p; do
            [[ -z "$p" || ! -e "$p" ]] && continue
            kb=$(get_path_size_kb "$p" 2> /dev/null || echo 0)
            [[ "$kb" =~ ^[0-9]+$ ]] || kb=0

            local display="${p/#$HOME/\~}"
            if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
                printf '  %s%s%s %sWould remove%s %s (%s)\n' \
                    "$GRAY" "$ICON_DRY_RUN" "$NC" "$YELLOW" "$NC" \
                    "$display" "$(bytes_to_human_kb "$kb")"
            else
                if safe_remove "$p" true; then
                    printf '  %s%s%s removed %s (%s)\n' \
                        "$GREEN" "$ICON_SUCCESS" "$NC" \
                        "$display" "$(bytes_to_human_kb "$kb")"
                    total_kb=$((total_kb + kb))
                    total_items=$((total_items + 1))
                else
                    printf '  %s%s%s failed %s\n' \
                        "$RED" "$ICON_ERROR" "$NC" "$display"
                    continue
                fi
            fi

            if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
                total_kb=$((total_kb + kb))
                total_items=$((total_items + 1))
            fi
        done < <(anteater_clean_category_paths "$id")
    done

    ANTEATER_CLEAN_BYTES=$((total_kb * 1024))
    ANTEATER_CLEAN_ITEMS=$total_items
    export ANTEATER_CLEAN_BYTES ANTEATER_CLEAN_ITEMS
}

# Top-level orchestrator called by bin/clean.sh.
# Returns 0 on success (even if nothing cleaned), 1 on user cancel.
anteater_clean_run() {
    local include_misc="${1:-false}"
    local -a ids=("${ANTEATER_CLEAN_CATEGORY_IDS[@]}")
    if [[ "$include_misc" == "true" ]]; then
        ids+=("${ANTEATER_CLEAN_OPTIONAL_CATEGORY_IDS[@]}")
    fi

    if ! anteater_clean_select_categories "${ids[@]}"; then
        return 1
    fi

    anteater_clean_apply "${ids[@]}"
    return 0
}
