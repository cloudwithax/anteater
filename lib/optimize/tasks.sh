#!/bin/bash
# System maintenance tasks for `aa optimize`.
# Each task is a (label, description, detect, run) tuple keyed by ID.
# All tasks require root; the apply layer shells out via sudo.

set -euo pipefail

if [[ -n "${ANTEATER_OPTIMIZE_TASKS_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_OPTIMIZE_TASKS_LOADED=1

# Stable IDs (display order). Detection filters to what's installed.
ANTEATER_OPTIMIZE_TASK_IDS=(
    pacman_cache
    apt_cache
    dnf_cache
    zypper_cache
    xbps_cache
    apk_cache
    pkg_openbsd
    journal_vacuum
    failed_units
    fstrim
)

anteater_optimize_task_label() {
    case "$1" in
        pacman_cache) printf 'Pacman cache' ;;
        apt_cache) printf 'APT cache' ;;
        dnf_cache) printf 'DNF cache' ;;
        zypper_cache) printf 'Zypper cache' ;;
        xbps_cache) printf 'XBPS cache' ;;
        apk_cache) printf 'APK cache' ;;
        pkg_openbsd) printf 'OpenBSD pkg cache' ;;
        journal_vacuum) printf 'systemd journal' ;;
        failed_units) printf 'Failed systemd units' ;;
        fstrim) printf 'Filesystem TRIM' ;;
        *) printf '%s' "$1" ;;
    esac
}

anteater_optimize_task_description() {
    case "$1" in
        pacman_cache) printf 'paccache -rk1 then pacman -Sc' ;;
        apt_cache) printf 'apt-get clean && apt-get autoclean' ;;
        dnf_cache) printf 'dnf clean all' ;;
        zypper_cache) printf 'zypper clean --all' ;;
        xbps_cache) printf 'xbps-remove -Oo' ;;
        apk_cache) printf 'apk cache clean' ;;
        pkg_openbsd) printf 'pkg_delete -a (autoremove orphans)' ;;
        journal_vacuum) printf 'journalctl --vacuum-time=2weeks' ;;
        failed_units) printf 'systemctl reset-failed' ;;
        fstrim) printf 'fstrim --all --verbose' ;;
        *) printf '' ;;
    esac
}

# Allow tests to override $PATH-based detection.
ANTEATER_OPTIMIZE_PATH="${ANTEATER_OPTIMIZE_PATH:-}"

_optimize_have() {
    if [[ -n "$ANTEATER_OPTIMIZE_PATH" ]]; then
        PATH="$ANTEATER_OPTIMIZE_PATH" command -v "$1" > /dev/null 2>&1
    else
        command -v "$1" > /dev/null 2>&1
    fi
}

# Returns 0 if the task is available on this system.
anteater_optimize_task_available() {
    case "$1" in
        pacman_cache) _optimize_have pacman ;;
        apt_cache) _optimize_have apt-get ;;
        dnf_cache) _optimize_have dnf ;;
        zypper_cache) _optimize_have zypper ;;
        xbps_cache) _optimize_have xbps-remove ;;
        apk_cache) _optimize_have apk ;;
        pkg_openbsd) _optimize_have pkg_delete ;;
        journal_vacuum) _optimize_have journalctl ;;
        failed_units) _optimize_have systemctl ;;
        fstrim) _optimize_have fstrim ;;
        *) return 1 ;;
    esac
}

# Echo only the IDs for which tooling exists, preserving display order.
anteater_optimize_available_tasks() {
    local id
    for id in "${ANTEATER_OPTIMIZE_TASK_IDS[@]}"; do
        if anteater_optimize_task_available "$id"; then
            printf '%s\n' "$id"
        fi
    done
}

# Returns the shell command (as one string) the task would execute.
# These are the commands previewed in --dry-run.
anteater_optimize_task_command() {
    case "$1" in
        pacman_cache)
            if _optimize_have paccache; then
                printf 'paccache -rk1 && pacman -Sc --noconfirm'
            else
                printf 'pacman -Sc --noconfirm'
            fi
            ;;
        apt_cache) printf 'apt-get clean && apt-get autoclean -y' ;;
        dnf_cache) printf 'dnf clean all' ;;
        zypper_cache) printf 'zypper --non-interactive clean --all' ;;
        xbps_cache) printf 'xbps-remove -Oo' ;;
        apk_cache) printf 'apk cache clean' ;;
        pkg_openbsd) printf 'pkg_delete -a' ;;
        journal_vacuum) printf 'journalctl --vacuum-time=2weeks' ;;
        failed_units) printf 'systemctl reset-failed' ;;
        fstrim) printf 'fstrim --all --verbose' ;;
        *) return 1 ;;
    esac
}

# Run a single task. Honors $ANTEATER_DRY_RUN. Returns:
#   0 success (or dry-run preview); 1 failure.
# Output is printed inline; callers print section headers.
anteater_optimize_run_task() {
    local id="$1"
    local cmd
    cmd=$(anteater_optimize_task_command "$id") || {
        printf '  %s%s%s unknown task: %s\n' "${RED:-}" "${ICON_ERROR:-x}" "${NC:-}" "$id"
        return 1
    }

    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        printf '  %s%s%s would run: %s%s%s\n' \
            "${GRAY:-}" "${ICON_DRY_RUN:-→}" "${NC:-}" \
            "${YELLOW:-}" "$cmd" "${NC:-}"
        return 0
    fi

    # Allow tests to bypass sudo (and execute the cmd as-is).
    local runner="sudo"
    if [[ "${ANTEATER_OPTIMIZE_NOSUDO:-0}" == "1" ]]; then
        runner=""
    fi

    local rc=0
    if [[ -n "$runner" ]]; then
        $runner bash -c "$cmd" || rc=$?
    else
        bash -c "$cmd" || rc=$?
    fi

    if [[ $rc -eq 0 ]]; then
        printf '  %s%s%s ran %s\n' "${GREEN:-}" "${ICON_SUCCESS:-✓}" "${NC:-}" "$cmd"
    else
        printf '  %s%s%s failed (rc=%d) %s\n' \
            "${RED:-}" "${ICON_ERROR:-x}" "${NC:-}" "$rc" "$cmd"
    fi
    return $rc
}

