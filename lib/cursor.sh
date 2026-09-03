#!/usr/bin/env bash
# ==============================================================================
# agls - Cursor IDE Agent Transcript Parser
# ==============================================================================

CURSOR_DIRS=(
    "$HOME/.cursor/projects"
    "$HOME/Library/Application Support/Cursor/User/workspaceStorage"
    "$HOME/.config/Cursor/User/workspaceStorage"
)

# Parse all Cursor sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "Cursor", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_cursor_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 - "$target_ws" "$match_all" << 'EOF' 2>/dev/null
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

cursor_dirs = [
    os.path.expanduser('~/.cursor/projects'),
    os.path.expanduser('~/Library/Application Support/Cursor/User/workspaceStorage'),
    os.path.expanduser('~/.config/Cursor/User/workspaceStorage')
]

seen_ids = set()

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        return re.sub(r'\s+', ' ', val).strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('message') or '')
    return str(val)

def is_ws_match(sws):
    if match_all:
        return True
    if not sws or not target_ws:
        return False
    s_norm = os.path.normpath(sws).rstrip('/')
    return (s_norm == target_ws) or s_norm.startswith(target_ws + '/')

for base_dir in cursor_dirs:
    if not os.path.isdir(base_dir):
        continue

    # Search for agent-transcripts
    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        if 'agent-transcripts' not in sfile and 'chat' not in sfile:
            continue
        try:
            filename = os.path.basename(sfile)
            sid = os.path.splitext(filename)[0]
            if sid in seen_ids or 'node_modules' in sfile:
                continue

            mtime = int(os.path.getmtime(sfile))
            sws = ''
            first_prompt = ''
            turns = 0
            created_at = ''

            # Check workspace.json in parent tree
            parent = os.path.dirname(sfile)
            for _ in range(4):
                ws_file = os.path.join(parent, 'workspace.json')
                if os.path.isfile(ws_file):
                    try:
                        with open(ws_file, 'r', encoding='utf-8') as wf:
                            wdata = json.load(wf)
                            folder = wdata.get('folder') or wdata.get('workspace') or ''
                            if folder.startswith('file://'):
                                folder = folder[7:]
                            if folder and os.path.isdir(folder):
                                sws = folder
                                break
                    except Exception:
                        pass
                parent = os.path.dirname(parent)

            # Read transcript events
            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        record = json.loads(line)
                        role = record.get('role') or record.get('type') or ''
                        txt = clean_text(record.get('text') or record.get('content') or record.get('message') or '')
                        
                        if role in ('user', 'human'):
                            turns += 1
                            if not first_prompt and txt:
                                first_prompt = txt
                        elif role in ('assistant', 'model', 'agent'):
                            turns += 1

                        if not sws:
                            cand = record.get('workspace') or record.get('cwd') or record.get('root') or ''
                            if cand and isinstance(cand, str) and cand.startswith('/'):
                                sws = cand
                    except Exception:
                        continue

            if is_ws_match(sws):
                seen_ids.add(sid)
                out = {
                    'id': sid,
                    'agent': 'Cursor',
                    'timestamp': str(created_at or mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': (clean_text(first_prompt) or '(Cursor session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
EOF
    fi
}

# Show detailed transcript of a Cursor session
show_cursor_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${CURSOR_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_BLUE}=== Cursor Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}File: ${found_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 - "$found_file" << 'EOF'
import json, sys

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        return val.strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('message') or '')
    return str(val)

sfile = sys.argv[1]
with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
    step = 1
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            record = json.loads(line)
            role = record.get('role') or record.get('type') or ''
            txt = clean_text(record.get('text') or record.get('content') or record.get('message') or '')
            if role in ('user', 'human') and txt:
                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                print(f'{txt}\n')
                step += 1
            elif role in ('assistant', 'model', 'agent') and txt:
                print(f'\033[1;38;5;39m[Turn {step} - Cursor]\033[0m')
                print(f'{txt}\n')
                step += 1
        except Exception:
            continue
EOF
    else
        cat "$found_file"
    fi
    return 0
}
