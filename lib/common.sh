#!/usr/bin/env bash
# ==============================================================================
# agls - Common utilities, color definitions, time formatting, and JSON helpers
# ==============================================================================

# ANSI Color Codes (using ANSI-C quoting $'\e[...' for true escape bytes)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RESET=$'\e[0m'
    COLOR_BOLD=$'\e[1m'
    COLOR_DIM=$'\e[2m'
    COLOR_ITALIC=$'\e[3m'
    COLOR_UNDERLINE=$'\e[4m'
    
    COLOR_RED=$'\e[38;5;196m'
    COLOR_GREEN=$'\e[38;5;46m'
    COLOR_YELLOW=$'\e[38;5;226m'
    COLOR_BLUE=$'\e[38;5;39m'
    COLOR_MAGENTA=$'\e[38;5;201m'
    COLOR_CYAN=$'\e[38;5;51m'
    COLOR_ORANGE=$'\e[38;5;208m'
    COLOR_PURPLE=$'\e[38;5;141m'
    COLOR_GRAY=$'\e[38;5;244m'
    COLOR_BG_DARK=$'\e[48;5;236m'
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_ITALIC=""
    COLOR_UNDERLINE=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_ORANGE=""
    COLOR_PURPLE=""
    COLOR_GRAY=""
    COLOR_BG_DARK=""
fi

# Normalize a workspace directory path (resolve ., ~, symlinks, trailing slashes)
normalize_path() {
    local target="${1:-.}"
    # Expand tilde
    target="${target/#\~/$HOME}"
    
    # Check if target exists
    if [[ -d "$target" ]]; then
        (cd "$target" 2>/dev/null && pwd -P)
    else
        # Remove trailing slash if not root
        target="${target%/}"
        # If relative path, prefix with pwd
        if [[ "$target" != /* ]]; then
            target="$(pwd -P)/$target"
        fi
        echo "$target"
    fi
}

# Convert ISO 8601 or epoch timestamp to relative time (e.g., "5m ago", "2h ago", "3d ago")
format_relative_time() {
    local raw_ts="$1"
    local epoch_ts=0
    local now_ts
    now_ts=$(date +%s)

    if [[ -z "$raw_ts" || "$raw_ts" == "null" ]]; then
        echo "-"
        return
    fi

    # If raw_ts is purely digits, treat as epoch (seconds or milliseconds)
    if [[ "$raw_ts" =~ ^[0-9]+$ ]]; then
        if (( ${#raw_ts} > 11 )); then
            epoch_ts=$(( raw_ts / 1000 ))
        else
            epoch_ts=$raw_ts
        fi
    else
        # Parse ISO 8601 format (e.g. 2026-08-28T18:47:54+07:00 or 2026-08-28T11:47:54Z)
        if date -j -f "%Y-%m-%dT%H:%M:%S" "${raw_ts:0:19}" "+%s" &>/dev/null; then
            epoch_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${raw_ts:0:19}" "+%s")
        elif date -d "$raw_ts" "+%s" &>/dev/null; then
            epoch_ts=$(date -d "$raw_ts" "+%s")
        elif command -v python3 &>/dev/null; then
            epoch_ts=$(python3 -c "
import datetime, sys
try:
    s = sys.argv[1].replace('Z', '+00:00')
    if '.' in s and ('+' in s or '-' in s[10:]):
        parts = s.split('.')
        tz_part = '+' + parts[1].split('+')[1] if '+' in parts[1] else '-' + parts[1].split('-')[1] if '-' in parts[1] else ''
        s = parts[0] + tz_part
    dt = datetime.datetime.fromisoformat(s)
    print(int(dt.timestamp()))
except Exception:
    print(0)
" "$raw_ts" 2>/dev/null)
        fi
    fi

    if [[ "$epoch_ts" -le 0 ]]; then
        echo "${raw_ts:0:10}"
        return
    fi

    local diff=$(( now_ts - epoch_ts ))
    if (( diff < 0 )); then diff=0; fi

    if (( diff < 60 )); then
        echo "${diff}s ago"
    elif (( diff < 3600 )); then
        echo "$(( diff / 60 ))m ago"
    elif (( diff < 86400 )); then
        echo "$(( diff / 3600 ))h ago"
    elif (( diff < 604800 )); then
        echo "$(( diff / 86400 ))d ago"
    else
        if date -r "$epoch_ts" "+%Y-%m-%d" &>/dev/null; then
            date -r "$epoch_ts" "+%Y-%m-%d"
        elif date -d "@$epoch_ts" "+%Y-%m-%d" &>/dev/null; then
            date -d "@$epoch_ts" "+%Y-%m-%d"
        else
            echo "${raw_ts:0:10}"
        fi
    fi
}

# Clean and truncate text to a maximum width
truncate_text() {
    local text="$1"
    local max_len="${2:-60}"
    text="$(echo "$text" | tr '\n\r\t' ' ' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
    
    if (( ${#text} > max_len )); then
        echo "${text:0:$(( max_len - 3 ))}..."
    else
        echo "$text"
    fi
}

# Colorize agent name for terminal display
format_agent_badge() {
    local agent="$1"
    case "$agent" in
        "claude"|"Claude Code"|"claude-code")
            echo "${COLOR_ORANGE}Claude Code${COLOR_RESET}"
            ;;
        "antigravity"|"Antigravity"|"agy")
            echo "${COLOR_CYAN}Antigravity${COLOR_RESET}"
            ;;
        "opencode"|"OpenCode")
            echo "${COLOR_GREEN}OpenCode${COLOR_RESET}"
            ;;
        "codex"|"Codex")
            echo "${COLOR_BLUE}Codex${COLOR_RESET}"
            ;;
        "pi"|"Pi"|"pi-agent"|"Pi Agent")
            echo "${COLOR_PURPLE}Pi${COLOR_RESET}"
            ;;
        *)
            echo "${COLOR_YELLOW}${agent}${COLOR_RESET}"
            ;;
    esac
}

# Check for JSON parser helper (prefer jq, fallback to python3)
has_jq() {
    command -v jq &>/dev/null
}
