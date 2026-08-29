#!/usr/bin/env bash
# ==============================================================================
# agls - Claude Code Session Parser
# ==============================================================================

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_PROJECTS_DIR="$CLAUDE_DIR/projects"

# Find all matching project directories for target workspace
get_claude_project_dirs() {
    local target_ws="$1"
    local match_all="$2"

    if [[ ! -d "$CLAUDE_PROJECTS_DIR" ]]; then
        return
    fi

    if [[ "$match_all" == "true" ]]; then
        find "$CLAUDE_PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
        return
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import os, sys

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
projects_dir = sys.argv[2]

def slug_to_real_path(slug):
    parts = [p for p in slug.split('-') if p]
    if not parts:
        return ''
    current = '/' + parts[0]
    i = 1
    while i < len(parts):
        found = False
        for j in range(len(parts), i, -1):
            candidate_name = '-'.join(parts[i:j])
            candidate_path = os.path.join(current, candidate_name)
            if os.path.isdir(candidate_path):
                current = candidate_path
                i = j
                found = True
                break
        if not found:
            current = os.path.join(current, parts[i])
            i += 1
    return current

if os.path.isdir(projects_dir):
    for entry in os.scandir(projects_dir):
        if entry.is_dir():
            real_path = slug_to_real_path(entry.name)
            r_norm = os.path.normpath(real_path).rstrip('/')
            # Option B: Match exact project or subdirectories inside target workspace
            if r_norm == target_ws or r_norm.startswith(target_ws + '/'):
                print(entry.path)
" "$target_ws" "$CLAUDE_PROJECTS_DIR"
    fi
}

