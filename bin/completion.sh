#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/core/common.sh"
source "$ROOT_DIR/lib/core/commands.sh"

command_names=()
for entry in "${ANTEATER_COMMANDS[@]}"; do
    command_names+=("${entry%%:*}")
done
command_words="${command_names[*]}"

emit_zsh_subcommands() {
    for entry in "${ANTEATER_COMMANDS[@]}"; do
        printf "        '%s:%s'\n" "${entry%%:*}" "${entry#*:}"
    done
}

emit_fish_completions() {
    local cmd="$1"
    for entry in "${ANTEATER_COMMANDS[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        printf 'complete -f -c %s -n "__fish_anteater_no_subcommand" -a %s -d "%s"\n' "$cmd" "$name" "$desc"
    done

    printf '\n'
    printf 'complete -f -c %s -n "not __fish_anteater_no_subcommand" -a bash -d "generate bash completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
    printf 'complete -f -c %s -n "not __fish_anteater_no_subcommand" -a zsh -d "generate zsh completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
    printf 'complete -f -c %s -n "not __fish_anteater_no_subcommand" -a fish -d "generate fish completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
}

remove_stale_completion_entries() {
    local config_file="$1"
    local success_message="$2"

    if [[ ! -f "$config_file" ]] || ! grep -Eq "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" 2> /dev/null; then
        return 1
    fi

    local original_mode=""
    local temp_file
    original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
    temp_file="$(mktemp)"
    grep -Ev "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
    mv "$temp_file" "$config_file"
    [[ -n "$original_mode" ]] && chmod "$original_mode" "$config_file" 2> /dev/null || true
    [[ -n "$success_message" ]] && echo -e "${GREEN}${ICON_SUCCESS}${NC} $success_message"
    return 0
}

