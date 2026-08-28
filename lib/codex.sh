#!/usr/bin/env bash
# ==============================================================================
# agls - Codex Session Parser
# ==============================================================================

CODEX_DIRS=(
    "$HOME/.codex/sessions"
    "$HOME/.codex"
    "$HOME/.config/codex/sessions"
)

# Parse all Codex sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "Codex", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_codex_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1])
match_all = (sys.argv[2].lower() == 'true')

codex_dirs = [
    os.path.expanduser('~/.codex/sessions'),
    os.path.expanduser('~/.codex'),
    os.path.expanduser('~/.config/codex/sessions')
]

IGNORED_NAMES = {'settings', 'config', 'history', 'auth', 'telemetry', 'models', 'package', 'package-lock'}

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<\/?command-message>', '', s)
        return s.strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('prompt') or val.get('message') or '')
    return str(val)

for base_dir in codex_dirs:
    if not os.path.isdir(base_dir):
        continue

    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            session_id = os.path.splitext(filename)[0]
            if session_id.lower() in IGNORED_NAMES or 'node_modules' in sfile:
                continue

            mtime = int(os.path.getmtime(sfile))
            turns = 0
            first_prompt = ''
            sws = ''
            created_at = ''
            updated_at = ''

            # Check JSON or JSONL format
            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().strip()
                if not content:
                    continue

                if content.startswith('{') and content.endswith('}'):
                    try:
                        data = json.loads(content)
                        sid = data.get('session_id') or data.get('id') or session_id
                        sws = data.get('workspace') or data.get('cwd') or data.get('project_path') or ''
                        first_prompt = clean_text(data.get('prompt') or data.get('title') or data.get('initial_prompt') or '')
                        ts = data.get('created_at') or data.get('timestamp')
                        if ts:
                            created_at = str(ts)
                        
                        msgs = data.get('messages') or data.get('turns') or data.get('history') or []
                        if isinstance(msgs, list):
                            turns = len(msgs)
                            if not first_prompt and turns > 0:
                                for m in msgs:
                                    if isinstance(m, dict) and m.get('role') in ('user', 'human'):
                                        first_prompt = clean_text(m.get('content') or m.get('text') or '')
                                        break
                    except Exception:
                        pass
                else:
                    # Treat as JSONL
                    for line in content.split('\n'):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            data = json.loads(line)
                            turns += 1
                            ts = data.get('created_at') or data.get('timestamp')
                            if ts and not created_at:
                                created_at = str(ts)
                            if ts:
                                updated_at = str(ts)
                            
                            if not sws:
                                sws = data.get('workspace') or data.get('cwd') or ''

                            if not first_prompt:
                                role = data.get('role') or data.get('type')
                                if role in ('user', 'human', 'USER_INPUT'):
                                    first_prompt = clean_text(data.get('content') or data.get('message') or '')
                        except Exception:
                            continue

            if match_all or not sws or sws == target_ws or target_ws.startswith(sws) or (sws and sws.startswith(target_ws)):
                out = {
                    'id': session_id,
                    'agent': 'Codex',
                    'timestamp': updated_at or created_at or str(mtime),
                    'workspace': sws or target_ws,
                    'turns': max(1, turns),
                    'prompt': (first_prompt or '(Codex session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of a Codex session
show_codex_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${CODEX_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id
    actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_BLUE}=== Codex Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}File: ${found_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, re

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        return s.strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('message') or '')
    return str(val)

sfile = sys.argv[1]
with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read().strip()
    if content.startswith('{') and content.endswith('}'):
        try:
            data = json.loads(content)
            msgs = data.get('messages') or data.get('turns') or []
            for step, m in enumerate(msgs, 1):
                role = m.get('role') or 'event'
                txt = clean_text(m.get('content') or m.get('text') or '')
                if role in ('user', 'human') and txt:
                    print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                    print(f'{txt}\n')
                elif role in ('assistant', 'model', 'agent') and txt:
                    print(f'\033[1;38;5;39m[Turn {step} - Codex]\033[0m')
                    print(f'{txt}\n')
        except Exception:
            print(content)
    else:
        step = 1
        for line in content.split('\n'):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                role = data.get('role') or data.get('type') or 'event'
                txt = clean_text(data.get('content') or data.get('message') or '')
                if role in ('user', 'human', 'USER_INPUT') and txt:
                    print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                    print(f'{txt}\n')
                    step += 1
                elif role in ('assistant', 'model', 'agent', 'PLANNER_RESPONSE') and txt:
                    print(f'\033[1;38;5;39m[Turn {step} - Codex]\033[0m')
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
