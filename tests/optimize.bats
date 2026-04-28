#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-home.XXXXXX")"
    export HOME
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CONFIG_HOME="$HOME/.config"

    mkdir -p "$HOME"

    # Stub directory we'll seed per-test with fake package managers.
    STUB_BIN="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-stubs.XXXXXX")"
    export STUB_BIN
}

teardown_file() {
    rm -rf "$HOME" "$STUB_BIN"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    unset XDG_CACHE_HOME XDG_STATE_HOME XDG_CONFIG_HOME STUB_BIN
}

setup() {
    rm -rf "$HOME/.cache" "$HOME/.local" "$HOME/.config"
    mkdir -p "$HOME"
    rm -rf "$STUB_BIN"
    mkdir -p "$STUB_BIN"
}

_make_stub() {
    local name="$1"
    local exit_code="${2:-0}"
    cat > "$STUB_BIN/$name" <<EOF
#!/bin/bash
echo "STUB:$name \$*"
exit $exit_code
EOF
    chmod +x "$STUB_BIN/$name"
}

_load() {
    HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        ANTEATER_OPTIMIZE_PATH="$STUB_BIN" \
        bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/optimize/tasks.sh'
        $1
    "
}

@test "bin/optimize.sh exists and is executable" {
    [ -f "$PROJECT_ROOT/bin/optimize.sh" ]
    [ -x "$PROJECT_ROOT/bin/optimize.sh" ]
}

@test "bin/optimize.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/optimize.sh"
    [ "$status" -eq 0 ]
}

@test "lib/optimize/tasks.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/optimize/tasks.sh"
    [ "$status" -eq 0 ]
}

@test "bin/optimize.sh --help prints usage" {
    run "$PROJECT_ROOT/bin/optimize.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Anteater Optimize"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "bin/optimize.sh rejects unknown options" {
    run "$PROJECT_ROOT/bin/optimize.sh" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "task IDs include all expected categories" {
    run _load 'printf "%s\n" "${ANTEATER_OPTIMIZE_TASK_IDS[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"pacman_cache"* ]]
    [[ "$output" == *"apt_cache"* ]]
    [[ "$output" == *"dnf_cache"* ]]
    [[ "$output" == *"journal_vacuum"* ]]
    [[ "$output" == *"fstrim"* ]]
}

@test "available_tasks returns empty when no tools detected" {
    run _load 'anteater_optimize_available_tasks'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "available_tasks reports pacman when stub present" {
    _make_stub pacman
    run _load 'anteater_optimize_available_tasks'
    [ "$status" -eq 0 ]
    [[ "$output" == *"pacman_cache"* ]]
}

@test "available_tasks orders tasks by display order" {
    _make_stub fstrim
    _make_stub pacman
    _make_stub journalctl
    run _load 'anteater_optimize_available_tasks | tr "\n" " "'
    [ "$status" -eq 0 ]
    # pacman_cache must come before journal_vacuum, journal_vacuum before fstrim.
    [[ "$output" == "pacman_cache journal_vacuum fstrim "* ]]
}

@test "task_command for pacman_cache references pacman -Sc" {
    _make_stub pacman
    run _load 'anteater_optimize_task_command pacman_cache'
    [ "$status" -eq 0 ]
    [[ "$output" == *"pacman -Sc"* ]]
}

@test "task_command for pacman_cache uses paccache when present" {
    _make_stub pacman
    _make_stub paccache
    run _load 'anteater_optimize_task_command pacman_cache'
    [ "$status" -eq 0 ]
    [[ "$output" == *"paccache -rk1"* ]]
    [[ "$output" == *"pacman -Sc"* ]]
}

@test "run_task in dry-run prints would-run preview" {
    _make_stub pacman
    run _load 'ANTEATER_DRY_RUN=1 anteater_optimize_run_task pacman_cache'
    [ "$status" -eq 0 ]
    [[ "$output" == *"would run"* ]]
    [[ "$output" == *"pacman -Sc"* ]]
}

@test "run_task with NOSUDO actually invokes the stub" {
    _make_stub pacman 0
    # Use the stubbed path as the live PATH so bash -c "pacman ..." resolves.
    run env HOME="$HOME" PATH="$STUB_BIN:$PATH" \
        ANTEATER_OPTIMIZE_PATH="$STUB_BIN" ANTEATER_OPTIMIZE_NOSUDO=1 \
        bash --noprofile --norc -c "
            source '$PROJECT_ROOT/lib/core/common.sh'
            source '$PROJECT_ROOT/lib/optimize/tasks.sh'
            anteater_optimize_run_task pacman_cache
        "
    [ "$status" -eq 0 ]
    [[ "$output" == *"STUB:pacman -Sc"* ]]
    [[ "$output" == *"ran"* ]]
}

@test "run_task surfaces failures" {
    _make_stub pacman 7
    run env HOME="$HOME" PATH="$STUB_BIN:$PATH" \
        ANTEATER_OPTIMIZE_PATH="$STUB_BIN" ANTEATER_OPTIMIZE_NOSUDO=1 \
        bash --noprofile --norc -c "
            source '$PROJECT_ROOT/lib/core/common.sh'
            source '$PROJECT_ROOT/lib/optimize/tasks.sh'
            anteater_optimize_run_task pacman_cache || echo rc=\$?
        "
    [ "$status" -eq 0 ]
    [[ "$output" == *"failed (rc=7)"* ]]
    [[ "$output" == *"rc=7"* ]]
}

@test "apply tallies ran/failed counters" {
    _make_stub pacman 0
    _make_stub journalctl 5
    run env HOME="$HOME" PATH="$STUB_BIN:$PATH" \
        ANTEATER_OPTIMIZE_PATH="$STUB_BIN" ANTEATER_OPTIMIZE_NOSUDO=1 \
        bash --noprofile --norc -c "
            source '$PROJECT_ROOT/lib/core/common.sh'
            source '$PROJECT_ROOT/lib/optimize/tasks.sh'
            ANTEATER_OPTIMIZE_SELECTED_pacman_cache=1
            ANTEATER_OPTIMIZE_SELECTED_journal_vacuum=1
            anteater_optimize_apply pacman_cache journal_vacuum
            echo \"RAN=\$ANTEATER_OPTIMIZE_RAN FAILED=\$ANTEATER_OPTIMIZE_FAILED\"
        "
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN=1 FAILED=1"* ]]
}

@test "apply skips unselected tasks" {
    _make_stub pacman 0
    run env HOME="$HOME" PATH="$STUB_BIN:$PATH" \
        ANTEATER_OPTIMIZE_PATH="$STUB_BIN" ANTEATER_OPTIMIZE_NOSUDO=1 \
        bash --noprofile --norc -c "
            source '$PROJECT_ROOT/lib/core/common.sh'
            source '$PROJECT_ROOT/lib/optimize/tasks.sh'
            ANTEATER_OPTIMIZE_SELECTED_pacman_cache=0
            anteater_optimize_apply pacman_cache
            echo \"RAN=\$ANTEATER_OPTIMIZE_RAN\"
        "
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN=0"* ]]
    [[ "$output" != *"STUB:pacman"* ]]
}

@test "anteater dispatches optimize subcommand to wrapper" {
    run env HOME="$HOME" "$PROJECT_ROOT/anteater" optimize --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Anteater Optimize"* ]]
}

@test "anteater --help advertises optimize command" {
    run env HOME="$HOME" "$PROJECT_ROOT/anteater" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"aa optimize"* ]]
}
