#!/usr/bin/env bash
# ==============================================================================
# agls - Antigravity IDE & CLI Session Parser
# ==============================================================================

ANTIGRAVITY_DIR="${ANTIGRAVITY_HOME:-$HOME/.gemini/antigravity}"
ANTIGRAVITY_BRAIN_DIR="$ANTIGRAVITY_DIR/brain"
ANTIGRAVITY_CLI_DIRS=(
    "$HOME/.gemini/antigravity/brain"
    "$HOME/.gemini/antigravity-cli/brain"
    "$HOME/.gemini/antigravity-ide/brain"
    "$HOME/.gemini/antigravity/sessions"
    "$HOME/.gemini/antigravity-cli/sessions"
    "$HOME/.gemini/antigravity-ide/sessions"
    "$HOME/.config/antigravity/brain"
    "$HOME/.config/antigravity-cli/brain"
    "$HOME/.config/antigravity-ide/brain"
    "$HOME/.gemini/tmp"
    "$HOME/.gemini/history"
)

# Parse all Antigravity conversations (IDE & CLI) and filter by workspace
# Outputs JSON records: {"id": "...", "agent": "Antigravity", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_antigravity_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, re, collections

target_ws = os.path.normpath(sys.argv[1]).rstrip('/')
match_all = (sys.argv[2].lower() == 'true')

brain_dirs = [
    os.path.expanduser('~/.gemini/antigravity/brain'),
    os.path.expanduser('~/.gemini/antigravity-cli/brain'),
    os.path.expanduser('~/.gemini/antigravity-ide/brain'),
    os.path.expanduser('~/.gemini/antigravity/sessions'),
    os.path.expanduser('~/.gemini/antigravity-cli/sessions'),
    os.path.expanduser('~/.gemini/antigravity-ide/sessions'),
    os.path.expanduser('~/.config/antigravity/brain'),
    os.path.expanduser('~/.config/antigravity-cli/brain'),
    os.path.expanduser('~/.config/antigravity-ide/brain')
]

home_dir = os.path.expanduser('~')
GENERIC_DIRS = {
    home_dir,
    os.path.join(home_dir, 'Documents'),
    os.path.join(home_dir, 'Desktop'),
    os.path.join(home_dir, 'Downloads'),
    '/Users', '/home', '/'
}

seen_ids = set()

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<session_context>.*?</session_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<[^>]+>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    if isinstance(val, list):
        return ' '.join(clean_text(v) for v in val if v).strip()
    if isinstance(val, dict):
        return clean_text(val.get('content') or val.get('text') or '')
    return str(val)

