#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-cli-home.XXXXXX")"
	export HOME

	mkdir -p "$HOME"
}

teardown_file() {
	rm -rf "$HOME/.config/anteater"
	rm -rf "$HOME"
	if [[ -n "${ORIGINAL_HOME:-}" ]]; then
		export HOME="$ORIGINAL_HOME"
	fi
}

setup() {
	rm -rf "$HOME/.config/anteater"
	mkdir -p "$HOME/.config/anteater"
}

@test "anteater --help prints command overview" {
	run env HOME="$HOME" "$PROJECT_ROOT/anteater" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"aa purge"* ]]
	[[ "$output" == *"aa completion"* ]]
}

@test "anteater --version reports script version" {
	expected_version="$(grep '^VERSION=' "$PROJECT_ROOT/anteater" | head -1 | sed 's/VERSION=\"\(.*\)\"/\1/')"
	run env HOME="$HOME" "$PROJECT_ROOT/anteater" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"$expected_version"* ]]
}

@test "anteater --version shows nightly channel metadata" {
	expected_version="$(grep '^VERSION=' "$PROJECT_ROOT/anteater" | head -1 | sed 's/VERSION=\"\(.*\)\"/\1/')"
	mkdir -p "$HOME/.config/anteater"
	cat > "$HOME/.config/anteater/install_channel" <<'EOF'
CHANNEL=nightly
EOF

	run env HOME="$HOME" "$PROJECT_ROOT/anteater" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"Anteater version $expected_version"* ]]
	[[ "$output" == *"Channel: Nightly"* ]]
}

@test "anteater unknown command returns error" {
	run env HOME="$HOME" "$PROJECT_ROOT/anteater" unknown-command
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown command: unknown-command"* ]]
}

@test "show_main_menu hides update shortcut when no update notice is available" {
	run bash --noprofile --norc <<EOF
set -euo pipefail
HOME="\$(mktemp -d)"
export HOME ANTEATER_TEST_MODE=1 ANTEATER_SKIP_MAIN=1
source "$PROJECT_ROOT/anteater"
show_brand_banner() { printf 'banner\n'; }
show_menu_option() { printf '%s' "\$2"; }
MAIN_MENU_BANNER=""
MAIN_MENU_UPDATE_MESSAGE=""
MAIN_MENU_SHOW_UPDATE=false
show_main_menu 1 true
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"U Update"* ]]
}

@test "interactive_main_menu ignores U shortcut when update notice is hidden" {
	run bash --noprofile --norc <<EOF
set -euo pipefail
HOME="\$(mktemp -d)"
export HOME ANTEATER_TEST_MODE=1 ANTEATER_SKIP_MAIN=1
source "$PROJECT_ROOT/anteater"
show_brand_banner() { :; }
show_main_menu() { :; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
update_anteater() { echo "UPDATE_CALLED"; }
state_file="\$HOME/read_key_state"
read_key() {
    if [[ ! -f "\$state_file" ]]; then
        : > "\$state_file"
        echo "UPDATE"
    else
        echo "QUIT"
    fi
}
interactive_main_menu
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"UPDATE_CALLED"* ]]
}

@test "interactive_main_menu accepts U shortcut when update notice is visible" {
	run bash --noprofile --norc <<EOF
set -euo pipefail
HOME="\$(mktemp -d)"
export HOME ANTEATER_TEST_MODE=1 ANTEATER_SKIP_MAIN=1
mkdir -p "\$HOME/.cache/anteater"
printf 'update available\n' > "\$HOME/.cache/anteater/update_message"
source "$PROJECT_ROOT/anteater"
show_brand_banner() { :; }
show_main_menu() { :; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
update_anteater() { echo "UPDATE_CALLED"; }
read_key() { echo "UPDATE"; }
interactive_main_menu
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"UPDATE_CALLED"* ]]
}
