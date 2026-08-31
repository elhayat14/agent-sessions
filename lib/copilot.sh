#!/usr/bin/env bash
# ==============================================================================
# agls - GitHub Copilot CLI Session Parser
# ==============================================================================

COPILOT_DIRS=(
    "$HOME/.copilot/session-state"
    "$HOME/.config/github-copilot/session-state"
    "$HOME/.copilot/sessions"
)

# Parse all Copilot CLI sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "Copilot", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_copilot_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

copilot_dirs = [
    os.path.expanduser('~/.copilot/session-state'),
    os.path.expanduser('~/.config/github-copilot/session-state'),
    os.path.expanduser('~/.copilot/sessions')
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

for base_dir in copilot_dirs:
    if not os.path.isdir(base_dir):
        continue

    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
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

            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        record = json.loads(line)
                        turns += 1
                        ts = record.get('timestamp')
                        if ts and not created_at: created_at = str(ts)
                        if ts: updated_at = str(ts)

                        data = record.get('data') if isinstance(record.get('data'), dict) else {}
                        rtype = record.get('type') or ''

                        if rtype == 'session.start':
                            sid = data.get('sessionId')
                            if sid: raw_id = str(sid)
                            if data.get('startTime'): created_at = str(data['startTime'])

                        if rtype == 'session.info' or 'trustedFolder' in str(data):
                            msg = data.get('message') or ''
                            m = re.search(r'folder\s+[\'\"]?([^\'\"]+)[\'\"]?', msg)
                            if m and os.path.isdir(m.group(1)):
                                sws = m.group(1)

                        if 'cwd' in data and os.path.isdir(data['cwd']):
                            sws = data['cwd']

                        if rtype == 'user.message' or rtype == 'user':
                            content = data.get('transformedContent') or data.get('content') or record.get('content') or ''
                            txt = clean_text(content)
                            if txt and not first_prompt:
                                first_prompt = txt
                    except Exception:
                        continue

            if is_ws_match(sws):
                seen_ids.add(raw_id)
                out = {
                    'id': raw_id,
                    'agent': 'Copilot',
                    'timestamp': updated_at or created_at or str(mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': (first_prompt or '(Copilot session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of a Copilot session
show_copilot_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${COPILOT_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_PURPLE}=== Copilot Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}File: ${found_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, re

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        return re.sub(r'\s+', ' ', val).strip()
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
            rtype = record.get('type') or ''
            data = record.get('data') if isinstance(record.get('data'), dict) else {}
            
            if rtype in ('user.message', 'user'):
                txt = clean_text(data.get('transformedContent') or data.get('content') or record.get('content') or '')
                if txt:
                    print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                    print(f'{txt}\n')
                    step += 1
            elif rtype in ('assistant.message', 'assistant', 'model'):
                txt = clean_text(data.get('content') or record.get('content') or '')
                if txt:
                    print(f'\033[1;38;5;141m[Turn {step} - Copilot]\033[0m')
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