# Index history.jsonl files for exact workspace joining
history_index = collections.defaultdict(list)
history_files = [
    os.path.expanduser('~/.gemini/antigravity/history.jsonl'),
    os.path.expanduser('~/.gemini/antigravity-cli/history.jsonl'),
    os.path.expanduser('~/.gemini/antigravity-ide/history.jsonl'),
    os.path.expanduser('~/.config/antigravity/history.jsonl')
]
for hf in history_files:
    if os.path.isfile(hf):
        try:
            with open(hf, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        rec = json.loads(line)
                        disp = clean_text(rec.get('display') or rec.get('title') or '')
                        ws = rec.get('workspace', '').strip()
                        ts = rec.get('timestamp') or ''
                        if disp and ws and os.path.isdir(ws):
                            history_index[disp].append({'workspace': os.path.normpath(ws), 'timestamp': str(ts)})
                    except Exception:
                        continue
        except Exception:
            pass

# 1. Check brain / session directories
for bdir in brain_dirs:
    if not os.path.isdir(bdir):
        continue

    for conv_dir in glob.glob(os.path.join(bdir, '*')):
        if not os.path.isdir(conv_dir):
            continue
        
        conv_id = os.path.basename(conv_dir)
        if conv_id in seen_ids or conv_id in ('scratch', 'builtin', 'cache', 'logs'):
            continue

        transcript_file = os.path.join(conv_dir, '.system_generated', 'logs', 'transcript.jsonl')
        if not os.path.isfile(transcript_file):
            transcript_file = os.path.join(conv_dir, '.system_generated', 'logs', 'transcript_full.jsonl')
        if not os.path.isfile(transcript_file):
            candidate_files = glob.glob(os.path.join(conv_dir, '**', '*.json*'), recursive=True)
            if candidate_files:
                transcript_file = candidate_files[0]

        if not os.path.isfile(transcript_file):
            continue

        try:
            turns = 0
            first_prompt = ''
            created_at = ''
            updated_at = ''
            ws_scores = collections.defaultdict(int)

            meta_file = os.path.join(conv_dir, 'metadata.json')
            if os.path.isfile(meta_file):
                try:
                    with open(meta_file, 'r', encoding='utf-8') as mf:
                        mdata = json.load(mf)
                        if 'workspace' in mdata and mdata['workspace']:
                            p = os.path.normpath(mdata['workspace'])
                            ws_scores[p] += 50
                        if 'created_at' in mdata and mdata['created_at']:
                            created_at = str(mdata['created_at'])
                        if 'summary' in mdata and mdata['summary']:
                            first_prompt = clean_text(mdata['summary'])
                except Exception:
                    pass

            mtime = int(os.path.getmtime(transcript_file))
            if not created_at:
                created_at = str(mtime)

            with open(transcript_file, 'r', encoding='utf-8', errors='ignore') as f:
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

                        tool_calls = data.get('tool_calls') or []
                        for tc in tool_calls:
                            args = tc.get('args') or tc.get('parameters') or {}
                            for key in ('DirectoryPath', 'Cwd', 'SearchDirectory', 'SearchPath', 'TargetFile', 'AbsolutePath'):
                                val = args.get(key)
                                if val and isinstance(val, str):
                                    val = val.strip('\"\'')
                                    if val.startswith('/'):
                                        dir_path = val if (key in ('DirectoryPath', 'Cwd', 'SearchDirectory', 'SearchPath') or os.path.isdir(val)) else os.path.dirname(val)
                                        p = os.path.normpath(dir_path)
                                        weight = 10 if key in ('Cwd', 'DirectoryPath') else 3
                                        ws_scores[p] += weight

                        raw_content = data.get('content') or ''
                        if not first_prompt and (data.get('type') in ('USER_INPUT', 'user') or data.get('source') == 'USER_EXPLICIT'):
                            txt = clean_text(raw_content)
                            if txt and not txt.startswith('<system_message>'):
                                first_prompt = txt
                    except Exception:
                        continue

            if first_prompt and first_prompt in history_index:
                for entry in history_index[first_prompt]:
                    ws_scores[entry['workspace']] += 100

            # Filter out non-existent directories or internal temp paths
            valid_candidates = []
            for p, score in ws_scores.items():
                if os.path.isdir(p) and not p.endswith('/.gemini') and not '/.gemini/' in p and not p.endswith('/scratch'):
                    valid_candidates.append((p, score))

            # Filter out generic home/Documents folders if specific project paths exist
            specific_candidates = [(p, sc) for p, sc in valid_candidates if p not in GENERIC_DIRS]
            candidates = specific_candidates if specific_candidates else valid_candidates

            resolved_ws = candidates[0][0] if candidates else ''

            is_match = False
            if match_all:
                is_match = True
            else:
                for p, _ in candidates:
                    p_norm = os.path.normpath(p).rstrip('/')
                    if p_norm == target_ws or p_norm.startswith(target_ws + '/'):
                        is_match = True
                        resolved_ws = p_norm
                        break

            if is_match:
                seen_ids.add(conv_id)
                if not first_prompt:
                    first_prompt = '(Antigravity session / conversation)'
                
                out = {
                    'id': conv_id,
                    'agent': 'Antigravity',
                    'timestamp': updated_at or created_at,
                    'workspace': resolved_ws,
                    'turns': turns,
                    'prompt': first_prompt[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue

# 2. Check Gemini CLI projects.json & tmp/*/chats
projects_file = os.path.expanduser('~/.gemini/projects.json')
if os.path.isfile(projects_file):
    try:
        with open(projects_file, 'r', encoding='utf-8') as pf:
            proj_map = json.load(pf).get('projects', {})
            for ws_path, slug in proj_map.items():
                ws_norm = os.path.normpath(ws_path).rstrip('/')
                is_proj_match = match_all or (ws_norm == target_ws) or ws_norm.startswith(target_ws + '/')
                if not is_proj_match:
                    continue

                chat_patterns = [
                    os.path.expanduser(f'~/.gemini/tmp/{slug}/chats/*.jsonl'),
                    os.path.expanduser(f'~/.gemini/history/{slug}/*.json*')
                ]
                for pat in chat_patterns:
                    for cfile in glob.glob(pat):
                        if not os.path.isfile(cfile):
                            continue
                        fname = os.path.basename(cfile)
                        cid = os.path.splitext(fname)[0]
                        if cid in seen_ids:
                            continue
                        try:
                            mtime = int(os.path.getmtime(cfile))
                            turns = 0
                            prompt = ''
                            last_ts = ''
                            with open(cfile, 'r', encoding='utf-8', errors='ignore') as cf:
                                for line in cf:
                                    line = line.strip()
                                    if not line: continue
                                    d = json.loads(line)
                                    msgs = d.get('$set', {}).get('messages', []) or d.get('messages', [])
                                    if msgs:
                                        turns = max(turns, len(msgs))
                                        for m in msgs:
                                            if not last_ts and m.get('timestamp'):
                                                last_ts = m.get('timestamp')
                                            if not prompt:
                                                c = m.get('content') or m.get('text') or ''
                                                if isinstance(c, list):
                                                    for part in c:
                                                        if isinstance(part, dict) and 'text' in part:
                                                            t = clean_text(part['text'])
                                                            if t: prompt = t; break
                                                elif isinstance(c, str):
                                                    t = clean_text(c)
                                                    if t: prompt = t

                            seen_ids.add(cid)
                            out = {
                                'id': cid,
                                'agent': 'Antigravity',
                                'timestamp': last_ts or str(mtime),
                                'workspace': ws_norm,
                                'turns': max(1, turns),
                                'prompt': (prompt or '(Gemini session)')[:150]
                            }
                            print(json.dumps(out))
                        except Exception:
                            continue
    except Exception:
        pass
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of an Antigravity conversation
show_antigravity_session() {
    local session_id="$1"
    local conv_dir=""
    local found_file=""
    local brain_dirs=(
        "$ANTIGRAVITY_BRAIN_DIR"
        "$HOME/.gemini/antigravity/brain"
        "$HOME/.gemini/antigravity-cli/brain"
        "$HOME/.gemini/antigravity-ide/brain"
        "$HOME/.gemini/antigravity/sessions"
        "$HOME/.gemini/antigravity-cli/sessions"
        "$HOME/.gemini/antigravity-ide/sessions"
        "$HOME/.config/antigravity/brain"
        "$HOME/.config/antigravity-cli/brain"
        "$HOME/.config/antigravity-ide/brain"
    )

    for bdir in "${brain_dirs[@]}"; do
        if [[ -d "$bdir/$session_id" ]]; then
            conv_dir="$bdir/$session_id"
            break
        elif [[ -d "$bdir" ]]; then
            conv_dir="$(find "$bdir" -maxdepth 1 -name "*${session_id}*" -type d 2>/dev/null | head -n 1)"
            [[ -n "$conv_dir" ]] && break
        fi
    done

    if [[ -n "$conv_dir" && -d "$conv_dir" ]]; then
        found_file="$conv_dir/.system_generated/logs/transcript.jsonl"
        if [[ ! -f "$found_file" ]]; then
            found_file="$conv_dir/.system_generated/logs/transcript_full.jsonl"
        fi
        if [[ ! -f "$found_file" ]]; then
            found_file="$(find "$conv_dir" -name "*.json*" 2>/dev/null | head -n 1)"
        fi
    fi

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        found_file="$(find "$HOME/.gemini" -name "*${session_id}*.json*" 2>/dev/null | head -n 1)"
    fi

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        return 1
    fi

    local actual_id="$(basename "${found_file%.*}")"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== Antigravity Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}Log: ${found_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, re

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<session_context>.*?</session_context>', '', s, flags=re.DOTALL)
        s = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', s, flags=re.DOTALL)
        s = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-message>.*?</command-message>', '', s, flags=re.DOTALL)
        s = re.sub(r'<command-name>.*?</command-name>', '', s, flags=re.DOTALL)
        s = re.sub(r'<\/?command-message>', '', s)
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        s = re.sub(r'<[^>]+>', '', s)
        return re.sub(r'\s+', ' ', s).strip()
    return str(val)

tfile = sys.argv[1]
with open(tfile, 'r', encoding='utf-8', errors='ignore') as f:
    step = 1
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            stype = data.get('type') or ''
            source = data.get('source') or ''
            ts = data.get('created_at') or data.get('timestamp') or ''
            raw_content = data.get('content') or data.get('message') or ''
            
            msgs = data.get('\$set', {}).get('messages', []) or data.get('messages', [])
            if msgs:
                for m in msgs:
                    m_role = m.get('type') or m.get('role') or 'event'
                    m_ts = m.get('timestamp') or ''
                    m_content = clean_text(m.get('content') or m.get('text') or '')
                    if m_role in ('user', 'human') and m_content:
                        print(f'\033[1;38;5;46m[Step {step} - User]\033[0m \033[2m{m_ts}\033[0m')
                        print(f'{m_content}\n')
                        step += 1
                    elif m_role in ('assistant', 'model') and m_content:
                        print(f'\033[1;38;5;51m[Step {step} - Gemini]\033[0m \033[2m{m_ts}\033[0m')
                        print(f'{m_content}\n')
                        step += 1
                continue

            content = clean_text(raw_content)
            if (stype in ('USER_INPUT', 'user') or source == 'USER_EXPLICIT') and content:
                print(f'\033[1;38;5;46m[Step {step} - User]\033[0m \033[2m{ts}\033[0m')
                print(f'{content}\n')
                step += 1
            elif (stype in ('PLANNER_RESPONSE', 'model', 'assistant') or source == 'MODEL'):
                if content:
                    print(f'\033[1;38;5;51m[Step {step} - Antigravity Agent]\033[0m \033[2m{ts}\033[0m')
                    print(f'{content}\n')
                tool_calls = data.get('tool_calls') or []
                if tool_calls:
                    for tc in tool_calls:
                        tname = tc.get('name') or tc.get('tool') or 'tool'
                        print(f'\033[38;5;208m  > Tool Call: {tname}\033[0m')
                    print('')
                step += 1
        except Exception:
            continue
" "$found_file"
    else
        cat "$found_file"
    fi
    return 0
}
