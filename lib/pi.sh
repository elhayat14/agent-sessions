#!/usr/bin/env bash
# ==============================================================================
# agls - Pi / OMP / Prime Agent Session Parser
# ==============================================================================

PI_DIRS=(
    "$HOME/.pi/agent/sessions"
    "$HOME/.pi/sessions"
    "$HOME/.omp/agent/sessions"
    "$HOME/.prime/agent/sessions"
    "$HOME/.config/pi/agent/sessions"
)

# Parse all Pi sessions for target workspace
# Outputs JSON records: {"id": "...", "agent": "Pi", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_pi_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 - "$target_ws" "$match_all" << 'EOF' 2>/dev/null
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

pi_dirs = [
    os.path.expanduser('~/.pi/agent/sessions'),
    os.path.expanduser('~/.pi/sessions'),
    os.path.expanduser('~/.omp/agent/sessions'),
    os.path.expanduser('~/.prime/agent/sessions'),
    os.path.expanduser('~/.config/pi/agent/sessions')
]

IGNORED_NAMES = {'settings', 'config', 'history', 'auth', 'telemetry', 'models', 'package', 'package-lock'}

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<system-reminder>.*?</system-reminder>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<\/?command-message>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('prompt') or val.get('message') or '')
    return str(val)

def is_ws_match(sws):
    if match_all:
        return True
    if not sws or not target_ws:
        return False
    s_norm = os.path.normpath(sws).rstrip('/')
    return (s_norm == target_ws) or s_norm.startswith(target_ws + '/')

def extract_cwd(obj):
    if not isinstance(obj, dict):
        return ''
    for k in ('cwd', 'workspace', 'directory', 'project_path', 'root'):
        if k in obj and obj[k] and isinstance(obj[k], str) and obj[k].startswith('/'):
            return obj[k]
    for wrapper_key in ('payload', 'data', 'event', 'meta', 'params', 'args'):
        nested = obj.get(wrapper_key)
        if isinstance(nested, dict):
            c = extract_cwd(nested)
            if c:
                return c
    return ''

seen_ids = set()

for base_dir in pi_dirs:
    if not os.path.isdir(base_dir):
        continue

    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            raw_id = os.path.splitext(filename)[0]
            if raw_id.lower() in IGNORED_NAMES or 'node_modules' in sfile or raw_id in seen_ids:
                continue

            # Skip internal artifact storage directories
            parent_name = os.path.basename(os.path.dirname(sfile))
            if re.match(r'^\d+_[0-9a-f-]{8,}$', parent_name):
                continue

            session_id = raw_id
            mtime = int(os.path.getmtime(sfile))
            turns = 0
            first_prompt = ''
            sws = ''
            created_at = ''
            updated_at = ''

            # Check if single JSON or JSONL
            is_single = False
            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                first_char = f.read(1)
                f.seek(0)
                if first_char == '{':
                    try:
                        content = f.read()
                        data = json.loads(content)
                        is_single = True
                        sid = data.get('session_id') or data.get('id')
                        if sid:
                            session_id = str(sid)
                        sws = extract_cwd(data)
                        first_prompt = clean_text(data.get('prompt') or data.get('title') or '')
                        
                        msgs = data.get('messages') or data.get('turns') or data.get('history') or []
                        if isinstance(msgs, list):
                            turns = len(msgs)
                            for m in msgs:
                                if not sws:
                                    sws = extract_cwd(m)
                                if not first_prompt and isinstance(m, dict) and m.get('role') in ('user', 'human'):
                                    first_prompt = clean_text(m.get('content') or m.get('text') or '')
                    except Exception:
                        is_single = False

            if not is_single:
                with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
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
                                sws = extract_cwd(data)
                            if not first_prompt:
                                role = data.get('role') or data.get('type')
                                if role in ('user', 'human', 'USER_INPUT'):
                                    first_prompt = clean_text(data.get('content') or data.get('message') or data.get('text') or data.get('prompt') or '')
                        except Exception:
                            continue

            if is_ws_match(sws):
                seen_ids.add(session_id)
                seen_ids.add(raw_id)
                
                agent_name = 'Pi'
                if '.omp' in base_dir:
                    agent_name = 'OMP'
                elif '.prime' in base_dir:
                    agent_name = 'Prime'

                out = {
                    'id': session_id,
                    'agent': agent_name,
                    'timestamp': updated_at or created_at or str(mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': (first_prompt or f'({agent_name} session)')[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
EOF
    fi
}

# Show detailed transcript of a Pi session
show_pi_session() {
    local session_id="$1"
    local found_file=""

    for bdir in "${PI_DIRS[@]}"; do
        if [[ -d "$bdir" ]]; then
            found_file="$(find "$bdir" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
            [[ -n "$found_file" ]] && break
        fi
    done

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_PURPLE}=== Pi Session: ${actual_id} ===${COLOR_RESET}"
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
is_single = False
try:
    with open(sfile, 'r', encoding='utf-8') as f:
        data = json.load(f)
        is_single = True
        msgs = data.get('messages') or data.get('turns') or []
        for step, m in enumerate(msgs, 1):
            role = m.get('role') or 'event'
            content = clean_text(m.get('content') or m.get('text') or '')
            if role in ('user', 'human') and content:
                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                print(f'{content}\n')
            elif role in ('assistant', 'model') and content:
                print(f'\033[1;38;5;141m[Turn {step} - Pi]\033[0m')
                print(f'{content}\n')
except Exception:
    is_single = False

if not is_single:
    with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
        step = 1
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                role = data.get('role') or data.get('type') or 'event'
                content = clean_text(data.get('content') or data.get('message') or data.get('text') or '')
                if role in ('user', 'human', 'USER_INPUT') and content:
                    print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                    print(f'{content}\n')
                    step += 1
                elif role in ('assistant', 'model', 'agent') and content:
                    print(f'\033[1;38;5;141m[Turn {step} - Pi]\033[0m')
                    print(f'{content}\n')
                    step += 1
            except Exception:
                continue
EOF
    else
        cat "$found_file"
    fi
    return 0
}
