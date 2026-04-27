#!/bin/bash
# Anteater - Platform Detection
# OS / distro / init / package-manager / desktop fingerprint.
#
# After sourcing, the following readonly globals are populated:
#
#   ANTEATER_OS_KIND        linux | openbsd
#   ANTEATER_OS_NAME        Human-readable, e.g. "CachyOS", "Ubuntu 24.04", "OpenBSD 7.5"
#   ANTEATER_DISTRO_ID      Canonical id from /etc/os-release (linux) or "openbsd"
#   ANTEATER_DISTRO_LIKE    Space-joined ID_LIKE chain ("" if none)
#   ANTEATER_DISTRO_VERSION VERSION_ID from os-release, or `uname -r` for openbsd
#   ANTEATER_INIT           systemd | openrc | runit | s6 | dinit | bsd-rc | unknown
#   ANTEATER_DESKTOP        gnome | kde | xfce | sway | hyprland | i3 | ... | unknown
#   ANTEATER_SHELL_KIND     bash | zsh | fish | unknown (login shell of $USER)
#   ANTEATER_PKG_MGRS       Space-joined list of detected package managers
#   ANTEATER_ARCH           uname -m
#   ANTEATER_KERNEL         uname -r
#
# Helpers (all return 0 on match, 1 otherwise):
#
#   platform_is_linux
#   platform_is_openbsd
#   platform_distro_is <id>      Matches ID or any ID_LIKE entry
#   platform_init_is <name>
#   platform_has_pkg_mgr <name>
#
# Test overrides (honored only when set):
#   ANTEATER_PLATFORM_OS_RELEASE_FILE  Alternate path to os-release fixture
#   ANTEATER_PLATFORM_UNAME_S          Override `uname -s` (linux|openbsd|...)
#   ANTEATER_PLATFORM_PATH             Override $PATH for pkg-mgr detection

set -euo pipefail

if [[ -n "${ANTEATER_PLATFORM_LOADED:-}" ]]; then
    return 0
fi
readonly ANTEATER_PLATFORM_LOADED=1

# ============================================================================
# Internal helpers
# ============================================================================

_platform_uname_s() {
    if [[ -n "${ANTEATER_PLATFORM_UNAME_S:-}" ]]; then
        printf '%s\n' "$ANTEATER_PLATFORM_UNAME_S"
    else
        uname -s 2> /dev/null || echo "unknown"
    fi
}

_platform_lc() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Read a single key from a freedesktop-style key=value file.
# Strips surrounding quotes. Empty string if not found.
_platform_read_kv() {
    local file="$1" key="$2" line value
    [[ -r "$file" ]] || return 0
    line=$(grep -E "^${key}=" "$file" 2> /dev/null | head -n1) || true
    [[ -z "$line" ]] && return 0
    value="${line#${key}=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s\n' "$value"
}

_platform_have_cmd() {
    local cmd="$1"
    if [[ -n "${ANTEATER_PLATFORM_PATH:-}" ]]; then
        PATH="$ANTEATER_PLATFORM_PATH" command -v "$cmd" > /dev/null 2>&1
    else
        command -v "$cmd" > /dev/null 2>&1
    fi
}

# ============================================================================
# Detection
# ============================================================================

_platform_detect_os_kind() {
    local s
    s=$(_platform_lc "$(_platform_uname_s)")
    case "$s" in
        linux) echo "linux" ;;
        openbsd) echo "openbsd" ;;
        *) echo "unknown" ;;
    esac
}

_platform_detect_distro_linux() {
    # Sets three globals on caller via stdout: id|like|version|name
    local os_release="${ANTEATER_PLATFORM_OS_RELEASE_FILE:-/etc/os-release}"
    local id="" like="" version="" pretty=""

    if [[ -r "$os_release" ]]; then
        id=$(_platform_read_kv "$os_release" "ID")
        like=$(_platform_read_kv "$os_release" "ID_LIKE")
        version=$(_platform_read_kv "$os_release" "VERSION_ID")
        pretty=$(_platform_read_kv "$os_release" "PRETTY_NAME")
        [[ -z "$pretty" ]] && pretty=$(_platform_read_kv "$os_release" "NAME")
    fi

    # Legacy fallbacks for systems without os-release. Skipped when the test
    # override is in effect so fixtures don't accidentally read host files.
    if [[ -z "${ANTEATER_PLATFORM_OS_RELEASE_FILE:-}" ]]; then
        if [[ -z "$id" && -r /etc/lsb-release ]]; then
            id=$(_platform_lc "$(_platform_read_kv /etc/lsb-release DISTRIB_ID)")
            version=$(_platform_read_kv /etc/lsb-release DISTRIB_RELEASE)
            pretty=$(_platform_read_kv /etc/lsb-release DISTRIB_DESCRIPTION)
        fi
        if [[ -z "$id" && -r /etc/debian_version ]]; then
            id="debian"
            version=$(< /etc/debian_version)
        fi
        if [[ -z "$id" && -r /etc/redhat-release ]]; then
            id="rhel"
            pretty=$(< /etc/redhat-release)
        fi
    fi

    [[ -z "$id" ]] && id="unknown"
    [[ -z "$pretty" ]] && pretty="$id"

    printf '%s|%s|%s|%s\n' "$id" "$like" "$version" "$pretty"
}

