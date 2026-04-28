#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-status-home.XXXXXX")"
    export HOME
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CONFIG_HOME="$HOME/.config"

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    unset XDG_CACHE_HOME XDG_STATE_HOME XDG_CONFIG_HOME
}

setup() {
    rm -rf "$HOME/.cache" "$HOME/.local" "$HOME/.config"
    mkdir -p "$HOME"
}

_load() {
    HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/platform.sh'
        source '$PROJECT_ROOT/lib/status/report.sh'
        $1
    "
}

@test "bin/status.sh exists and is executable" {
    [ -f "$PROJECT_ROOT/bin/status.sh" ]
    [ -x "$PROJECT_ROOT/bin/status.sh" ]
}

@test "bin/status.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/status.sh"
    [ "$status" -eq 0 ]
}

@test "lib/status/report.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/status/report.sh"
    [ "$status" -eq 0 ]
}

@test "bin/status.sh --help prints usage" {
    run "$PROJECT_ROOT/bin/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Anteater Status"* ]]
    [[ "$output" == *"--help"* ]]
}

@test "bin/status.sh rejects unknown options" {
    run "$PROJECT_ROOT/bin/status.sh" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "status_render_all prints all four sections" {
    run _load 'status_render_all'
    [ "$status" -eq 0 ]
    [[ "$output" == *"System"* ]]
    [[ "$output" == *"Memory"* ]]
    [[ "$output" == *"Disks"* ]]
    [[ "$output" == *"Anteater"* ]]
}

@test "status_uptime returns non-empty string" {
    run _load 'status_uptime'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "status_loadavg returns three numbers on Linux" {
    if [[ ! -r /proc/loadavg ]]; then
        skip "no /proc/loadavg"
    fi
    run _load 'status_loadavg'
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9.]+\ [0-9.]+\ [0-9.]+$ ]]
}

@test "status_memory_kib parses fixture meminfo" {
    local fixture="$HOME/meminfo.fixture"
    cat > "$fixture" <<'EOF'
MemTotal:       16000000 kB
MemFree:         2000000 kB
MemAvailable:    8000000 kB
SwapTotal:       4000000 kB
SwapFree:        3000000 kB
EOF
    run _load "ANTEATER_STATUS_MEMINFO='$fixture' status_memory_kib"
    [ "$status" -eq 0 ]
    # total used available swap_total swap_used
    [[ "$output" == "16000000 8000000 8000000 4000000 1000000" ]]
}

@test "status_render_memory shows percentage and bar" {
    local fixture="$HOME/meminfo.fixture"
    cat > "$fixture" <<'EOF'
MemTotal:       8000000 kB
MemAvailable:   2000000 kB
SwapTotal:      0 kB
SwapFree:       0 kB
EOF
    run _load "ANTEATER_STATUS_MEMINFO='$fixture' status_render_memory"
    [ "$status" -eq 0 ]
    [[ "$output" == *"75%"* ]]
    [[ "$output" == *"none"* ]]
}

@test "status_render_disks dedupes by source device" {
    # Mock df: same fs '/dev/sda1' on two mounts; only the shorter mount stays.
    local stub="$HOME/df-stub"
    cat > "$stub" <<'EOF'
#!/bin/bash
cat <<'OUT'
Filesystem 1024-blocks       Used Available Capacity Mounted on
/dev/sda1   100000000   50000000  50000000      50% /
/dev/sda1   100000000   50000000  50000000      50% /home/foo
/dev/sdb1     1000000     200000    800000      20% /boot
OUT
EOF
    chmod +x "$stub"
    run _load "ANTEATER_STATUS_DF='$stub' status_render_disks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/ "* || "$output" == *"/  "* ]]
    [[ "$output" != *"/home/foo"* ]]
    [[ "$output" == *"/boot"* ]]
}

@test "status_render_anteater shows version and paths" {
    run _load "VERSION='9.9.9' status_render_anteater"
    [ "$status" -eq 0 ]
    [[ "$output" == *"9.9.9"* ]]
    [[ "$output" == *"$XDG_CACHE_HOME/anteater"* ]]
    [[ "$output" == *"$XDG_CONFIG_HOME/anteater"* ]]
}

@test "anteater dispatches status subcommand to wrapper" {
    run env HOME="$HOME" "$PROJECT_ROOT/anteater" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Anteater Status"* ]]
}

@test "anteater --help advertises status command" {
    run env HOME="$HOME" "$PROJECT_ROOT/anteater" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"aa status"* ]]
}
