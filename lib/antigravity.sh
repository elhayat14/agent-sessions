#!/usr/bin/env bash
# ==============================================================================
# agls - Antigravity IDE & CLI Session Parser
# ==============================================================================

ANTIGRAVITY_DIR="${ANTIGRAVITY_HOME:-$HOME/.gemini/antigravity}"
ANTIGRAVITY_BRAIN_DIR="$ANTIGRAVITY_DIR/brain"
ANTIGRAVITY_CLI_DIRS=(
    "$HOME/.gemini/antigravity-cli"
    "$HOME/.gemini/antigravity"
    "$HOME/.config/antigravity"
)

# Parse all Antigravity conversations (IDE & CLI) and filter by workspace
# Outputs JSON records: {"id": "...", "agent": "Antigravity", "timestamp": "...", "workspace": "...", "turns": N, "prompt": "..."}
list_antigravity_sessions() {
    local target_ws="$1"
    local match_all="${2:-false}"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys, glob, re

target_ws = os.path.normpath(sys.argv[1])
match_all = (sys.argv[2].lower() == 'true')

brain_dirs = [
    os.path.expanduser('~/.gemini/antigravity/brain'),
    os.path.expanduser('~/.gemini/antigravity-cli/brain'),
    os.path.expanduser('~/.gemini/antigravity-cli/sessions'),
    os.path.expanduser('~/.config/antigravity/brain')
]

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
        return clean_text(val.get('content') or val.get('text') or '')
    return str(val)

for bdir in brain_dirs:
    if not os.path.isdir(bdir):
        continue

    for conv_dir in glob.glob(os.path.join(bdir, '*')):
        if not os.path.isdir(conv_dir):
            continue
        
        conv_id = os.path.basename(conv_dir)
        if conv_id in seen_ids or conv_id in ('scratch', 'builtin', 'cache', 'logs'):
            continue
        
        # Check transcripts
        log_dir = os.path.join(conv_dir, '.system_generated', 'logs')
        transcript_file = os.path.join(log_dir, 'transcript.jsonl')
        if not os.path.exists(transcript_file):
            transcript_file = os.path.join(log_dir, 'transcript_full.jsonl')
        if not os.path.exists(transcript_file):
            # Check for direct json/jsonl in directory (CLI sessions)
            candidates = glob.glob(os.path.join(conv_dir, '*.json*'))
            if candidates:
                transcript_file = candidates[0]
            else:
                continue

        turns = 0
        first_prompt = ''
        created_at = ''
        updated_at = ''
        session_workspaces = set()

        # Check metadata.json if present
        meta_file = os.path.join(conv_dir, 'metadata.json')
        if os.path.exists(meta_file):
            try:
                with open(meta_file, 'r', encoding='utf-8') as mf:
                    mdata = json.load(mf)
                    if 'workspace' in mdata:
                        session_workspaces.add(os.path.normpath(mdata['workspace']))
                    if 'created_at' in mdata:
                        created_at = str(mdata['created_at'])
            except Exception:
                pass

        try:
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

                        # Check tool calls for workspace directory
                        tool_calls = data.get('tool_calls') or []
                        for tc in tool_calls:
                            args = tc.get('args') or tc.get('parameters') or {}
                            for key in ('Cwd', 'SearchDirectory', 'SearchPath', 'TargetFile', 'AbsolutePath'):
                                val = args.get(key)
                                if val and isinstance(val, str) and val.startswith('/'):
                                    dir_path = val if (key in ('Cwd', 'SearchDirectory', 'SearchPath') or os.path.isdir(val)) else os.path.dirname(val)
                                    session_workspaces.add(os.path.normpath(dir_path))

                        # Check content for workspace mentions (e.g. user_information block)
                        raw_content = data.get('content') or ''
                        if isinstance(raw_content, str) and '/Users/' in raw_content:
                            matches = re.findall(r'(\/(?:Users|home)\/[a-zA-Z0-9_\-\.\/]+)', raw_content)
                            for m in matches:
                                if os.path.isdir(m) and not m.endswith('/.gemini') and not m.endswith('/scratch'):
                                    session_workspaces.add(os.path.normpath(m))

                        # Check prompt content
                        if not first_prompt and (data.get('type') in ('USER_INPUT', 'user') or data.get('source') == 'USER_EXPLICIT'):
                            txt = clean_text(raw_content)
                            if txt and not txt.startswith('<system_message>'):
                                first_prompt = txt
                    except Exception:
                        continue

            is_match = False
            matched_ws = target_ws

            if match_all:
                is_match = True
                if session_workspaces:
                    matched_ws = sorted(list(session_workspaces), key=len)[0]
            else:
                for ws in session_workspaces:
                    if ws == target_ws or ws.startswith(target_ws + '/') or target_ws.startswith(ws + '/'):
                        is_match = True
                        matched_ws = ws
                        break
                if not is_match and not session_workspaces and target_ws in ('', '.'):
                    is_match = True

            if is_match:
                seen_ids.add(conv_id)
                if not first_prompt:
                    first_prompt = '(Antigravity session / conversation)'
                
                out = {
                    'id': conv_id,
                    'agent': 'Antigravity',
                    'timestamp': updated_at or created_at,
                    'workspace': matched_ws,
                    'turns': turns,
                    'prompt': first_prompt[:150]
                }
                print(json.dumps(out))
        except Exception:
            continue
" "$target_ws" "$match_all" 2>/dev/null
    fi
}

# Show detailed transcript of an Antigravity conversation
show_antigravity_session() {
    local session_id="$1"
    local conv_dir=""
    local brain_dirs=(
        "$ANTIGRAVITY_BRAIN_DIR"
        "$HOME/.gemini/antigravity-cli/brain"
        "$HOME/.gemini/antigravity-cli/sessions"
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

    if [[ -z "$conv_dir" || ! -d "$conv_dir" ]]; then
        return 1
    fi

    local transcript_file="$conv_dir/.system_generated/logs/transcript.jsonl"
    if [[ ! -f "$transcript_file" ]]; then
        transcript_file="$conv_dir/.system_generated/logs/transcript_full.jsonl"
    fi
    if [[ ! -f "$transcript_file" ]]; then
        transcript_file="$(find "$conv_dir" -name "*.json*" 2>/dev/null | head -n 1)"
    fi

    if [[ -z "$transcript_file" || ! -f "$transcript_file" ]]; then
        return 1
    fi

    local actual_id="$(basename "$conv_dir")"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== Antigravity Session: ${actual_id} ===${COLOR_RESET}"
    echo -e "${COLOR_DIM}Log: ${transcript_file}${COLOR_RESET}\n"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, re

def clean_text(val):
    if not val:
        return ''
    if isinstance(val, str):
        s = val.strip()
        s = re.sub(r'<\/?USER_REQUEST>', '', s)
        return s.strip()
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
" "$transcript_file"
    else
        cat "$transcript_file"
    fi
    return 0
}
