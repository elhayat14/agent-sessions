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

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

preferred_dirs = [
    os.path.expanduser('~/.codex/sessions'),
    os.path.expanduser('~/.codex/history'),
    os.path.expanduser('~/.config/codex/sessions')
]
fallback_dir = os.path.expanduser('~/.codex')

search_dirs = [d for d in preferred_dirs if os.path.isdir(d)]
if not search_dirs and os.path.isdir(fallback_dir):
    search_dirs = [fallback_dir]

# 1. Index session_index.jsonl for thread titles
codex_titles = {}
index_files = [
    os.path.expanduser('~/.codex/session_index.jsonl'),
    os.path.expanduser('~/.config/codex/session_index.jsonl')
]
for ifile in index_files:
    if os.path.isfile(ifile):
        try:
            with open(ifile, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        rec = json.loads(line)
                        sid = str(rec.get('id') or '')
                        tname = rec.get('thread_name') or rec.get('title') or ''
                        if sid and tname:
                            codex_titles[sid] = str(tname).strip()
                    except Exception:
                        continue
        except Exception:
            pass

IGNORED_KEYWORDS = {'cache', 'models', 'telemetry', 'config', 'settings', 'auth', 'package', 'node_modules', 'tmp', 'log'}

seen_ids = set()

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<skills_instructions>.*?</skills_instructions>', '', s, flags=re.DOTALL)
        s = re.sub(r'<recommended_plugins>.*?</recommended_plugins>', '', s, flags=re.DOTALL)
        s = re.sub(r'<environment_context>.*?</environment_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<system-reminder>.*?</system-reminder>', '', s, flags=re.DOTALL)
        s = re.sub(r'<codex_internal_context>.*?</codex_internal_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<goal_context>.*?</goal_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<local-command-caveat>.*?</local-command-caveat>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'# AGENTS\.md instructions.*', '', s, flags=re.DOTALL)
        s = re.sub(r'# Context from my IDE setup:.*', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<[^>]+>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        for k in ('content', 'text', 'message', 'prompt', 'query', 'body'):
            if k in val and val[k]:
                return clean_text(val[k])
        for k in ('payload', 'data', 'event'):
            if k in val and isinstance(val[k], dict):
                return clean_text(val[k])
    return str(val)

def extract_prompt_from_dict(obj):
    if not isinstance(obj, dict):
        return ''
    role = obj.get('role') or obj.get('type') or obj.get('event') or ''
    if role in ('user', 'human', 'USER_INPUT', 'user_message', 'input'):
        txt = clean_text(obj.get('content') or obj.get('message') or obj.get('text') or obj.get('prompt') or '')
        if txt:
            return txt
    for wrapper_key in ('payload', 'data', 'event', 'item', 'body'):
        nested = obj.get(wrapper_key)
        if isinstance(nested, dict):
            nested_type = nested.get('type') or nested.get('role') or ''
            if nested_type in ('user', 'human', 'user_message', 'input') or not nested_type:
                txt = clean_text(nested.get('content') or nested.get('message') or nested.get('text') or nested.get('prompt') or '')
                if txt:
                    return txt
    return ''

def extract_cwd(obj):
    if not isinstance(obj, dict):
        return ''
    for k in ('cwd', 'workspace', 'project_path', 'directory', 'path', 'root'):
        if k in obj and obj[k] and isinstance(obj[k], str) and obj[k].startswith('/'):
            return obj[k]
    if 'workspace_roots' in obj and isinstance(obj['workspace_roots'], list) and obj['workspace_roots']:
        if isinstance(obj['workspace_roots'][0], str) and obj['workspace_roots'][0].startswith('/'):
            return obj['workspace_roots'][0]
    for wrapper_key in ('payload', 'data', 'event', 'meta', 'params', 'args'):
        nested = obj.get(wrapper_key)
        if isinstance(nested, dict):
            c = extract_cwd(nested)
            if c:
                return c
    return ''

def is_ws_match(session_ws):
    if match_all:
        return True
    if not session_ws or not target_ws:
        return False
    s_norm = os.path.normpath(session_ws).rstrip('/')
    return (s_norm == target_ws) or s_norm.startswith(target_ws + '/')

def is_worker_session(payload):
    if not isinstance(payload, dict):
        return False
    ts = payload.get('thread_source') or payload.get('threadSource')
    if ts and str(ts).lower() != 'user':
        return True
    src = payload.get('source')
    if isinstance(src, dict) and src.get('subagent'):
        return True
    return False

for base_dir in search_dirs:
    for sfile in glob.glob(os.path.join(base_dir, '**', '*.json*'), recursive=True):
        if not os.path.isfile(sfile) or os.path.basename(sfile).startswith('.'):
            continue
        try:
            filename = os.path.basename(sfile)
            raw_id = os.path.splitext(filename)[0]
            
            if any(k in raw_id.lower() for k in IGNORED_KEYWORDS) or 'node_modules' in sfile:
                continue

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
            meta_title = ''
            sws = ''
            created_at = ''
            updated_at = ''
            is_worker = False

            # First, try parsing as single JSON
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
                            clean_id = str(sid)
                        sws = extract_cwd(data)
                        first_prompt = extract_prompt_from_dict(data)
                        ts = data.get('created_at') or data.get('timestamp')
                        if ts:
                            created_at = str(ts)
                        
                        msgs = data.get('messages') or data.get('turns') or data.get('history') or data.get('events') or []
                        if isinstance(msgs, list):
                            turns = len(msgs)
                            for m in msgs:
                                if not sws:
                                    sws = extract_cwd(m)
                                if not first_prompt:
                                    txt = extract_prompt_from_dict(m)
                                    if txt:
                                        first_prompt = txt
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
                            
                            p = data.get('payload')
                            if data.get('type') == 'session_meta' and isinstance(p, dict):
                                if is_worker_session(p):
                                    is_worker = True
                                    break
                                meta_title = p.get('title') or p.get('thread_name') or p.get('threadName') or ''
                                sid = p.get('id') or p.get('session_id')
                                if sid:
                                    clean_id = str(sid)
                                if not sws:
                                    sws = p.get('cwd') or (p.get('workspace_roots', [None])[0] if isinstance(p.get('workspace_roots'), list) else '')

                            if isinstance(p, dict):
                                if not sws:
                                    sws = p.get('cwd') or (p.get('workspace_roots', [None])[0] if isinstance(p.get('workspace_roots'), list) else '')

                            if not sws:
                                sws = extract_cwd(data)

                            if not sws and '<cwd>' in line:
                                m = re.search(r'<cwd>([^<]+)<\/cwd>', line)
                                if m:
                                    sws = m.group(1).strip()

                            if not first_prompt:
                                if isinstance(p, dict) and p.get('role') == 'user':
                                    c_list = p.get('content') or []
                                    if isinstance(c_list, list):
                                        for item in c_list:
                                            if isinstance(item, dict) and item.get('type') == 'input_text':
                                                txt = clean_text(item.get('text', ''))
                                                if txt and not txt.startswith('# Context') and not txt.startswith('# AGENTS'):
                                                    first_prompt = txt
                                                    break
                                if not first_prompt:
                                    txt = extract_prompt_from_dict(data)
                                    if txt and not txt.startswith('# Context') and not txt.startswith('# AGENTS'):
                                        first_prompt = txt
                        except Exception:
                            continue

            if is_worker:
                continue

            final_title = codex_titles.get(clean_id) or meta_title or first_prompt or '(Codex session)'

            if is_ws_match(sws):
                seen_ids.add(clean_id)
                seen_ids.add(raw_id)
                
                out = {
                    'id': clean_id,
                    'agent': 'Codex',
                    'timestamp': updated_at or created_at or str(mtime),
                    'workspace': sws,
                    'turns': max(1, turns),
                    'prompt': final_title[:150]
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

    local actual_id="$(basename "${found_file%.*}")"
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
        s = re.sub(r'<skills_instructions>.*?</skills_instructions>', '', s, flags=re.DOTALL)
        s = re.sub(r'<recommended_plugins>.*?</recommended_plugins>', '', s, flags=re.DOTALL)
        s = re.sub(r'<environment_context>.*?</environment_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<system-reminder>.*?</system-reminder>', '', s, flags=re.DOTALL)
        s = re.sub(r'<codex_internal_context>.*?</codex_internal_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<goal_context>.*?</goal_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<local-command-caveat>.*?</local-command-caveat>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'# AGENTS\.md instructions.*', '', s, flags=re.DOTALL)
        s = re.sub(r'# Context from my IDE setup:.*', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<[^>]+>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or val.get('message') or '')
    return str(val)

sfile = sys.argv[1]
is_single = False
try:
    with open(sfile, 'r', encoding='utf-8', errors='ignore') as f:
        data = json.loads(f.read())
        is_single = True
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
                if isinstance(data.get('payload'), dict):
                    p = data['payload']
                    role = p.get('type') or p.get('role') or role
                    if p.get('role') == 'user':
                        for item in (p.get('content') or []):
                            txt = clean_text(item.get('text', ''))
                            if txt and not txt.startswith('# Context') and not txt.startswith('# AGENTS'):
                                print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
                                print(f'{txt}\n')
                                step += 1
                                break
                    elif role in ('assistant', 'model', 'agent', 'PLANNER_RESPONSE', 'agent_message'):
                        txt = clean_text(p.get('message') or p.get('content') or '')
                        if txt:
                            print(f'\033[1;38;5;39m[Turn {step} - Codex]\033[0m')
                            print(f'{txt}\n')
                            step += 1
                else:
                    txt = clean_text(data.get('content') or data.get('message') or data.get('text') or '')
                    if role in ('user', 'human', 'USER_INPUT', 'user_message') and txt:
                        print(f'\033[1;38;5;46m[Turn {step} - User]\033[0m')
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
