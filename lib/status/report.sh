#!/bin/bash
# Anteater - Status report builders.
# Linux reads /proc + df + free; OpenBSD falls back to sysctl/swapctl.

if [[ -n "${ANTEATER_STATUS_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_STATUS_LOADED=1

# Pretty-print a section header (matches start_section style without
# resetting TRACK_SECTION state).
status_section() {
    local title="$1"
    printf '\n%s%s %s%s\n' "${PURPLE_BOLD:-}" "${ICON_ARROW:-▶}" "$title" "${NC:-}"
}

status_kv() {
    local key="$1" val="$2"
    printf '  %s%-14s%s %s\n' "${GRAY:-}" "$key" "${NC:-}" "$val"
}

status_bar() {
    local pct="$1"
    local width="${2:-20}"
    local filled
    filled=$((pct * width / 100))
    [[ $filled -lt 0 ]] && filled=0
    [[ $filled -gt $width ]] && filled=$width
    local empty=$((width - filled))
    local color="${GREEN:-}"
    if [[ $pct -ge 90 ]]; then
        color="${RED:-}"
    elif [[ $pct -ge 75 ]]; then
        color="${YELLOW:-}"
    fi
    printf '%s' "$color"
    printf '%0.s█' $(seq 1 $filled 2> /dev/null)
    printf '%s' "${GRAY:-}"
    printf '%0.s░' $(seq 1 $empty 2> /dev/null)
    printf '%s' "${NC:-}"
}

# --- system facts ---------------------------------------------------------

status_uptime() {
    local up=""
    if [[ -r /proc/uptime ]]; then
        local secs
        secs=$(awk '{print int($1)}' /proc/uptime 2> /dev/null || echo 0)
        local d=$((secs / 86400))
        local h=$(((secs % 86400) / 3600))
        local m=$(((secs % 3600) / 60))
        if [[ $d -gt 0 ]]; then
            up="${d}d ${h}h ${m}m"
        elif [[ $h -gt 0 ]]; then
            up="${h}h ${m}m"
        else
            up="${m}m"
        fi
    elif command -v uptime > /dev/null 2>&1; then
        up=$(uptime | sed -E 's/.*up[[:space:]]+([^,]+),.*/\1/' | xargs)
    fi
    [[ -z "$up" ]] && up="unknown"
    printf '%s' "$up"
}

status_loadavg() {
    if [[ -r /proc/loadavg ]]; then
        awk '{print $1" "$2" "$3}' /proc/loadavg
    elif command -v sysctl > /dev/null 2>&1; then
        sysctl -n vm.loadavg 2> /dev/null | awk '{print $2" "$3" "$4}'
    else
        printf '%s' "unknown"
    fi
}

status_render_system() {
    status_section "System"
    status_kv "Host" "$(uname -n 2> /dev/null || echo unknown)"
    status_kv "OS" "${ANTEATER_OS_NAME:-unknown}"
    status_kv "Kernel" "${ANTEATER_KERNEL:-unknown}"
    status_kv "Arch" "${ANTEATER_ARCH:-unknown}"
    status_kv "Init" "${ANTEATER_INIT:-unknown}"
    status_kv "Uptime" "$(status_uptime)"
    status_kv "Load avg" "$(status_loadavg)"
}

# --- memory ---------------------------------------------------------------

# Linux /proc/meminfo path (override-able for tests).
ANTEATER_STATUS_MEMINFO="${ANTEATER_STATUS_MEMINFO:-/proc/meminfo}"

# Print "total used available swap_total swap_used" in KiB.
# Returns empty values when source data is unavailable.
status_memory_kib() {
    if [[ -r "$ANTEATER_STATUS_MEMINFO" ]]; then
        awk '
            /^MemTotal:/ {total=$2}
            /^MemAvailable:/ {avail=$2}
            /^SwapTotal:/ {st=$2}
            /^SwapFree:/ {sf=$2}
            END {
                used = (total != "" && avail != "") ? (total - avail) : ""
                sused = (st != "" && sf != "") ? (st - sf) : ""
                printf "%s %s %s %s %s\n", total, used, avail, st, sused
            }
        ' "$ANTEATER_STATUS_MEMINFO"
    elif command -v sysctl > /dev/null 2>&1; then
        # OpenBSD: hw.physmem (bytes), no MemAvailable equivalent.
        local total_b avail_b
        total_b=$(sysctl -n hw.physmem 2> /dev/null || echo "")
        avail_b=$(sysctl -n hw.usermem 2> /dev/null || echo "")
        local total="" avail="" used=""
        if [[ -n "$total_b" ]]; then total=$((total_b / 1024)); fi
        if [[ -n "$avail_b" ]]; then avail=$((avail_b / 1024)); fi
        if [[ -n "$total" && -n "$avail" ]]; then used=$((total - avail)); fi
        local st="" sused=""
        if command -v swapctl > /dev/null 2>&1; then
            local st_blocks sused_blocks
            read -r st_blocks sused_blocks _ < <(swapctl -s 2> /dev/null \
                | awk '/total:/ {print $2, $4}')
            if [[ "$st_blocks" =~ ^[0-9]+$ ]]; then st=$((st_blocks / 2)); fi
            if [[ "$sused_blocks" =~ ^[0-9]+$ ]]; then sused=$((sused_blocks / 2)); fi
        fi
        printf '%s %s %s %s %s\n' "$total" "$used" "$avail" "$st" "$sused"
    else
        printf ' \n'
    fi
}

status_render_memory() {
    status_section "Memory"
    local line total used avail st sused
    line=$(status_memory_kib)
    read -r total used avail st sused <<< "$line"

    if [[ -z "$total" || ! "$total" =~ ^[0-9]+$ ]]; then
        status_kv "RAM" "unavailable"
        return
    fi

    local used_h avail_h total_h pct
    used_h=$(bytes_to_human_kb "$used")
    avail_h=$(bytes_to_human_kb "$avail")
    total_h=$(bytes_to_human_kb "$total")
    pct=$((used * 100 / total))
    status_kv "RAM" "$(status_bar "$pct") $pct% ($used_h used / $total_h)"
    status_kv "Available" "$avail_h"

    if [[ -n "$st" && "$st" =~ ^[0-9]+$ && $st -gt 0 ]]; then
        local sused_h st_h spct
        sused_h=$(bytes_to_human_kb "${sused:-0}")
        st_h=$(bytes_to_human_kb "$st")
        spct=$((${sused:-0} * 100 / st))
        status_kv "Swap" "$(status_bar "$spct") $spct% ($sused_h / $st_h)"
    else
        status_kv "Swap" "none"
    fi
}

# --- disks ----------------------------------------------------------------

# Path to df binary; tests may override.
ANTEATER_STATUS_DF="${ANTEATER_STATUS_DF:-df}"

status_render_disks() {
    status_section "Disks"
    if ! command -v "$ANTEATER_STATUS_DF" > /dev/null 2>&1; then
        status_kv "df" "unavailable"
        return
    fi

    local lines
    # POSIX -P keeps a single record per filesystem; -k makes Use% computable;
    # -T (GNU) gives type column but isn't portable, so skip it.
    lines=$("$ANTEATER_STATUS_DF" -Pk 2> /dev/null | awk 'NR>1') || return 0

    # Dedupe by source device: keep the row with the shortest mount path so
    # btrfs subvolumes / bind mounts collapse to their canonical mount.
    declare -A seen_dev_mount=()
    local kept=""
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        local fs blocks used avail capacity mount
        read -r fs blocks used avail capacity mount <<< "$row"
        case "$mount" in
            /proc | /proc/* | /sys | /sys/* | /dev | /dev/* | /run | /run/* \
                | /tmp/snap.* | /var/lib/docker/* | /var/lib/snapd/*)
                continue
                ;;
        esac
        case "$fs" in
            tmpfs | devtmpfs | overlay | aufs | squashfs | none) continue ;;
        esac
        local prev="${seen_dev_mount[$fs]:-}"
        if [[ -z "$prev" || ${#mount} -lt ${#prev} ]]; then
            seen_dev_mount[$fs]="$mount"
        fi
    done <<< "$lines"

    local printed=0
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        local fs blocks used avail capacity mount
        read -r fs blocks used avail capacity mount <<< "$row"
        [[ "${seen_dev_mount[$fs]:-}" == "$mount" ]] || continue

        local pct="${capacity%\%}"
        [[ "$pct" =~ ^[0-9]+$ ]] || continue

        local used_h avail_h total_h
        used_h=$(bytes_to_human_kb "$used")
        avail_h=$(bytes_to_human_kb "$avail")
        total_h=$(bytes_to_human_kb "$blocks")
        printf '  %s%-22s%s %s %3s%% (%s used, %s free of %s)\n' \
            "${GRAY:-}" "$mount" "${NC:-}" "$(status_bar "$pct")" \
            "$pct" "$used_h" "$avail_h" "$total_h"
        printed=$((printed + 1))
    done <<< "$lines"

    if [[ $printed -eq 0 ]]; then
        status_kv "Disks" "no real filesystems detected"
    fi
}

# --- anteater stats -------------------------------------------------------

status_dir_size_h() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        printf '%s' "0B"
        return
    fi
    local kb
    kb=$(du -sk "$dir" 2> /dev/null | awk '{print $1}')
    [[ -z "$kb" ]] && kb=0
    bytes_to_human_kb "$kb"
}

status_render_anteater() {
    status_section "Anteater"
    local cache_dir log_dir config_dir
    cache_dir="${ANTEATER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/anteater}"
    log_dir="${ANTEATER_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/anteater/logs}"
    config_dir="${ANTEATER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/anteater}"

    status_kv "Version" "${VERSION:-unknown}"
    status_kv "Cache" "$cache_dir ($(status_dir_size_h "$cache_dir"))"
    status_kv "Logs" "$log_dir ($(status_dir_size_h "$log_dir"))"
    status_kv "Config" "$config_dir"

    # Most recent op from the log file, if any.
    local op_log="$log_dir/operations.log"
    if [[ -r "$op_log" ]]; then
        local last
        last=$(tail -1 "$op_log" 2> /dev/null || true)
        if [[ -n "$last" ]]; then
            status_kv "Last op" "$last"
        fi
    fi
    return 0
}

# Top-level driver.
status_render_all() {
    status_render_system
    status_render_memory
    status_render_disks
    status_render_anteater
    printf '\n'
}
