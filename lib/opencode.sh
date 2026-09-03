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
        python3 - "$target_ws" "$match_all" << 'EOF' 2>/dev/null
import json, os, sys, glob, sqlite3, re

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
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

seen_ids = set()

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

def is_ws_match(sws):
    if match_all:
        return True
    if not sws or not target_ws:
        return False
    s_norm = os.path.normpath(sws).rstrip('/')
    return (s_norm == target_ws) or s_norm.startswith(target_ws + '/')

for base_dir in opencode_dirs:
    if not os.path.isdir(base_dir):
        continue

    # 1. Query SQLite databases (opencode.db)
    db_candidates = [
        os.path.join(base_dir, 'opencode.db'),
        os.path.join(base_dir, 'storage.db'),
        os.path.join(base_dir, 'database.db')
    ]
    for db_path in db_candidates:
        if os.path.isfile(db_path):
            try:
                conn = sqlite3.connect(db_path)
                cur = conn.cursor()
                # Check tables
                cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('session', 'sessions');")
                if cur.fetchone():
                    table_name = 'session'
                    # Select session id, title, directory, time_created, time_updated
                    cur.execute(f"SELECT id, title, directory, time_created, time_updated FROM {table_name}")
                    for row in cur.fetchall():
                        sid, stitle, sdir, t_create, t_update = row[0], row[1], row[2], row[3], row[4]
                        if not sid or sid in seen_ids:
                            continue
                        
                        sws = sdir or ''
                        if is_ws_match(sws):
                            # Count messages if message table exists
                            turns = 1
                            try:
                                cur.execute("SELECT COUNT(*) FROM message WHERE session_id = ?", (sid,))
                                cnt_row = cur.fetchone()
                                if cnt_row and cnt_row[0]:
                                    turns = cnt_row[0]
                            except Exception:
                                pass

                            seen_ids.add(sid)
                            out = {
                                'id': sid,
                                'agent': 'OpenCode',
                                'timestamp': str(t_update or t_create or ''),
                                'workspace': sws,
                                'turns': max(1, turns),
                                'prompt': (clean_text(stitle) or '(OpenCode session)')[:150]
                            }
                            print(json.dumps(out))
                conn.close()
            except Exception:
                pass

    # 2. Check JSON/JSONL session storage
    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            raw_id = os.path.splitext(filename)[0]
            if raw_id.lower() in IGNORED_NAMES or 'node_modules' in sfile or raw_id in seen_ids:
                continue

            session_id = raw_id
            mtime = int(os.path.getmtime(sfile))
            turns = 0
            first_prompt = ''
            sws = ''

            # Check if JSONL
            is_jsonl = sfile.endswith('.jsonl')
            if is_jsonl:
                with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            d = json.loads(line)
                            turns += 1
                            if not sws:
                                sws = d.get('workspace') or d.get('cwd') or d.get('project_path') or ''
                            if not first_prompt:
                                role = d.get('role') or d.get('type')
                                if role in ('user', 'human'):
                                    first_prompt = clean_text(d.get('content') or d.get('text') or '')
                        except Exception:
                            continue
            else:
                with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().strip()
                turns = 1

                if content.startswith('{'):
                    try:
                        data = json.loads(content)
                        if not any(k in data for k in ('messages', 'conversation', 'turns', 'prompt', 'sessionId', 'session_id', 'workspace', 'cwd')):
                            continue
                        
                        sws = data.get('workspace') or data.get('cwd') or data.get('project_path') or ''
                        first_prompt = data.get('prompt') or data.get('title') or data.get('name') or ''
                        
                        msgs = data.get('messages') or data.get('turns') or data.get('history') or []
                        if isinstance(msgs, list):
                            turns = len(msgs)
                            if not first_prompt and turns > 0:
                                for m in msgs:
                                    if isinstance(m, dict) and m.get('role') in ('user', 'human'):
                                        first_prompt = clean_text(m.get('content') or m.get('text') or '')
                                        break
                    except Exception:
                        continue

            if is_ws_match(sws):
                seen_ids.add(session_id)
                out = {
                    'id': session_id,
                    'agent': 'OpenCode',
                    'timestamp': str(mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': (clean_text(first_prompt) or '(OpenCode session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
EOF
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

    # If file not found, check sqlite DB
    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        for bdir in "${OPENCODE_DIRS[@]}"; do
            for db in "$bdir"/*.db "$bdir"/**/*.db; do
                if [[ -f "$db" ]] && command -v python3 &>/dev/null; then
                    local db_res
                    db_res="$(python3 - "$db" "$session_id" << 'EOF' 2>/dev/null
import sqlite3, sys
db_path = sys.argv[1]
sid = sys.argv[2]
try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute('SELECT data FROM message WHERE session_id = ? ORDER BY time_created ASC LIMIT 100', (sid,))
    rows = cur.fetchall()
    if rows:
        print(f'=== OpenCode Session: {sid} ===\nSource DB: {db_path}\n')
        for idx, r in enumerate(rows, 1):
            print(f'[{idx}] {r[0][:200]}')
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
EOF
)"
                    if [[ $? -eq 0 && -n "$db_res" ]]; then
                        echo -e "${COLOR_BOLD}${COLOR_GREEN}${db_res}${COLOR_RESET}"
                        return 0
                    fi
                fi
            done
        done
        return 1
    fi

    local actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}=== OpenCode Session: ${actual_id} ===${COLOR_RESET}"
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
try:
    with open(sfile, 'r', encoding='utf-8') as f:
        data = json.load(f)
        msgs = data.get('messages') or data.get('turns') or []
        for step, m in enumerate(msgs, 1):
            role = m.get('role') or 'event'
            content = clean_text(m.get('content') or m.get('text') or '')
            if role in ('user', 'human') and content:
                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                print(f'{content}\n')
            elif role in ('assistant', 'model') and content:
                print(f'\033[1;38;5;39m[Turn {step} - OpenCode]\033[0m')
                print(f'{content}\n')
except Exception:
    pass
EOF
    else
        cat "$found_file"
    fi
    return 0
}
