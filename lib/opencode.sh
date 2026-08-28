#!/usr/bin/env bash
# ==============================================================================
# agls - OpenCode Session Parser
# ==============================================================================

OPENCODE_DIRS=(
    "$HOME/.local/share/opencode"
    "$HOME/.config/opencode"
    "$HOME/.opencode"
    "$HOME/.cache/opencode"
)

# Parse all OpenCode sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "OpenCode", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_opencode_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, sqlite3, re

target_ws = os.path.normpath(sys.argv[1])
match_all = (sys.argv[2].lower() == 'true')
opencode_dirs = [
    os.path.expanduser('~/.local/share/opencode'),
    os.path.expanduser('~/.config/opencode'),
    os.path.expanduser('~/.opencode'),
    os.path.expanduser('~/.cache/opencode')
]

IGNORED_NAMES = {
    'package', 'package-lock', 'tsconfig', 'models', 'auth', 'settings',
    'config', 'index', 'workspace', 'extensions', 'telemetry', 'state'
}

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        return val.strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('message') or '')
    return str(val)

for base_dir in opencode_dirs:
    if not os.path.isdir(base_dir):
        continue

    # 1. Search for SQLite database if present
    for db_path in glob.glob(os.path.join(base_dir, '**', '*.db'), recursive=True):
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table';\")
            tables = [r[0] for r in cursor.fetchall()]
            for tbl in tables:
                if 'session' in tbl.lower() or 'conversation' in tbl.lower():
                    cursor.execute(f'PRAGMA table_info({tbl});')
                    cols = [c[1] for c in cursor.fetchall()]
                    ws_col = next((c for c in cols if 'workspace' in c.lower() or 'path' in c.lower() or 'dir' in c.lower()), None)
                    id_col = next((c for c in cols if 'id' in c.lower()), cols[0])
                    prompt_col = next((c for c in cols if 'prompt' in c.lower() or 'title' in c.lower() or 'summary' in c.lower() or 'name' in c.lower()), None)
                    time_col = next((c for c in cols if 'time' in c.lower() or 'date' in c.lower() or 'created' in c.lower() or 'updated' in c.lower()), None)

                    select_cols = [id_col]
                    select_cols.append(ws_col if ws_col else '\"\"')
                    select_cols.append(prompt_col if prompt_col else '\"\"')
                    select_cols.append(time_col if time_col else '\"\"')

                    query = f\"SELECT {','.join(select_cols)} FROM {tbl} LIMIT 100;\"
                    cursor.execute(query)
                    for row in cursor.fetchall():
                        sid = str(row[0])
                        sws = str(row[1]) if len(row) > 1 else ''
                        sprompt = str(row[2]) if len(row) > 2 else ''
                        sts = str(row[3]) if len(row) > 3 else ''

                        if sid.lower() in IGNORED_NAMES:
                            continue

                        if match_all or not sws or sws == target_ws or target_ws.startswith(sws):
                            out = {
                                'id': sid,
                                'agent': 'OpenCode',
                                'timestamp': sts or str(int(os.path.getmtime(db_path))),
                                'workspace': sws or target_ws,
                                'turns': 1,
                                'prompt': (clean_text(sprompt) or '(OpenCode session)')[:150]
                            }
                            print(json.dumps(out))
            conn.close()
        except Exception:
            pass

    # 2. Search for JSON / JSONL session files in session directories
    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            session_id = os.path.splitext(filename)[0]
            
            # Skip non-session files
            if session_id.lower() in IGNORED_NAMES or 'node_modules' in sfile:
                continue

            # Check parent directory name - must look like sessions/conversations or ID must look like UUID/ses_
            parent_dir = os.path.basename(os.path.dirname(sfile)).lower()
            is_valid_dir = any(k in parent_dir for k in ('session', 'conversation', 'chat', 'history', 'tasks', 'agents'))
            is_valid_id = bool(re.match(r'^(ses_|task_|conv_|[0-9a-f-]{8,})', session_id, re.I))

            if not (is_valid_dir or is_valid_id):
                continue

            mtime = int(os.path.getmtime(sfile))
            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().strip()
                if not content:
                    continue
                
                data = None
                first_prompt = ''
                sws = ''
                turns = 1

                if content.startswith('{'):
                    try:
                        data = json.loads(content)
                        # Must contain session-like keys
                        if not any(k in data for k in ('messages', 'conversation', 'turns', 'prompt', 'sessionId', 'session_id', 'workspace', 'cwd')):
                            continue
                        
                        sws = data.get('workspace') or data.get('cwd') or data.get('root') or ''
                        first_prompt = clean_text(data.get('prompt') or data.get('title') or data.get('initial_prompt') or '')
                        if 'messages' in data and isinstance(data['messages'], list):
                            turns = len(data['messages'])
                            if not first_prompt and turns > 0:
                                first_prompt = clean_text(data['messages'][0].get('content', ''))
                    except Exception:
                        continue
                
                if match_all or not sws or sws == target_ws or target_ws.startswith(sws):
                    out = {
                        'id': session_id,
                        'agent': 'OpenCode',
                        'timestamp': str(mtime),
                        'workspace': sws or target_ws,
                        'turns': turns,
                        'prompt': (first_prompt or '(OpenCode session)')[:150]
                    }
                    print(json.dumps(out))
        except Exception:
            continue
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of an OpenCode session
show_opencode_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${OPENCODE_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    echo -e "${COLOR_BOLD}${COLOR_GREEN}=== OpenCode Session: ${session_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}File: ${found_file}${COLOR_RESET}\n"

    if has_jq; then
        jq . "$found_file" 2>/dev/null || cat "$found_file"
    else
        cat "$found_file"
    fi
    return 0
}
