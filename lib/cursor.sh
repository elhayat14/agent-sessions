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
        python3 -c "
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
            raw_id = os.path.splitext(filename)[0]
            if raw_id in seen_ids:
                continue

            mtime = int(os.path.getmtime(sfile))
            turns = 0
            first_prompt = ''
            sws = ''
            created_at = ''
            updated_at = ''

            # Check for workspace.json in parent workspaceStorage
            ws_meta = os.path.join(os.path.dirname(os.path.dirname(sfile)), 'workspace.json')
            if os.path.isfile(ws_meta):
                try:
                    with open(ws_meta, 'r', encoding='utf-8') as wsf:
                        wdata = json.load(wsf)
                        uri = wdata.get('folder') or ''
                        if uri.startswith('file://'):
                            sws = os.path.normpath(uri[7:])
                except Exception:
                    pass

            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        record = json.loads(line)
                        turns += 1
                        ts = record.get('timestamp') or record.get('created_at')
                        if ts and not created_at: created_at = str(ts)
                        if ts: updated_at = str(ts)

                        if not sws and 'workspace' in record:
                            sws = record['workspace']

                        role = record.get('role') or record.get('type') or ''
                        if role in ('user', 'human') and not first_prompt:
                            txt = clean_text(record.get('text') or record.get('content') or record.get('message') or '')
                            if txt: first_prompt = txt
                    except Exception:
                        continue

            if is_ws_match(sws):
                seen_ids.add(raw_id)
                out = {
                    'id': raw_id,
                    'agent': 'Cursor',
                    'timestamp': updated_at or created_at or str(mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': (first_prompt or '(Cursor session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
" "$target_ws" "$match_all" 2>/dev/null
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
        python3 -c "
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
" "$found_file"
    else
        cat "$found_file"
    fi
    return 0
}
