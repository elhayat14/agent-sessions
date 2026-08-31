#!/usr/bin/env bash
# ==============================================================================
# agls - Cline & Roo Code Session Parser
# ==============================================================================

CLINE_DIRS=(
    "$HOME/.cline/data/sessions"
    "$HOME/.config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"
    "$HOME/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks"
    "$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"
    "$HOME/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks"
)

# Parse all Cline sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "Cline", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_cline_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

cline_dirs = [
    os.path.expanduser('~/.cline/data/sessions'),
    os.path.expanduser('~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks'),
    os.path.expanduser('~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks'),
    os.path.expanduser('~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks'),
    os.path.expanduser('~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks')
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

for base_dir in cline_dirs:
    if not os.path.isdir(base_dir):
        continue

    # Cline structure 1: ~/.cline/data/sessions/<id>/<id>.json + .messages.json
    for mfile in glob.glob(os.path.join(base_dir, '*', '*.json')):
        fname = os.path.basename(mfile)
        if fname.endswith('.messages.json') or fname.startswith('.'):
            continue
        try:
            sid = os.path.splitext(fname)[0]
            if sid in seen_ids:
                continue

            with open(mfile, 'r', encoding='utf-8', errors='ignore') as f:
                meta = json.load(f)
                if not isinstance(meta, dict):
                    continue

                sws = meta.get('cwd') or meta.get('workspace_root') or meta.get('workspace') or ''
                first_prompt = meta.get('task') or meta.get('prompt') or ''
                created_at = meta.get('started_at') or meta.get('created_at') or ''
                turns = 1

                # Check messages file if present
                msg_file = os.path.join(os.path.dirname(mfile), f'{sid}.messages.json')
                if os.path.isfile(msg_file):
                    try:
                        with open(msg_file, 'r', encoding='utf-8', errors='ignore') as mf:
                            mdata = json.load(mf)
                            msgs = mdata.get('messages') or []
                            if isinstance(msgs, list):
                                turns = max(1, len(msgs))
                                if not first_prompt:
                                    for m in msgs:
                                        if isinstance(m, dict) and m.get('role') == 'user':
                                            first_prompt = clean_text(m.get('content') or '')
                                            if first_prompt: break
                    except Exception:
                        pass

                if is_ws_match(sws):
                    seen_ids.add(sid)
                    out = {
                        'id': sid,
                        'agent': 'Cline',
                        'timestamp': str(created_at) or str(int(os.path.getmtime(mfile))),
                        'workspace': sws,
                        'turns': turns,
                        'prompt': (clean_text(first_prompt) or '(Cline task)')[:150]
                    }
                    print(json.dumps(out))
        except Exception:
            continue

    # Cline / Roo structure 2: tasks/<id>/api_conversation_history.json
    for task_dir in glob.glob(os.path.join(base_dir, '*')):
        if not os.path.isdir(task_dir):
            continue
        sid = os.path.basename(task_dir)
        if sid in seen_ids:
            continue

        hist_file = os.path.join(task_dir, 'api_conversation_history.json')
        if os.path.isfile(hist_file):
            try:
                mtime = int(os.path.getmtime(hist_file))
                with open(hist_file, 'r', encoding='utf-8', errors='ignore') as f:
                    msgs = json.load(f)
                    if isinstance(msgs, list) and msgs:
                        first_prompt = ''
                        sws = ''
                        for m in msgs:
                            if isinstance(m, dict) and m.get('role') == 'user':
                                txt = clean_text(m.get('content'))
                                if txt and not first_prompt:
                                    first_prompt = txt
                                if not sws and '<cwd>' in txt:
                                    m_cwd = re.search(r'<cwd>([^<]+)<\/cwd>', txt)
                                    if m_cwd: sws = m_cwd.group(1).strip()

                        if is_ws_match(sws):
                            seen_ids.add(sid)
                            out = {
                                'id': sid,
                                'agent': 'Cline',
                                'timestamp': str(mtime),
                                'workspace': sws,
                                'turns': len(msgs),
                                'prompt': (clean_text(first_prompt) or '(Cline task)')[:150]
                            }
                            print(json.dumps(out))
            except Exception:
                continue
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of a Cline session
show_cline_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${CLINE_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== Cline Session: ${session_id} ===${COLOR_RESET}"
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
try:
    with open(sfile, 'r', encoding='utf-8') as f:
        data = json.load(f)
        msgs = data if isinstance(data, list) else data.get('messages', [])
        for step, m in enumerate(msgs, 1):
            role = m.get('role') or 'event'
            content = clean_text(m.get('content') or m.get('text') or '')
            if role in ('user', 'human') and content:
                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                print(f'{content}\n')
            elif role in ('assistant', 'model', 'agent') and content:
                print(f'\033[1;38;5;51m[Turn {step} - Cline]\033[0m')
                print(f'{content}\n')
except Exception:
    pass
" "$found_file"
    else
        cat "$found_file"
    fi
    return 0
}
