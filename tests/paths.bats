#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    TEST_HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-paths.XXXXXX")"
    export TEST_HOME
}

teardown_file() {
    rm -rf "$TEST_HOME"
}

# Run paths.sh in a clean environment with HOME forced to $TEST_HOME and
# any extra env vars threaded through.
_run_paths() {
    local cmd="$1"
    shift
    env -i HOME="$TEST_HOME" PATH="$PATH" "$@" \
        bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/paths.sh'; $cmd"
}

@test "default config dir under HOME/.config/anteater" {
    result=$(_run_paths 'echo "$ANTEATER_CONFIG_DIR"')
    [ "$result" = "$TEST_HOME/.config/anteater" ]
}

@test "default cache dir under HOME/.cache/anteater" {
    result=$(_run_paths 'echo "$ANTEATER_CACHE_DIR"')
    [ "$result" = "$TEST_HOME/.cache/anteater" ]
}

@test "default data dir under HOME/.local/share/anteater" {
    result=$(_run_paths 'echo "$ANTEATER_DATA_DIR"')
    [ "$result" = "$TEST_HOME/.local/share/anteater" ]
}

@test "default state dir under HOME/.local/state/anteater" {
    result=$(_run_paths 'echo "$ANTEATER_STATE_DIR"')
    [ "$result" = "$TEST_HOME/.local/state/anteater" ]
}

@test "log dir nested under state dir" {
    result=$(_run_paths 'echo "$ANTEATER_LOG_DIR"')
    [ "$result" = "$TEST_HOME/.local/state/anteater/logs" ]
}

@test "trash dir under data home (not anteater-namespaced)" {
    result=$(_run_paths 'echo "$ANTEATER_TRASH_DIR"')
    [ "$result" = "$TEST_HOME/.local/share/Trash" ]
}

@test "XDG_CONFIG_HOME override is respected" {
    result=$(_run_paths 'echo "$ANTEATER_CONFIG_DIR"' XDG_CONFIG_HOME=/custom/cfg)
    [ "$result" = "/custom/cfg/anteater" ]
}

@test "XDG_CACHE_HOME override is respected" {
    result=$(_run_paths 'echo "$ANTEATER_CACHE_DIR"' XDG_CACHE_HOME=/custom/cache)
    [ "$result" = "/custom/cache/anteater" ]
}

@test "XDG_DATA_HOME override drives data dir and trash" {
    result=$(_run_paths 'echo "$ANTEATER_DATA_DIR|$ANTEATER_TRASH_DIR"' XDG_DATA_HOME=/custom/data)
    [ "$result" = "/custom/data/anteater|/custom/data/Trash" ]
}

@test "XDG_STATE_HOME override drives state dir and log dir" {
    result=$(_run_paths 'echo "$ANTEATER_STATE_DIR|$ANTEATER_LOG_DIR"' XDG_STATE_HOME=/custom/state)
    [ "$result" = "/custom/state/anteater|/custom/state/anteater/logs" ]
}

@test "TMPDIR override is respected" {
    result=$(_run_paths 'echo "$ANTEATER_TMP"' TMPDIR=/scratch/tmp)
    [ "$result" = "/scratch/tmp" ]
}

@test "default TMP is /tmp when TMPDIR is unset" {
    result=$(_run_paths 'echo "$ANTEATER_TMP"')
    [ "$result" = "/tmp" ]
}

@test "VAR_TMP is /var/tmp" {
    result=$(_run_paths 'echo "$ANTEATER_VAR_TMP"')
    [ "$result" = "/var/tmp" ]
}

@test "paths_resolve expands leading tilde" {
    result=$(_run_paths 'paths_resolve ~/projects/anteater')
    [ "$result" = "$TEST_HOME/projects/anteater" ]
}

@test "paths_resolve passes absolute paths through" {
    result=$(_run_paths 'paths_resolve /etc/hosts')
    [ "$result" = "/etc/hosts" ]
}

@test "paths_resolve passes relative paths through" {
    result=$(_run_paths 'paths_resolve some/relative/path')
    [ "$result" = "some/relative/path" ]
}

@test "paths_user_home returns HOME" {
    result=$(_run_paths 'paths_user_home')
    [ "$result" = "$TEST_HOME" ]
}

@test "paths_user_home errors when HOME is unset" {
    run env -i PATH="$PATH" \
        bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/paths.sh'; paths_user_home"
    [ "$status" -ne 0 ]
}

@test "paths_ensure_dir creates directory with 700" {
    target="$TEST_HOME/ensure-test"
    rm -rf "$target"
    _run_paths "paths_ensure_dir '$target'; stat -c '%a' '$target' 2>/dev/null || stat -f '%Mp%Lp' '$target'"
    [ -d "$target" ]
    perms=$(stat -c '%a' "$target" 2> /dev/null || stat -f '%Mp%Lp' "$target")
    [ "$perms" = "700" ]
    rm -rf "$target"
}