# Parse all Claude sessions for target workspace
list_claude_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    local proj_dirs
    proj_dirs="$(get_claude_project_dirs "$target_ws" "$match_all")"

    if [[ -z "$proj_dirs" ]]; then
        return
    fi

    while IFS= read -r pdir; do
        [[ -z "$pdir" || ! -d "$pdir" ]] && continue
        
        local slug
        slug="$(basename "$pdir")"

        for sfile in "$pdir"/*.jsonl "$pdir"/*.json; do
            [[ ! -f "$sfile" ]] && continue
            
            local filename="$(basename "$sfile")"
            local session_id="${filename%.*}"
            [[ "$session_id" == "sessions" || "$session_id" == "config" ]] && continue

            if command -v python3 &>/dev/null; then
                python3 -c "
import json, os, sys, re

sfile = sys.argv[1]
session_id = sys.argv[2]
slug = sys.argv[3]
target_ws = os.path.normpath(sys.argv[4]).rstrip('/')
match_all = (sys.argv[5].lower() == 'true')

def slug_to_real_path(s):
    parts = [p for p in s.split('-') if p]
    if not parts:
        return ''
    current = '/' + parts[0]
    i = 1
    while i < len(parts):
        found = False
        for j in range(len(parts), i, -1):
            candidate_name = '-'.join(parts[i:j])
            candidate_path = os.path.join(current, candidate_name)
            if os.path.isdir(candidate_path):
                current = candidate_path
                i = j
                found = True
                break
        if not found:
            current = os.path.join(current, parts[i])
            i += 1
    return current

workspace = slug_to_real_path(slug)

turns = 0
first_prompt = ''
timestamp = ''
updated_at = ''

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<local-command-caveat>.*?</local-command-caveat>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        parts = []
        for item in val:
            if isinstance(item, str):
                parts.append(clean_text(item))
            elif isinstance(item, dict):
                t = item.get('text') or item.get('content') or item.get('prompt') or ''
                if t:
                    parts.append(clean_text(t))
        return ' '.join(p for p in parts if p).strip()
    if isinstance(val, dict):
        if 'content' in val:
            return clean_text(val['content'])
        if 'text' in val:
            return clean_text(val['text'])
        if 'message' in val:
            return clean_text(val['message'])
        if 'prompt' in val:
            return clean_text(val['prompt'])
    return str(val)

try:
    mtime = int(os.path.getmtime(sfile))
    timestamp = str(mtime)

    with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                turns += 1
                
                # Check for explicit cwd in log
                if 'cwd' in data and data['cwd'] and os.path.isdir(data['cwd']):
                    workspace = os.path.normpath(data['cwd'])

                ts = data.get('timestamp') or data.get('created_at') or data.get('time')
                if ts and not updated_at:
                    timestamp = str(ts)
                if ts:
                    updated_at = str(ts)

                if not first_prompt:
                    msg_type = data.get('type') or data.get('role')
                    msg_obj = data.get('message')
                    
                    if msg_type in ('user', 'USER_INPUT', 'human') or (isinstance(msg_obj, dict) and msg_obj.get('role') == 'user'):
                        raw = data.get('content') or (msg_obj.get('content') if isinstance(msg_obj, dict) else None) or data.get('text') or ''
                        txt = clean_text(raw)
                        if txt and not txt.startswith('/'):
                            first_prompt = txt
                    elif 'prompt' in data and data['prompt']:
                        first_prompt = clean_text(data['prompt'])
            except Exception:
                continue

    if not match_all:
        ws_norm = os.path.normpath(workspace).rstrip('/')
        if not (ws_norm == target_ws or ws_norm.startswith(target_ws + '/')):
            sys.exit(0)

    if not first_prompt:
        first_prompt = '(Interactive session / command execution)'

    out = {
        'id': session_id,
        'agent': 'Claude Code',
        'timestamp': updated_at or timestamp,
        'workspace': workspace or target_ws,
        'turns': turns,
        'prompt': first_prompt[:200]
    }
    print(json.dumps(out))
except Exception:
    pass
" "$sfile" "$session_id" "$slug" "$target_ws" "$match_all" 2>/dev/null
            fi
        done
    done <<< "$proj_dirs"
}

# Show detailed transcript of a Claude Code session
show_claude_session() {
    local session_id="$1"
    local found_file=""

    if [[ -d "$CLAUDE_PROJECTS_DIR" ]]; then
        found_file="$(find "$CLAUDE_PROJECTS_DIR" -name "${session_id}*.jsonl" -o -name "${session_id}*.json" 2>/dev/null | head -n 1)"
    fi

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id
    actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_ORANGE}=== Claude Code Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}File: ${found_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, re

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<local-command-caveat>.*?</local-command-caveat>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        parts = []
        for item in val:
            if isinstance(item, str):
                parts.append(clean_text(item))
            elif isinstance(item, dict):
                t = item.get('text') or item.get('content') or item.get('prompt') or ''
                if t:
                    parts.append(clean_text(t))
        return ' '.join(p for p in parts if p).strip()
    if isinstance(val, dict):
        if 'content' in val:
            return clean_text(val['content'])
        if 'text' in val:
            return clean_text(val['text'])
        if 'message' in val:
            return clean_text(val['message'])
        if 'prompt' in val:
            return clean_text(val['prompt'])
    return str(val)

sfile = sys.argv[1]
with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
    step = 1
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            role = data.get('type') or data.get('role') or 'event'
            msg_obj = data.get('message')
            if isinstance(msg_obj, dict) and 'role' in msg_obj:
                role = msg_obj.get('role')
                raw_content = msg_obj.get('content')
            else:
                raw_content = data.get('content') or data.get('text') or ''

            content = clean_text(raw_content)
            ts = data.get('timestamp') or data.get('created_at') or ''
            
            if role in ('user', 'USER_INPUT', 'human') and content:
                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m \033[2m{ts}\033[0m')
                print(f'{content}\n')
                step += 1
            elif role in ('assistant', 'PLANNER_RESPONSE', 'model') and content:
                print(f'\033[1;38;5;39m[Turn {step} - Claude]\033[0m \033[2m{ts}\033[0m')
                print(f'{content}\n')
                step += 1
        except Exception:
            continue
" "$found_file"
    else
        cat "$found_file"
    fi
    return 0
}
