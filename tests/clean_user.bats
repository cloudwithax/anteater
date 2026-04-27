#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-home.XXXXXX")"
    export HOME
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_DATA_HOME="$HOME/.local/share"

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    unset XDG_CACHE_HOME XDG_DATA_HOME
}

setup() {
    rm -rf "$HOME/.cache" "$HOME/.local" "$HOME/.npm" "$HOME/.cargo" "$HOME/.yarn"
    mkdir -p "$HOME"
}

_seed_cache() {
    local rel="$1"
    local content="${2:-junk}"
    local target="$HOME/$rel"
    mkdir -p "$(dirname "$target")"
    if [[ "$rel" == */ ]] || [[ ! "$rel" == *.* ]]; then
        mkdir -p "$target"
        printf '%s' "$content" > "$target/payload"
    else
        printf '%s' "$content" > "$target"
    fi
}

_load() {
    HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/log.sh'
        source '$PROJECT_ROOT/lib/clean/user.sh'
        $1
    "
}

@test "category IDs include thumbnails browser dev trash" {
    run _load 'printf "%s\n" "${ANTEATER_CLEAN_CATEGORY_IDS[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"thumbnails"* ]]
    [[ "$output" == *"browser"* ]]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"trash"* ]]
}

@test "misc_cache is in optional category list (opt-in)" {
    run _load 'printf "%s\n" "${ANTEATER_CLEAN_OPTIONAL_CATEGORY_IDS[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"misc_cache"* ]]
}

@test "category_paths returns nothing when no caches exist" {
    run _load 'anteater_clean_category_paths thumbnails'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "category_paths discovers thumbnails dir" {
    _seed_cache ".cache/thumbnails/normal/abc.png" "img"
    run _load 'anteater_clean_category_paths thumbnails'
    [ "$status" -eq 0 ]
    [[ "$output" == *".cache/thumbnails"* ]]
}

@test "category_paths discovers chrome and firefox caches" {
    _seed_cache ".cache/google-chrome/Default/Cache/data" "x"
    _seed_cache ".cache/mozilla/firefox/abc.default/cache2/entries/x" "x"
    run _load 'anteater_clean_category_paths browser'
    [ "$status" -eq 0 ]
    [[ "$output" == *".cache/google-chrome/Default/Cache"* ]]
    [[ "$output" == *".cache/mozilla/firefox/abc.default/cache2"* ]]
}

@test "category_paths discovers dev caches" {
    _seed_cache ".cache/pip/wheels/x" "x"
    _seed_cache ".cargo/registry/cache/foo" "x"
    _seed_cache ".npm/_cacache/contents/x" "x"
    run _load 'anteater_clean_category_paths dev'
    [ "$status" -eq 0 ]
    [[ "$output" == *".cache/pip"* ]]
    [[ "$output" == *".cargo/registry/cache"* ]]
    [[ "$output" == *".npm/_cacache"* ]]
}

@test "category_paths discovers trash" {
    _seed_cache ".local/share/Trash/files/old.txt" "x"
    _seed_cache ".local/share/Trash/info/old.txt.trashinfo" "x"
    run _load 'anteater_clean_category_paths trash'
    [ "$status" -eq 0 ]
    [[ "$output" == *".local/share/Trash/files"* ]]
    [[ "$output" == *".local/share/Trash/info"* ]]
}

@test "misc_cache excludes known categories" {
    _seed_cache ".cache/thumbnails/x" "x"
    _seed_cache ".cache/google-chrome/Default/Cache/x" "x"
    _seed_cache ".cache/some-app/state" "x"
    run _load 'anteater_clean_category_paths misc_cache'
    [ "$status" -eq 0 ]
    [[ "$output" == *".cache/some-app"* ]]
    [[ "$output" != *"thumbnails"* ]]
    [[ "$output" != *"google-chrome"* ]]
}

@test "category_size_kb returns 0 for empty category" {
    run _load 'anteater_clean_category_size_kb thumbnails'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "category_size_kb totals sizes for populated category" {
    mkdir -p "$HOME/.cache/thumbnails/normal"
    dd if=/dev/zero of="$HOME/.cache/thumbnails/normal/big" bs=1024 count=64 2>/dev/null
    run _load 'anteater_clean_category_size_kb thumbnails'
    [ "$status" -eq 0 ]
    [ "$output" -ge 64 ]
}

@test "apply removes selected category contents" {
    _seed_cache ".cache/thumbnails/normal/x.png" "x"
    [ -d "$HOME/.cache/thumbnails" ]

    run _load '
        ANTEATER_CLEAN_SELECTED_thumbnails=1
        anteater_clean_apply thumbnails
        echo "BYTES=$ANTEATER_CLEAN_BYTES"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"BYTES="* ]]
    [ ! -e "$HOME/.cache/thumbnails" ]
}

@test "apply skips unselected categories" {
    _seed_cache ".cache/thumbnails/x" "x"

    run _load '
        ANTEATER_CLEAN_SELECTED_thumbnails=0
        anteater_clean_apply thumbnails
    '
    [ "$status" -eq 0 ]
    [ -d "$HOME/.cache/thumbnails" ]
}

@test "apply in dry-run mode preserves files" {
    _seed_cache ".cache/thumbnails/x" "x"

    run env ANTEATER_DRY_RUN=1 HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        bash --noprofile --norc -c "
            source '$PROJECT_ROOT/lib/core/common.sh'
            source '$PROJECT_ROOT/lib/core/log.sh'
            source '$PROJECT_ROOT/lib/clean/user.sh'
            ANTEATER_CLEAN_SELECTED_thumbnails=1
            anteater_clean_apply thumbnails
            echo \"BYTES=\$ANTEATER_CLEAN_BYTES\"
        "
    [ "$status" -eq 0 ]
    [ -d "$HOME/.cache/thumbnails" ]
    [[ "$output" == *"Would remove"* ]]
}

@test "non-interactive select_categories chooses populated categories by default" {
    _seed_cache ".cache/thumbnails/x" "x"

    run _load '
        anteater_clean_select_categories thumbnails browser
        echo "T=$ANTEATER_CLEAN_SELECTED_thumbnails"
        echo "B=$ANTEATER_CLEAN_SELECTED_browser"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"T=1"* ]]
    [[ "$output" == *"B=0"* ]]
}

@test "bin/clean.sh --help exits 0 with usage" {
    run "$PROJECT_ROOT/bin/clean.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Anteater Clean"* ]]
    [[ "$output" == *"--include-cache"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "bin/clean.sh rejects unknown options" {
    run "$PROJECT_ROOT/bin/clean.sh" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "bin/clean.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/clean.sh"
    [ "$status" -eq 0 ]
}

@test "lib/clean/user.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/clean/user.sh"
    [ "$status" -eq 0 ]
}
