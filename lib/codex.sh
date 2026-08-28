#!/usr/bin/env bash
# ==============================================================================
# agls - Codex Session Parser
# ==============================================================================

CODEX_DIRS=(
    "$HOME/.codex/sessions"
    "$HOME/.codex/history"
    "$HOME/.config/codex/sessions"
    "$HOME/.codex"
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

# Look in specific sessions directories first
preferred_dirs = [
    os.path.expanduser('~/.codex/sessions'),
    os.path.expanduser('~/.codex/history'),
    os.path.expanduser('~/.config/codex/sessions')
]
fallback_dir = os.path.expanduser('~/.codex')

search_dirs = [d for d in preferred_dirs if os.path.isdir(d)]
if not search_dirs and os.path.isdir(fallback_dir):
    search_dirs = [fallback_dir]

IGNORED_KEYWORDS = {'cache', 'index', 'models', 'telemetry', 'config', 'settings', 'auth', 'package', 'node_modules', 'tmp', 'log'}

seen_ids = set()

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
        # Look for text / content / message / prompt
        for k in ('content', 'text', 'message', 'prompt', 'query', 'body'):
            if k in val and val[k]:
                return clean_text(val[k])
        # Look in nested payload / data
        for k in ('payload', 'data', 'event'):
            if k in val and isinstance(val[k], dict):
                return clean_text(val[k])
    return str(val)

def extract_prompt_from_dict(obj):
    if not isinstance(obj, dict):
        return ''
    
    # Check direct role
    role = obj.get('role') or obj.get('type') or obj.get('event') or ''
    if role in ('user', 'human', 'USER_INPUT', 'user_message', 'input'):
        txt = clean_text(obj.get('content') or obj.get('message') or obj.get('text') or obj.get('prompt') or '')
        if txt:
            return txt

    # Check payload or data wrapper (common in Codex rollouts)
    for wrapper_key in ('payload', 'data', 'event', 'item', 'body'):
        nested = obj.get(wrapper_key)
        if isinstance(nested, dict):
            nested_type = nested.get('type') or nested.get('role') or ''
            if nested_type in ('user', 'human', 'user_message', 'input') or not nested_type:
                txt = clean_text(nested.get('content') or nested.get('message') or nested.get('text') or nested.get('prompt') or '')
                if txt:
                    return txt
    return ''

for base_dir in search_dirs:
    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            raw_id = os.path.splitext(filename)[0]
            
            # Skip non-session files
            if any(k in raw_id.lower() for k in IGNORED_KEYWORDS) or 'node_modules' in sfile:
                continue

            # Extract clean ID if filename is rollout-YYYY-MM-DD...-<UUID>
            clean_id = raw_id
            match_uuid = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', raw_id, re.I)
            if match_uuid:
                clean_id = match_uuid.group(1)
            elif raw_id.startswith('rollout-'):
                clean_id = raw_id.replace('rollout-', '')

            if clean_id in seen_ids or raw_id in seen_ids:
                continue

            mtime = int(os.path.getmtime(sfile))
            turns = 0
            first_prompt = ''
            sws = ''
            created_at = ''
            updated_at = ''

            with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().strip()
                if not content:
                    continue

                if content.startswith('{') and content.endswith('}'):
                    try:
                        data = json.loads(content)
                        sid = data.get('session_id') or data.get('id')
                        if sid:
                            clean_id = str(sid)
                        sws = data.get('workspace') or data.get('cwd') or data.get('project_path') or ''
                        first_prompt = extract_prompt_from_dict(data)
                        ts = data.get('created_at') or data.get('timestamp')
                        if ts:
                            created_at = str(ts)
                        
                        msgs = data.get('messages') or data.get('turns') or data.get('history') or data.get('events') or []
                        if isinstance(msgs, list):
                            turns = len(msgs)
                            if not first_prompt:
                                for m in msgs:
                                    txt = extract_prompt_from_dict(m)
                                    if txt:
                                        first_prompt = txt
                                        break
                    except Exception:
                        pass
                else:
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
                            
                            # Check session ID and workspace in session_meta events
                            sid = data.get('session_id') or data.get('id')
                            if isinstance(data.get('payload'), dict):
                                sid = sid or data['payload'].get('id') or data['payload'].get('session_id')
                                sws = sws or data['payload'].get('cwd') or data['payload'].get('workspace')
                            
                            if sid:
                                clean_id = str(sid)

                            if not sws:
                                sws = data.get('workspace') or data.get('cwd') or ''

                            if not first_prompt:
                                txt = extract_prompt_from_dict(data)
                                if txt:
                                    first_prompt = txt
                        except Exception:
                            continue

            if match_all or not sws or sws == target_ws or target_ws.startswith(sws) or (sws and sws.startswith(target_ws)):
                seen_ids.add(clean_id)
                seen_ids.add(raw_id)
                
                out = {
                    'id': clean_id,
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
                if isinstance(data.get('payload'), dict):
                    role = data['payload'].get('type') or data['payload'].get('role') or role
                    txt = clean_text(data['payload'].get('message') or data['payload'].get('content') or '')
                else:
                    txt = clean_text(data.get('content') or data.get('message') or data.get('text') or '')
                
                if role in ('user', 'human', 'USER_INPUT', 'user_message') and txt:
                    print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                    print(f'{txt}\n')
                    step += 1
                elif role in ('assistant', 'model', 'agent', 'PLANNER_RESPONSE', 'agent_message') and txt:
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
