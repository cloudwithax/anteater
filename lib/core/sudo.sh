#!/bin/bash
# Sudo Session Manager
# Unified sudo authentication and keepalive management

set -euo pipefail

# ============================================================================
# Password prompt
# ============================================================================

_request_password() {
    local tty_path="$1"

    sudo -k 2> /dev/null

    local stty_orig
    stty_orig=$(stty -g < "$tty_path" 2> /dev/null || echo "")
    trap '[[ -n "${stty_orig:-}" ]] && stty "${stty_orig:-}" < "$tty_path" 2> /dev/null || true' RETURN

    echo -e "${PURPLE}${ICON_ARROW}${NC} Enter your credentials:" > "$tty_path"

    # shellcheck disable=SC2024,SC2094
    # Intentionally route sudo's native prompt to the same TTY device it reads from.
    if sudo -v < "$tty_path" > /dev/null 2> "$tty_path"; then
        return 0
    fi

    return 1
}

request_sudo_access() {
    local prompt_msg="${1:-Admin access required}"

    if sudo -n true 2> /dev/null; then
        return 0
    fi

    # Tests must never trigger real password prompts.
    if [[ "${ANTEATER_TEST_MODE:-0}" == "1" || "${ANTEATER_TEST_NO_AUTH:-0}" == "1" ]]; then
        return 1
    fi

    local tty_path="/dev/tty"
    if [[ ! -r "$tty_path" || ! -w "$tty_path" ]]; then
        tty_path=$(tty 2> /dev/null || echo "")
        if [[ -z "$tty_path" || ! -r "$tty_path" || ! -w "$tty_path" ]]; then
            return 1
        fi
    fi

    sudo -k

    echo -e "${PURPLE}${ICON_ARROW}${NC} ${prompt_msg}"
    if _request_password "$tty_path"; then
        safe_clear_lines 3 "$tty_path"
        return 0
    fi
    return 1
}

# ============================================================================
# Sudo Session Management
# ============================================================================

ANTEATER_SUDO_KEEPALIVE_PID=""
ANTEATER_SUDO_ESTABLISHED="false"

_start_sudo_keepalive() {
    (
        sleep 2

        local retry_count=0
        while true; do
            if ! sudo -n -v 2> /dev/null; then
                retry_count=$((retry_count + 1))
                if [[ $retry_count -ge 3 ]]; then
                    exit 1
                fi
                sleep 5
                continue
            fi
            retry_count=0
            sleep 30
            kill -0 "$$" 2> /dev/null || exit
        done
    ) > /dev/null 2>&1 &

    local pid=$!
    echo $pid
}

_stop_sudo_keepalive() {
    local pid="${1:-}"
    if [[ -n "$pid" ]]; then
        kill "$pid" 2> /dev/null || true
        wait "$pid" 2> /dev/null || true
    fi
}

has_sudo_session() {
    sudo -n true 2> /dev/null
}

request_sudo() {
    local prompt_msg="${1:-Admin access required}"

    if has_sudo_session; then
        return 0
    fi

    if request_sudo_access "$prompt_msg"; then
        return 0
    else
        return 1
    fi
}

ensure_sudo_session() {
    local prompt="${1:-Admin access required}"

    if has_sudo_session && [[ "$ANTEATER_SUDO_ESTABLISHED" == "true" ]]; then
        return 0
    fi

    if [[ "${ANTEATER_TEST_MODE:-0}" == "1" || "${ANTEATER_TEST_NO_AUTH:-0}" == "1" ]]; then
        ANTEATER_SUDO_ESTABLISHED="false"
        return 1
    fi

    if [[ -n "$ANTEATER_SUDO_KEEPALIVE_PID" ]]; then
        _stop_sudo_keepalive "$ANTEATER_SUDO_KEEPALIVE_PID"
        ANTEATER_SUDO_KEEPALIVE_PID=""
    fi

    if ! request_sudo "$prompt"; then
        ANTEATER_SUDO_ESTABLISHED="false"
        return 1
    fi

    ANTEATER_SUDO_KEEPALIVE_PID=$(_start_sudo_keepalive)

    ANTEATER_SUDO_ESTABLISHED="true"
    return 0
}

stop_sudo_session() {
    if [[ -n "$ANTEATER_SUDO_KEEPALIVE_PID" ]]; then
        _stop_sudo_keepalive "$ANTEATER_SUDO_KEEPALIVE_PID"
        ANTEATER_SUDO_KEEPALIVE_PID=""
    fi
    ANTEATER_SUDO_ESTABLISHED="false"
}

register_sudo_cleanup() {
    trap stop_sudo_session EXIT INT TERM
}

will_need_sudo() {
    local -a operations=("$@")
    for op in "${operations[@]}"; do
        case "$op" in
            system_update | firewall | system_fix)
                return 0
                ;;
        esac
    done
    return 1
}