if [[ $# -gt 0 ]]; then
    normalized_args=()
    for arg in "$@"; do
        case "$arg" in
            "--dry-run" | "-n")
                export ANTEATER_DRY_RUN=1
                ;;
            *)
                normalized_args+=("$arg")
                ;;
        esac
    done
    if [[ ${#normalized_args[@]} -gt 0 ]]; then
        set -- "${normalized_args[@]}"
    else
        set --
    fi
fi

# Auto-install mode when run without arguments
if [[ $# -eq 0 ]]; then
    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, shell config files will not be modified"
        echo ""
    fi

    # Detect current shell
    current_shell="${SHELL##*/}"
    if [[ -z "$current_shell" ]]; then
        current_shell="$(ps -p "$PPID" -o comm= 2> /dev/null | awk '{print $1}')"
    fi

    completion_name=""
    if command -v anteater > /dev/null 2>&1; then
        completion_name="anteater"
    elif command -v aa > /dev/null 2>&1; then
        completion_name="aa"
    fi

    # Fish uses a separate install path: write to ~/.config/fish/completions/ so
    # both `anteater` and `aa` load completions independently on terminal startup.
    if [[ "$current_shell" == "fish" ]]; then
        fish_dir="${HOME}/.config/fish/completions"
        anteater_file="${fish_dir}/anteater.fish"
        mo_file="${fish_dir}/aa.fish"
        config_fish="${HOME}/.config/fish/config.fish"

        if [[ -z "$completion_name" ]]; then
            # Clean up any stale config.fish entries even when anteater is not in PATH
            if [[ "${ANTEATER_DRY_RUN:-0}" != "1" ]]; then
                remove_stale_completion_entries "$config_fish" "Removed stale completion entries from config.fish" || true
            fi
            log_error "anteater not found in PATH, install Anteater before enabling completion"
            exit 1
        fi

        if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
            echo -e "${GRAY}${ICON_REVIEW} [DRY RUN] Would write Fish completions to:${NC}"
            echo "  $anteater_file"
            echo "  $mo_file"
            echo ""
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Dry run complete, no changes made"
            exit 0
        fi

        # Remove stale config.fish source-based entries (previous install method)
        if remove_stale_completion_entries "$config_fish" "Removed stale source-based entries from config.fish"; then
            echo ""
        fi

        # Prompt only on first install; silently update if files exist
        if [[ ! -f "$anteater_file" ]]; then
            echo ""
            echo -e "${GRAY}Will write Fish completions to:${NC}"
            echo "  $anteater_file"
            echo "  $mo_file"
            echo ""
            echo -ne "${PURPLE}${ICON_ARROW}${NC} Enable completion for ${GREEN}fish${NC}? ${GRAY}Enter confirm / Q cancel${NC}: "
            IFS= read -r -s -n1 key || key=""
            drain_pending_input
            echo ""

            case "$key" in
                $'\e' | [Qq] | [Nn])
                    echo -e "${YELLOW}Cancelled${NC}"
                    exit 0
                    ;;
                "" | $'\n' | $'\r' | [Yy]) ;;
                *)
                    log_error "Invalid key"
                    exit 1
                    ;;
            esac
        fi

        mkdir -p "$fish_dir"
        "$completion_name" completion fish > "$anteater_file"
        # aa.fish sources anteater.fish so Fish loads aa completions on `aa<Tab>`
        printf '# Anteater completions for aa (alias) -- auto-generated, do not edit\n' > "$mo_file"
        printf 'source %s\n' "$anteater_file" >> "$mo_file"

        if [[ -f "$anteater_file" ]]; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Fish completions written to $fish_dir"
        fi
        echo ""
        exit 0
    fi

    case "$current_shell" in
        bash)
            config_file="${HOME}/.bashrc"
            [[ -f "${HOME}/.bash_profile" ]] && config_file="${HOME}/.bash_profile"
            # shellcheck disable=SC2016
            completion_line='if output="$('"$completion_name"' completion bash 2>/dev/null)"; then eval "$output"; fi'
            ;;
        zsh)
            config_file="${HOME}/.zshrc"
            # shellcheck disable=SC2016
            completion_line='if output="$('"$completion_name"' completion zsh 2>/dev/null)"; then eval "$output"; fi'
            ;;
        *)
            log_error "Unsupported shell: $current_shell"
            echo "  anteater completion <bash|zsh|fish>"
            exit 1
            ;;
    esac

    if [[ -z "$completion_name" ]]; then
        if [[ -f "$config_file" ]] && grep -Eq "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" 2> /dev/null; then
            if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
                echo -e "${GRAY}${ICON_REVIEW} [DRY RUN] Would remove stale completion entries from $config_file${NC}"
                echo ""
            else
                original_mode=""
                original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
                temp_file="$(mktemp)"
                grep -Ev "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
                mv "$temp_file" "$config_file"
                if [[ -n "$original_mode" ]]; then
                    chmod "$original_mode" "$config_file" 2> /dev/null || true
                fi
                echo -e "${GREEN}${ICON_SUCCESS}${NC} Removed stale completion entries from $config_file"
                echo ""
            fi
        fi
        log_error "anteater not found in PATH, install Anteater before enabling completion"
        exit 1
    fi

    # Check if already installed and normalize to latest line
    if [[ -f "$config_file" ]] && grep -Eq "(anteater|aa)[[:space:]]+completion" "$config_file" 2> /dev/null; then
        if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
            echo -e "${GRAY}${ICON_REVIEW} [DRY RUN] Would normalize completion entry in $config_file${NC}"
            echo ""
            exit 0
        fi

        original_mode=""
        original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
        temp_file="$(mktemp)"
        grep -Ev "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
        mv "$temp_file" "$config_file"
        if [[ -n "$original_mode" ]]; then
            chmod "$original_mode" "$config_file" 2> /dev/null || true
        fi
        {
            echo ""
            echo "# Anteater shell completion"
            echo "$completion_line"
        } >> "$config_file"
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Shell completion updated in $config_file"
        echo ""
        exit 0
    fi

    # Prompt user for installation
    echo ""
    echo -e "${GRAY}Will add to ${config_file}:${NC}"
    echo "  $completion_line"
    echo ""
    if [[ "${ANTEATER_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Dry run complete, no changes made"
        exit 0
    fi

    echo -ne "${PURPLE}${ICON_ARROW}${NC} Enable completion for ${GREEN}${current_shell}${NC}? ${GRAY}Enter confirm / Q cancel${NC}: "
    IFS= read -r -s -n1 key || key=""
    drain_pending_input
    echo ""

    case "$key" in
        $'\e' | [Qq] | [Nn])
            echo -e "${YELLOW}Cancelled${NC}"
            exit 0
            ;;
        "" | $'\n' | $'\r' | [Yy]) ;;
        *)
            log_error "Invalid key"
            exit 1
            ;;
    esac

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        touch "$config_file"
    fi

    # Remove previous Anteater completion lines to avoid duplicates
    if [[ -f "$config_file" ]]; then
        original_mode=""
        original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
        temp_file="$(mktemp)"
        grep -Ev "(^# Anteater shell completion$|(anteater|aa)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
        mv "$temp_file" "$config_file"
        if [[ -n "$original_mode" ]]; then
            chmod "$original_mode" "$config_file" 2> /dev/null || true
        fi
    fi

    # Add completion line
    {
        echo ""
        echo "# Anteater shell completion"
        echo "$completion_line"
    } >> "$config_file"

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Completion added to $config_file"
    echo ""
    echo ""
    echo -e "${GRAY}To activate now:${NC}"
    echo -e "  ${GREEN}source $config_file${NC}"
    exit 0