# Interactive checkbox picker mirroring anteater_clean_select_categories.
# Reads task IDs from positional args. Sets ANTEATER_OPTIMIZE_SELECTED_<id>.
# Returns 0 with at least one selection; 1 if user cancels or no selection.
anteater_optimize_select_tasks() {
    local -a ids=("$@")
    local n=${#ids[@]}
    [[ $n -eq 0 ]] && return 1

    local -a checked=()
    local i
    for ((i = 0; i < n; i++)); do
        # Default OFF: optimize tasks touch system state, opt-in is safer.
        checked+=(false)
    done

    if [[ ! -t 0 || ! -t 1 ]]; then
        # Non-interactive: select nothing and return cancel-style status so
        # the caller can decide to abort.
        for ((i = 0; i < n; i++)); do
            eval "ANTEATER_OPTIMIZE_SELECTED_${ids[i]}=0"
        done
        return 1
    fi

    local original_stty=""
    if command -v stty > /dev/null 2>&1; then
        original_stty=$(stty -g 2> /dev/null || echo "")
    fi
    local restored=false
    _optimize_restore() {
        [[ "$restored" == "true" ]] && return
        restored=true
        show_cursor
        if [[ -n "$original_stty" ]]; then
            stty "$original_stty" 2> /dev/null || stty sane 2> /dev/null || true
        fi
    }
    # shellcheck disable=SC2329
    _optimize_interrupt() {
        _optimize_restore
        exit 130
    }
    trap _optimize_interrupt INT TERM
    hide_cursor

    local cursor=0
    local first_draw=true

    _optimize_draw() {
        if [[ "$first_draw" == "true" ]]; then
            first_draw=false
        else
            printf '\033[%dA' $((n + 3))
        fi
        printf '\r\033[2K%s%s%s\n' "$BLUE" "Select maintenance tasks (require sudo)" "$NC"
        printf '\r\033[2K%sSpace toggles · Enter confirms · q cancels%s\n' "$GRAY" "$NC"
        local label desc prefix style marker
        for ((i = 0; i < n; i++)); do
            marker="$ICON_EMPTY"
            [[ "${checked[i]}" == "true" ]] && marker="$ICON_SOLID"
            label="$(anteater_optimize_task_label "${ids[i]}")"
            desc="$(anteater_optimize_task_description "${ids[i]}")"
            prefix="  "
            style=""
            if [[ $i -eq $cursor ]]; then
                prefix="${PURPLE}${ICON_ARROW}${NC} "
                style="${PURPLE_BOLD}"
            fi
            printf '\r\033[2K%s%s%s %s%-22s%s %s%s%s\n' \
                "$prefix" "$style" "$marker" "$NC" "$label" "$NC" \
                "$GRAY" "$desc" "$NC"
        done
        printf '\r\033[2K\n'
    }

    while true; do
        _optimize_draw
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
                _optimize_restore
                trap - INT TERM
                return 1
                ;;
        esac
    done

    _optimize_restore
    trap - INT TERM

    local any=false
    for ((i = 0; i < n; i++)); do
        if [[ "${checked[i]}" == "true" ]]; then
            eval "ANTEATER_OPTIMIZE_SELECTED_${ids[i]}=1"
            any=true
        else
            eval "ANTEATER_OPTIMIZE_SELECTED_${ids[i]}=0"
        fi
    done

    [[ "$any" == "true" ]] || return 1
    return 0
}

# Apply the selected tasks. Honors $ANTEATER_DRY_RUN.
# Sets ANTEATER_OPTIMIZE_RAN / ANTEATER_OPTIMIZE_FAILED counters.
anteater_optimize_apply() {
    local -a ids=("$@")
    local id selected ran=0 failed=0
    for id in "${ids[@]}"; do
        selected=""
        eval "selected=\${ANTEATER_OPTIMIZE_SELECTED_${id}:-0}"
        [[ "$selected" == "1" ]] || continue

        local label
        label="$(anteater_optimize_task_label "$id")"
        printf '\n%s━━━ %s ━━━%s\n' "$BLUE" "$label" "$NC"

        if anteater_optimize_run_task "$id"; then
            ran=$((ran + 1))
        else
            failed=$((failed + 1))
        fi
    done
    ANTEATER_OPTIMIZE_RAN=$ran
    ANTEATER_OPTIMIZE_FAILED=$failed
    export ANTEATER_OPTIMIZE_RAN ANTEATER_OPTIMIZE_FAILED
    return 0
}

# Top-level orchestrator called by bin/optimize.sh.
# Returns 0 on success (or successful dry-run), 1 on user cancel.
anteater_optimize_run() {
    local -a ids
    mapfile -t ids < <(anteater_optimize_available_tasks)
    if [[ ${#ids[@]} -eq 0 ]]; then
        printf '%sNo supported maintenance tools detected on this system.%s\n' \
            "${YELLOW:-}" "${NC:-}"
        return 0
    fi

    if ! anteater_optimize_select_tasks "${ids[@]}"; then
        return 1
    fi

    anteater_optimize_apply "${ids[@]}"
    return 0
}
