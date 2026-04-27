#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    FIXTURES="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-platform.XXXXXX")"
    export FIXTURES

    cat > "$FIXTURES/os-release-cachyos" <<'EOF'
NAME="CachyOS Linux"
PRETTY_NAME="CachyOS"
ID=cachyos
ID_LIKE=arch
BUILD_ID=rolling
EOF

    cat > "$FIXTURES/os-release-ubuntu" <<'EOF'
PRETTY_NAME="Ubuntu 24.04 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04 (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
EOF

    cat > "$FIXTURES/os-release-debian" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
ID=debian
EOF

    cat > "$FIXTURES/os-release-fedora" <<'EOF'
NAME="Fedora Linux"
VERSION="40 (Workstation Edition)"
ID=fedora
VERSION_ID=40
PRETTY_NAME="Fedora Linux 40 (Workstation Edition)"
EOF

    cat > "$FIXTURES/os-release-alpine" <<'EOF'
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.20.0
PRETTY_NAME="Alpine Linux v3.20"
EOF

    cat > "$FIXTURES/os-release-empty" <<'EOF'
EOF
}

teardown_file() {
    rm -rf "$FIXTURES"
}

# Source the module in a clean sub-shell with the requested fixture and
# echo a Tcl-list-style line of the fields under test. The system PATH is
# preserved so bash itself stays callable; only ANTEATER_PLATFORM_PATH is
# overridden when a fake pkg-mgr directory is requested.
_run_platform() {
    local fixture="$1"
    local uname_s="${2:-Linux}"
    local fake_path="${3:-}"
    local cmd="$4"
    env -i HOME="$HOME" PATH="$PATH" \
        ANTEATER_PLATFORM_OS_RELEASE_FILE="$fixture" \
        ANTEATER_PLATFORM_UNAME_S="$uname_s" \
        ${fake_path:+ANTEATER_PLATFORM_PATH="$fake_path"} \
        bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/platform.sh'; $cmd"
}

@test "detects linux from uname Linux" {
    result=$(_run_platform "$FIXTURES/os-release-cachyos" Linux "" 'echo "$ANTEATER_OS_KIND"')
    [ "$result" = "linux" ]
}

@test "detects openbsd from uname OpenBSD" {
    result=$(_run_platform "$FIXTURES/os-release-empty" OpenBSD "" 'echo "$ANTEATER_OS_KIND $ANTEATER_DISTRO_ID"')
    [[ "$result" == "openbsd openbsd" ]]
}

@test "cachyos distro reads ID and ID_LIKE" {
    result=$(_run_platform "$FIXTURES/os-release-cachyos" Linux "" \
        'echo "$ANTEATER_DISTRO_ID|$ANTEATER_DISTRO_LIKE|$ANTEATER_OS_NAME"')
    [ "$result" = "cachyos|arch|CachyOS" ]
}

@test "ubuntu distro picks PRETTY_NAME and version" {
    result=$(_run_platform "$FIXTURES/os-release-ubuntu" Linux "" \
        'echo "$ANTEATER_DISTRO_ID|$ANTEATER_DISTRO_LIKE|$ANTEATER_DISTRO_VERSION|$ANTEATER_OS_NAME"')
    [ "$result" = "ubuntu|debian|24.04|Ubuntu 24.04 LTS" ]
}

@test "debian distro has empty ID_LIKE" {
    result=$(_run_platform "$FIXTURES/os-release-debian" Linux "" \
        'echo "$ANTEATER_DISTRO_ID|$ANTEATER_DISTRO_LIKE"')
    [ "$result" = "debian|" ]
}

@test "fedora distro" {
    result=$(_run_platform "$FIXTURES/os-release-fedora" Linux "" \
        'echo "$ANTEATER_DISTRO_ID|$ANTEATER_DISTRO_VERSION"')
    [ "$result" = "fedora|40" ]
}

@test "empty os-release falls back to unknown" {
    result=$(_run_platform "$FIXTURES/os-release-empty" Linux "" 'echo "$ANTEATER_DISTRO_ID"')
    [ "$result" = "unknown" ]
}

@test "platform_distro_is matches ID" {
    _run_platform "$FIXTURES/os-release-ubuntu" Linux "" 'platform_distro_is ubuntu'
}

@test "platform_distro_is matches ID_LIKE" {
    _run_platform "$FIXTURES/os-release-cachyos" Linux "" 'platform_distro_is arch'
}

@test "platform_distro_is misses unrelated id" {
    run _run_platform "$FIXTURES/os-release-ubuntu" Linux "" 'platform_distro_is fedora'
    [ "$status" -ne 0 ]
}

@test "platform_is_linux true on linux fixture" {
    _run_platform "$FIXTURES/os-release-cachyos" Linux "" 'platform_is_linux'
}

@test "platform_is_openbsd true on openbsd fixture" {
    _run_platform "$FIXTURES/os-release-empty" OpenBSD "" 'platform_is_openbsd'
}

@test "platform_is_openbsd false on linux" {
    run _run_platform "$FIXTURES/os-release-cachyos" Linux "" 'platform_is_openbsd'
    [ "$status" -ne 0 ]
}

@test "package manager detection finds binaries on PATH" {
    fake="$(mktemp -d)"
    : > "$fake/pacman" && chmod +x "$fake/pacman"
    : > "$fake/flatpak" && chmod +x "$fake/flatpak"
    result=$(_run_platform "$FIXTURES/os-release-cachyos" Linux "$fake" 'echo "$ANTEATER_PKG_MGRS"')
    rm -rf "$fake"
    [[ "$result" == *"pacman"* ]]
    [[ "$result" == *"flatpak"* ]]
}

@test "platform_has_pkg_mgr matches exact name" {
    fake="$(mktemp -d)"
    : > "$fake/dnf" && chmod +x "$fake/dnf"
    _run_platform "$FIXTURES/os-release-fedora" Linux "$fake" 'platform_has_pkg_mgr dnf'
    rm -rf "$fake"
}

@test "platform_has_pkg_mgr false for absent manager" {
    fake="$(mktemp -d)"
    run _run_platform "$FIXTURES/os-release-fedora" Linux "$fake" 'platform_has_pkg_mgr pacman'
    rm -rf "$fake"
    [ "$status" -ne 0 ]
}

@test "xbps-install binary normalizes to xbps" {
    fake="$(mktemp -d)"
    : > "$fake/xbps-install" && chmod +x "$fake/xbps-install"
    result=$(_run_platform "$FIXTURES/os-release-empty" Linux "$fake" 'echo "$ANTEATER_PKG_MGRS"')
    rm -rf "$fake"
    [[ "$result" == *"xbps"* ]]
    [[ "$result" != *"xbps-install"* ]]
}

@test "openbsd init is bsd-rc" {
    result=$(_run_platform "$FIXTURES/os-release-empty" OpenBSD "" 'echo "$ANTEATER_INIT"')
    [ "$result" = "bsd-rc" ]
}

@test "platform_summary returns a single non-empty line" {
    result=$(_run_platform "$FIXTURES/os-release-cachyos" Linux "" 'platform_summary')
    [ -n "$result" ]
    [ "$(printf '%s' "$result" | wc -l)" -eq 0 ]
}