fi

case "$1" in
    bash)
        cat << EOF
_anteater_completions()
{
    local cur_word prev_word
    cur_word="\${COMP_WORDS[\$COMP_CWORD]}"
    prev_word="\${COMP_WORDS[\$COMP_CWORD-1]}"

    if [ "\$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( \$(compgen -W "$command_words" -- "\$cur_word") )
    else
        case "\$prev_word" in
            completion)
                COMPREPLY=( \$(compgen -W "bash zsh fish" -- "\$cur_word") )
                ;;
            *)
                COMPREPLY=()
                ;;
        esac
    fi
}

complete -F _anteater_completions anteater aa
EOF
        ;;
    zsh)
        printf '#compdef anteater aa\n\n'
        printf '_anteater() {\n'
        printf '    local -a subcommands\n'
        printf '    subcommands=(\n'
        emit_zsh_subcommands
        printf '    )\n'
        printf "    _describe 'subcommand' subcommands\n"
        printf '}\n\n'
        printf 'compdef _anteater anteater aa\n'
        ;;
    fish)
        printf '# Completions for anteater\n'
        emit_fish_completions anteater
        printf '\n# Completions for aa (alias)\n'
        emit_fish_completions aa
        printf '\nfunction __fish_anteater_no_subcommand\n'
        printf '    for i in (commandline -opc)\n'
        # shellcheck disable=SC2016
        printf '        if contains -- $i %s\n' "$command_words"
        printf '            return 1\n'
        printf '        end\n'
        printf '    end\n'
        printf '    return 0\n'
        printf 'end\n\n'
        printf 'function __fish_see_subcommand_path\n'
        printf '    string match -q -- "completion" (commandline -opc)[1]\n'
        printf 'end\n'
        ;;
    *)
        cat << 'EOF'
Usage: anteater completion [bash|zsh|fish]

Setup shell tab completion for anteater and aa commands.

Auto-install:
  anteater completion              # Auto-detect shell and install
  anteater completion --dry-run    # Preview config changes without writing files

Manual install:
  anteater completion bash         # Generate bash completion script
  anteater completion zsh          # Generate zsh completion script
  anteater completion fish         # Generate fish completion script

Examples:
  # Auto-install (recommended)
  anteater completion

  # Manual install - Bash
  eval "$(anteater completion bash)"

  # Manual install - Zsh
  eval "$(anteater completion zsh)"

  # Manual install - Fish
  anteater completion fish | source
EOF
        exit 1
        ;;
esac
