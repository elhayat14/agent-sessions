#!/usr/bin/env bash
# ==============================================================================
# agls - Bash auto-completion
# ==============================================================================

_agls_completions() {
    local cur prev opts commands agents
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="update uninstall"
    agents="claude antigravity opencode codex pi all"
    opts="-p --page -n --limit -a --all --agent -s --search --json --show --resume -y --yes -v --version -h --help"

    case "$prev" in
        --agent)
            COMPREPLY=( $(compgen -W "$agents" -- "$cur") )
            return 0
            ;;
        --show|--resume|-i|-r)
            return 0
            ;;
        -n|--limit|-p|--page|-s|--search)
            return 0
            ;;
        *)
            ;;
    esac

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands $opts" -- "$cur") )
        return 0
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # Fallback to directories
    COMPREPLY=( $(compgen -d -- "$cur") )
}

complete -F _agls_completions agls
complete -F _agls_completions agent-sessions