_platform_detect_distro_openbsd() {
    local version
    version=$(uname -r 2> /dev/null || echo "")
    printf 'openbsd||%s|OpenBSD %s\n' "$version" "$version"
}

_platform_detect_init() {
    case "$ANTEATER_OS_KIND" in
        openbsd)
            echo "bsd-rc"
            return
            ;;
    esac

    if [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif [[ -d /run/openrc ]] || [[ -x /sbin/openrc ]] || [[ -x /usr/sbin/openrc ]]; then
        echo "openrc"
    elif [[ -d /run/runit ]] || [[ -x /usr/bin/runit ]] || [[ -x /sbin/runit ]]; then
        echo "runit"
    elif [[ -d /run/s6 ]] || [[ -d /run/s6-rc ]]; then
        echo "s6"
    elif [[ -x /sbin/dinit ]] || [[ -x /usr/sbin/dinit ]]; then
        echo "dinit"
    else
        echo "unknown"
    fi
}

_platform_detect_pkg_mgrs() {
    local found=()
    local mgr
    # Order matters only for display; callers should use platform_has_pkg_mgr.
    for mgr in pacman apt dnf zypper apk xbps-install emerge pkg_add nix-env nix flatpak snap yay paru; do
        if _platform_have_cmd "$mgr"; then
            # Normalize xbps-install → xbps for predictable matching
            case "$mgr" in
                xbps-install) found+=("xbps") ;;
                *) found+=("$mgr") ;;
            esac
        fi
    done
    printf '%s\n' "${found[*]:-}"
}

_platform_detect_desktop() {
    local d="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
    if [[ -z "$d" ]]; then
        echo "unknown"
        return
    fi
    # XDG_CURRENT_DESKTOP can be colon-separated, e.g. "ubuntu:GNOME"
    d="${d%%:*}"
    _platform_lc "$d"
}

_platform_detect_shell_kind() {
    local sh="${SHELL:-}"
    sh="${sh##*/}"
    case "$sh" in
        bash | zsh | fish | dash | ksh | tcsh | csh | sh) echo "$sh" ;;
        *) echo "unknown" ;;
    esac
}

# ============================================================================
# Populate readonly globals
# ============================================================================

ANTEATER_OS_KIND=$(_platform_detect_os_kind)

case "$ANTEATER_OS_KIND" in
    linux)
        _info=$(_platform_detect_distro_linux)
        ;;
    openbsd)
        _info=$(_platform_detect_distro_openbsd)
        ;;
    *)
        _info="unknown||$(uname -r 2> /dev/null || echo unknown)|unknown"
        ;;
esac

ANTEATER_DISTRO_ID="${_info%%|*}"
_rest="${_info#*|}"
ANTEATER_DISTRO_LIKE="${_rest%%|*}"
_rest="${_rest#*|}"
ANTEATER_DISTRO_VERSION="${_rest%%|*}"
ANTEATER_OS_NAME="${_rest#*|}"
unset _info _rest

ANTEATER_INIT=$(_platform_detect_init)
ANTEATER_DESKTOP=$(_platform_detect_desktop)
ANTEATER_SHELL_KIND=$(_platform_detect_shell_kind)
ANTEATER_PKG_MGRS=$(_platform_detect_pkg_mgrs)
ANTEATER_ARCH=$(uname -m 2> /dev/null || echo unknown)
ANTEATER_KERNEL=$(uname -r 2> /dev/null || echo unknown)

readonly ANTEATER_OS_KIND ANTEATER_OS_NAME ANTEATER_DISTRO_ID \
    ANTEATER_DISTRO_LIKE ANTEATER_DISTRO_VERSION ANTEATER_INIT \
    ANTEATER_DESKTOP ANTEATER_SHELL_KIND ANTEATER_PKG_MGRS \
    ANTEATER_ARCH ANTEATER_KERNEL

# ============================================================================
# Public helpers
# ============================================================================

platform_is_linux() {
    [[ "$ANTEATER_OS_KIND" == "linux" ]]
}

platform_is_openbsd() {
    [[ "$ANTEATER_OS_KIND" == "openbsd" ]]
}

platform_distro_is() {
    local target="$1" tok
    [[ "$ANTEATER_DISTRO_ID" == "$target" ]] && return 0
    for tok in $ANTEATER_DISTRO_LIKE; do
        [[ "$tok" == "$target" ]] && return 0
    done
    return 1
}

platform_init_is() {
    [[ "$ANTEATER_INIT" == "$1" ]]
}

platform_has_pkg_mgr() {
    local target="$1" tok
    for tok in $ANTEATER_PKG_MGRS; do
        [[ "$tok" == "$target" ]] && return 0
    done
    return 1
}

platform_summary() {
    printf '%s %s · %s · init=%s · desktop=%s · arch=%s · kernel=%s · pkg=[%s]\n' \
        "$ANTEATER_OS_KIND" "$ANTEATER_DISTRO_ID" "$ANTEATER_OS_NAME" \
        "$ANTEATER_INIT" "$ANTEATER_DESKTOP" "$ANTEATER_ARCH" \
        "$ANTEATER_KERNEL" "$ANTEATER_PKG_MGRS"
}
