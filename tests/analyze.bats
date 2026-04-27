#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-analyze-home.XXXXXX")"
    export HOME
    export XDG_CACHE_HOME="$HOME/.cache"

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    unset XDG_CACHE_HOME
}

@test "bin/analyze.sh exists and is executable" {
    [ -f "$PROJECT_ROOT/bin/analyze.sh" ]
    [ -x "$PROJECT_ROOT/bin/analyze.sh" ]
}

@test "bin/analyze.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/analyze.sh"
    [ "$status" -eq 0 ]
}

@test "bin/analyze.sh fails clearly when Go is unavailable and no cached binary" {
    local fake_cache="$HOME/.cache/anteater/bin"
    rm -rf "$fake_cache"

    local stub_bin
    stub_bin="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-analyze-stubs.XXXXXX")"
    # Provide a minimal PATH containing only common shell utilities the wrapper needs.
    cp /usr/bin/find "$stub_bin/" 2> /dev/null || ln -s "$(command -v find)" "$stub_bin/find"
    cp /usr/bin/head "$stub_bin/" 2> /dev/null || ln -s "$(command -v head)" "$stub_bin/head"
    ln -s "$(command -v mkdir)" "$stub_bin/mkdir"
    ln -s "$(command -v dirname)" "$stub_bin/dirname"
    ln -s "$(command -v cd)" "$stub_bin/cd" 2> /dev/null || true
    ln -s "$(command -v rm)" "$stub_bin/rm"
    ln -s "$(command -v bash)" "$stub_bin/bash"
    # Do NOT provide `go`.

    run env -i HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$stub_bin" \
        bash --noprofile --norc "$PROJECT_ROOT/bin/analyze.sh"
    rm -rf "$stub_bin"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires Go to build"* ]]
}

@test "bin/analyze.sh execs cached binary when fresh" {
    local cache_bin="$HOME/.cache/anteater/bin"
    mkdir -p "$cache_bin"

    cat > "$cache_bin/aa-analyze" <<'STUB'
#!/bin/bash
echo "STUB CALLED args=$*"
exit 0
STUB
    chmod +x "$cache_bin/aa-analyze"

    # Touch all sources to be older than the stub binary.
    touch -d "1 hour ago" "$PROJECT_ROOT/cmd/aa-analyze"/*.go \
        "$PROJECT_ROOT/internal/analyze"/*.go \
        "$PROJECT_ROOT/go.mod" "$PROJECT_ROOT/go.sum" 2> /dev/null || true
    touch "$cache_bin/aa-analyze"

    run env HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        "$PROJECT_ROOT/bin/analyze.sh" some-arg
    [ "$status" -eq 0 ]
    [[ "$output" == *"STUB CALLED args=some-arg"* ]]
}

@test "bin/analyze.sh --rebuild removes cached binary" {
    local cache_bin="$HOME/.cache/anteater/bin"
    mkdir -p "$cache_bin"

    # Stub that fails to confirm wrapper attempted to rebuild rather than re-exec it.
    cat > "$cache_bin/aa-analyze" <<'STUB'
#!/bin/bash
echo "STALE STUB"
exit 7
STUB
    chmod +x "$cache_bin/aa-analyze"

    if ! command -v go > /dev/null 2>&1; then
        skip "go not installed"
    fi

    run env HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        "$PROJECT_ROOT/bin/analyze.sh" --rebuild --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"aa-analyze"* ]]
    [[ "$output" != *"STALE STUB"* ]]
}

@test "anteater dispatches analyze subcommand to wrapper" {
    local cache_bin="$HOME/.cache/anteater/bin"
    mkdir -p "$cache_bin"
    rm -f "$cache_bin/aa-analyze"

    cat > "$cache_bin/aa-analyze" <<'STUB'
#!/bin/bash
echo "DISPATCH OK args=$*"
exit 0
STUB
    chmod +x "$cache_bin/aa-analyze"

    touch -d "1 hour ago" "$PROJECT_ROOT/cmd/aa-analyze"/*.go \
        "$PROJECT_ROOT/internal/analyze"/*.go \
        "$PROJECT_ROOT/go.mod" "$PROJECT_ROOT/go.sum" 2> /dev/null || true
    touch "$cache_bin/aa-analyze"

    run env HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        "$PROJECT_ROOT/anteater" analyze /tmp
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISPATCH OK args=/tmp"* ]]
}

@test "anteater --help advertises analyze command" {
    run env HOME="$HOME" "$PROJECT_ROOT/anteater" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"aa analyze"* ]]
}

@test "cmd/aa-analyze go package builds" {
    if ! command -v go > /dev/null 2>&1; then
        skip "go not installed"
    fi
    run bash -c "cd '$PROJECT_ROOT' && go build ./cmd/aa-analyze"
    [ "$status" -eq 0 ]
    rm -f "$PROJECT_ROOT/aa-analyze"
}
