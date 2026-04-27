#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-scripts-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    export TERM="dumb"
    rm -rf "${HOME:?}"/*
    mkdir -p "$HOME"
}

@test "check.sh --help shows usage information" {
    run "$PROJECT_ROOT/scripts/check.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--format"* ]]
    [[ "$output" == *"--no-format"* ]]
}

@test "check.sh script exists and is valid" {
    [ -f "$PROJECT_ROOT/scripts/check.sh" ]
    [ -x "$PROJECT_ROOT/scripts/check.sh" ]

    run bash -c "grep -q 'Anteater Check' '$PROJECT_ROOT/scripts/check.sh'"
    [ "$status" -eq 0 ]
}

@test "test.sh script exists and is valid" {
    [ -f "$PROJECT_ROOT/scripts/test.sh" ]
    [ -x "$PROJECT_ROOT/scripts/test.sh" ]

    run bash -c "grep -q 'Anteater Test Runner' '$PROJECT_ROOT/scripts/test.sh'"
    [ "$status" -eq 0 ]
}

@test "test.sh includes test lint step" {
    run bash -c "grep -q 'Test script lint' '$PROJECT_ROOT/scripts/test.sh'"
    [ "$status" -eq 0 ]
}

@test "Makefile has build target for Go binaries" {
    run bash -c "grep -Eq '(^|[[:space:]])(go|\\$\\(GO\\))[[:space:]]+build' '$PROJECT_ROOT/Makefile'"
    [ "$status" -eq 0 ]
}

@test "setup-quick-launchers.sh has detect_mo function" {
    run bash -c "grep -q 'detect_mo()' '$PROJECT_ROOT/scripts/setup-quick-launchers.sh'"
    [ "$status" -eq 0 ]
}

@test "setup-quick-launchers.sh has Raycast script generation" {
    run bash -c "grep -q 'create_raycast_commands' '$PROJECT_ROOT/scripts/setup-quick-launchers.sh'"
    [ "$status" -eq 0 ]
    run bash -c "grep -q 'write_raycast_script' '$PROJECT_ROOT/scripts/setup-quick-launchers.sh'"
    [ "$status" -eq 0 ]
}

@test "setup-quick-launchers.sh generates Raycast scripts with discoverable metadata" {
    local fake_bin="$HOME/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/aa" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$fake_bin/aa"

    run env HOME="$HOME" TERM="dumb" PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$PROJECT_ROOT/scripts/setup-quick-launchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Raycast: Anteater Clean | Alfred keyword: clean"* ]]
    [[ "$output" == *"Raycast: Anteater Status | Alfred keyword: status"* ]]

    local raycast_dir="$HOME/Library/Application Support/Raycast/script-commands"
    [ -d "$raycast_dir" ]

    local clean_script="$raycast_dir/anteater-clean.sh"
    local uninstall_script="$raycast_dir/anteater-uninstall.sh"
    local optimize_script="$raycast_dir/anteater-optimize.sh"
    local analyze_script="$raycast_dir/anteater-analyze.sh"
    local status_script="$raycast_dir/anteater-status.sh"

    [ -x "$clean_script" ]
    [ -x "$uninstall_script" ]
    [ -x "$optimize_script" ]
    [ -x "$analyze_script" ]
    [ -x "$status_script" ]

    run grep -q '^# @raycast.title Anteater Clean$' "$clean_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.title Anteater Uninstall$' "$uninstall_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.title Anteater Optimize$' "$optimize_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.title Anteater Analyze$' "$analyze_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.title Anteater Status$' "$status_script"
    [ "$status" -eq 0 ]

    run grep -q '^# @raycast.description Deep system cleanup with Anteater$' "$clean_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.description Uninstall applications with Anteater$' "$uninstall_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.description System health checks and optimization$' "$optimize_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.description Disk space analysis with Anteater$' "$analyze_script"
    [ "$status" -eq 0 ]
    run grep -q '^# @raycast.description Live system status dashboard$' "$status_script"
    [ "$status" -eq 0 ]
}

@test "install.sh supports dev branch installs" {
    run bash -c "grep -q 'refs/heads/dev.tar.gz' '$PROJECT_ROOT/install.sh'"
    [ "$status" -eq 0 ]
    run bash -c "grep -q 'ANTEATER_VERSION=\"dev\"' '$PROJECT_ROOT/install.sh'"
    [ "$status" -eq 0 ]
}

@test "update_homebrew_tap_formula.sh updates all release artifacts" {
    local formula_file="$HOME/anteater.rb"
    cat > "$formula_file" <<'EOF'
class Anteater < Formula
  desc "Anteater"
  homepage "https://github.com/cloudwithax/anteater"
  url "https://github.com/cloudwithax/anteater/archive/refs/tags/V1.32.0.tar.gz"
  sha256 "old-source-sha"

  on_arm do
    url "https://github.com/cloudwithax/anteater/releases/download/V1.32.0/binaries-darwin-arm64.tar.gz"
    sha256 "old-arm-sha"
  end

  on_intel do
    url "https://github.com/cloudwithax/anteater/releases/download/V1.32.0/binaries-darwin-amd64.tar.gz"
    sha256 "old-amd-sha"
  end
end
EOF

    run "$PROJECT_ROOT/scripts/update_homebrew_tap_formula.sh" \
        --formula "$formula_file" \
        --tag "V1.33.0" \
        --source-sha "new-source-sha" \
        --arm-sha "new-arm-sha" \
        --amd-sha "new-amd-sha"
    [ "$status" -eq 0 ]

    run grep -q 'url "https://github.com/cloudwithax/anteater/archive/refs/tags/V1.33.0.tar.gz"' "$formula_file"
    [ "$status" -eq 0 ]
    run grep -q 'sha256 "new-source-sha"' "$formula_file"
    [ "$status" -eq 0 ]
    run grep -q 'url "https://github.com/cloudwithax/anteater/releases/download/V1.33.0/binaries-darwin-arm64.tar.gz"' "$formula_file"
    [ "$status" -eq 0 ]
    run grep -q 'sha256 "new-arm-sha"' "$formula_file"
    [ "$status" -eq 0 ]
    run grep -q 'url "https://github.com/cloudwithax/anteater/releases/download/V1.33.0/binaries-darwin-amd64.tar.gz"' "$formula_file"
    [ "$status" -eq 0 ]
    run grep -q 'sha256 "new-amd-sha"' "$formula_file"
    [ "$status" -eq 0 ]
}

@test "update_homebrew_tap_formula.sh fails when expected sections are missing" {
    local formula_file="$HOME/anteater-missing-intel.rb"
    cat > "$formula_file" <<'EOF'
class Anteater < Formula
  desc "Anteater"
  homepage "https://github.com/cloudwithax/anteater"
  url "https://github.com/cloudwithax/anteater/archive/refs/tags/V1.32.0.tar.gz"
  sha256 "old-source-sha"

  on_arm do
    url "https://github.com/cloudwithax/anteater/releases/download/V1.32.0/binaries-darwin-arm64.tar.gz"
    sha256 "old-arm-sha"
  end
end
EOF

    run "$PROJECT_ROOT/scripts/update_homebrew_tap_formula.sh" \
        --formula "$formula_file" \
        --tag "V1.33.0" \
        --source-sha "new-source-sha" \
        --arm-sha "new-arm-sha" \
        --amd-sha "new-amd-sha"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to update formula"* ]]
}
