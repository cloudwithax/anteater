#!/usr/bin/env bats

# Tests for anteater_delete in lib/core/file_ops.sh.
# Exercises permanent mode (default), trash mode (via ANTEATER_TEST_TRASH_DIR
# so Finder is never invoked), dry-run, and the deletions log.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-anteater-delete.XXXXXX")"
    export SANDBOX
    export ANTEATER_DELETE_LOG="$SANDBOX/deletions.log"
    export ANTEATER_TEST_TRASH_DIR="$SANDBOX/Trash"
    export ANTEATER_TEST_NO_AUTH=1
    unset ANTEATER_DELETE_MODE
    unset ANTEATER_DRY_RUN
}

teardown() {
    rm -rf "$SANDBOX"
}

prelude() {
    cat <<EOF
set -euo pipefail
export ANTEATER_DELETE_LOG="$ANTEATER_DELETE_LOG"
export ANTEATER_TEST_TRASH_DIR="$ANTEATER_TEST_TRASH_DIR"
export ANTEATER_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
EOF
}

@test "anteater_delete defaults to permanent mode and removes the target" {
    local victim="$SANDBOX/victim"
    mkdir -p "$victim"
    : > "$victim/keep.txt"

    run bash --noprofile --norc <<EOF
$(prelude)
anteater_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]]
    # Trash dir must remain empty in permanent mode.
    [[ -z "$(ls -A "$ANTEATER_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "anteater_delete trash mode moves the target instead of rm -rf" {
    local victim="$SANDBOX/victim_trash"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    run bash --noprofile --norc <<EOF
$(prelude)
export ANTEATER_DELETE_MODE=trash
anteater_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]]
    # Something landed in the stub trash dir.
    [[ -n "$(ls -A "$ANTEATER_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "anteater_delete writes a tab-separated log line per call" {
    local victim="$SANDBOX/logged"
    : > "$victim"

    run bash --noprofile --norc <<EOF
$(prelude)
anteater_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -s "$ANTEATER_DELETE_LOG" ]]

    # Expect 5 tab-separated fields: timestamp, mode, size_kb, status, path.
    local fields
    fields=$(awk -F'\t' 'END { print NF }' "$ANTEATER_DELETE_LOG")
    [ "$fields" -eq 5 ]

    # Status column must be "ok" for a successful permanent delete.
    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$ANTEATER_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "anteater_delete dry-run does not touch the filesystem but still logs" {
    local victim="$SANDBOX/dry"
    : > "$victim"

    run bash --noprofile --norc <<EOF
$(prelude)
export ANTEATER_DRY_RUN=1
anteater_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -e "$victim" ]]

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$ANTEATER_DELETE_LOG")
    [ "$status_col" = "dry-run" ]
}

@test "anteater_delete records a forensic log entry for rejected paths" {
    run bash --noprofile --norc <<EOF
$(prelude)
anteater_delete "/tmp/../etc/hosts"
EOF

    [ "$status" -ne 0 ]
    # Rejection IS logged (security-relevant), with status="rejected" and size=0.
    # Audit trails need to distinguish refused-by-policy from never-attempted.
    [[ -s "$ANTEATER_DELETE_LOG" ]]
    local status_col size_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$ANTEATER_DELETE_LOG")
    size_col=$(awk -F'\t' 'END { print $3 }' "$ANTEATER_DELETE_LOG")
    [ "$status_col" = "rejected" ]
    [ "$size_col" = "0" ]
}

@test "anteater_delete is a no-op on a non-existent path" {
    run bash --noprofile --norc <<EOF
$(prelude)
anteater_delete "$SANDBOX/does-not-exist"
EOF

    [ "$status" -eq 0 ]
    [[ ! -s "$ANTEATER_DELETE_LOG" ]]
}

@test "anteater_delete trash failure falls back to permanent rm" {
    local victim="$SANDBOX/fallback_target"
    : > "$victim"

    # Pointing ANTEATER_TEST_TRASH_DIR at a non-writable parent forces the stub
    # trash move to fail, exercising the fallback path.
    local blocked="$SANDBOX/blocked/Trash"
    mkdir -p "$(dirname "$blocked")"
    chmod 0555 "$(dirname "$blocked")"

    run bash --noprofile --norc <<EOF
$(prelude)
export ANTEATER_DELETE_MODE=trash
export ANTEATER_TEST_TRASH_DIR="$blocked"
anteater_delete "$victim"
EOF

    chmod 0755 "$(dirname "$blocked")"

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]]

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$ANTEATER_DELETE_LOG")
    [ "$status_col" = "trash-fallback-rm" ]
    # User explicitly asked NOT to permanent-delete; fallback must surface.
    [[ "$output" == *"Trash unavailable"* ]]
}

@test "anteater_delete records 'unknown' (not 0) when size measurement fails" {
    # Override get_path_size_kb to simulate a measurement failure (non-numeric
    # output, non-zero exit). The actual delete still goes through safe_remove
    # so the file is removed; only the log size column should differ.
    local victim="$SANDBOX/measureless"
    : > "$victim"

    run bash --noprofile --norc <<EOF
$(prelude)
get_path_size_kb() { echo "ERR"; return 1; }
anteater_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]]
    local size_col
    size_col=$(awk -F'\t' 'END { print $3 }' "$ANTEATER_DELETE_LOG")
    [ "$size_col" = "unknown" ]
}

@test "anteater_delete warns once per session when audit log is unwritable" {
    local victim="$SANDBOX/log_blocked"
    : > "$victim"
    local broken_log_dir="$SANDBOX/no_write/logs"
    mkdir -p "$(dirname "$broken_log_dir")"
    chmod 0555 "$(dirname "$broken_log_dir")"

    run bash --noprofile --norc <<EOF
set -euo pipefail
export ANTEATER_DELETE_LOG="$broken_log_dir/deletions.log"
export ANTEATER_TEST_TRASH_DIR="$ANTEATER_TEST_TRASH_DIR"
export ANTEATER_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
anteater_delete "$victim"
# Second call in the same shell must NOT print again.
: > "$SANDBOX/second_victim"
anteater_delete "$SANDBOX/second_victim"
EOF

    chmod 0755 "$(dirname "$broken_log_dir")"

    [ "$status" -eq 0 ]
    # Warning visible exactly once.
    local warn_count
    warn_count=$(printf '%s\n' "$output" | grep -c "deletions audit log unavailable" || true)
    [ "$warn_count" = "1" ]
}
