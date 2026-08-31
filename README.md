# `agls` — AI Agent Sessions CLI

[![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-success.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS / Linux / WSL](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20WSL-blue.svg)]()
[![Shell: Bash / Zsh](https://img.shields.io/badge/Shell-Bash%20%7C%20Zsh-green.svg)]()

> A fast, lightweight CLI tool to list, filter, inspect, and resume AI agent sessions across workspaces.

Supports **Claude Code**, **Antigravity IDE & CLI (`agy`)**, **OpenCode**, **Codex**, **Pi Agent / OMP / Prime**, **Cline & Roo Code**, **GitHub Copilot CLI**, and **Cursor**.

```
AGENT SESSIONS (Workspace: All Workspaces) Page 1/3

#       SESSION ID                             AGENT         UPDATED     TURNS  
────────────────────────────────────────────────────────────────────────────────
[1]     498f6e24-9b26-4b1a-8c5e-7a2e8e7f1234   Claude Code   11m ago     35
       📂 ~/projects/my-app  •  "Implement rate-limiting middleware in Express"
[2]     b834d95d-7b04-469c-861d-f3afcd204bd0   Antigravity   2h ago      48
       📂 ~/projects/auth-svc •  "Fix JWT authentication expiry bug in auth service"
[3]     ses_001ec48a-1294-4d82-951b-0291ba81   OpenCode      1d ago      12
       📂 ~/work/payment-api  •  "Add unit tests for payment controller"
[4]     cdx_7a8b9c1d-3e2f-4a5b-9c8d-1e2f3a4b   Codex         2d ago      18
       📂 ~/projects/db-core  •  "Refactor database migration scripts"
[5]     pi_98765432-10fe-dcba-9876-543210fed   Pi            3d ago      8
       📂 ~/research/oauth    •  "Research OAuth2 PKCE best practices"
────────────────────────────────────────────────────────────────────────────────
Showing 1-5 of 48 sessions (Page 1/3).  Next: agls -p 2
Quick Resume: agls -r <#|SESSION_ID>  Inspect: agls -i <#|SESSION_ID>
```

---

## 💻 Platform Compatibility

| Operating System / Environment | Support Level | Notes |
| :--- | :--- | :--- |
| **macOS** | **Full Support (100%)** | Native POSIX Bash / Zsh support with BSD date parsing. |
| **Linux** (Ubuntu, Debian, Fedora, Arch, etc.) | **Full Support (100%)** | Native POSIX Bash / Zsh with GNU date parsing. |
| **Windows via WSL** (WSL 1 & 2) | **Full Support (100%)** | Runs natively inside the WSL Linux environment. |
| **Windows via Git Bash / MSYS2** | **Partial Support** | Shell scripts run; path mapping depends on whether agent tools use Windows-native or Unix paths. |
| **Windows Native (PowerShell / CMD)** | **Not Supported** | `agls` is written in POSIX Bash (`#!/usr/bin/env bash`) and requires a Bash shell environment. |

---

## ⚡ 1-Line Quick Install

### Default: Install Latest Stable Release (Recommended)
Installs the latest tested release tag (e.g. `v1.0.0`):

```bash
curl -fsSL https://raw.githubusercontent.com/elhayat14/agent-sessions/main/install.sh | bash
```

The installer will:
1. Clone the repository into `~/.local/share/agent-sessions` and check out the latest stable release tag
2. Create the `agls` (and alias `agent-sessions`) symlink in `~/.local/bin/`
3. Configure shell auto-completions for **Zsh** and **Bash**
4. Verify your `PATH` configuration

---

### Advanced Install Options

#### Install Bleeding Edge (`main` branch)
```bash
curl -fsSL https://raw.githubusercontent.com/elhayat14/agent-sessions/main/install.sh | VERSION=main bash
```

#### Install Specific Release Tag
```bash
curl -fsSL https://raw.githubusercontent.com/elhayat14/agent-sessions/main/install.sh | VERSION=v1.0.0 bash
```

---

### Alternative: Manual Git Clone Installation
```bash
git clone https://github.com/elhayat14/agent-sessions.git
cd agent-sessions
chmod +x bin/agls install.sh uninstall.sh
./install.sh
```

---

## 🚀 How to Resume Sessions

`agls` detects which agent originally created the session and invokes the appropriate command directly:

| AI Agent | Resume Command Executed | Default Storage Location |
| :--- | :--- | :--- |
| **Claude Code** | `claude --resume <session_id>` | `~/.claude/projects/` |
| **Antigravity CLI** | `agy --conversation=<session_id>` | `~/.gemini/antigravity*/brain/` |
| **OpenCode** | `opencode -s <session_id>` | `~/.local/share/opencode/` |
| **Codex** | `codex resume <session_id>` | `~/.codex/sessions/` |
| **Pi / OMP / Prime** | `pi --session <session_id>` | `~/.pi/agent/sessions/` |
| **Cline & Roo Code** | `cline --task <session_id>` | `~/.cline/data/sessions/` |
| **GitHub Copilot CLI** | `copilot --resume <session_id>` | `~/.copilot/session-state/` |
| **Cursor** | `cursor <workspace_path>` | `~/.cursor/projects/` |

### 3 Convenient Ways to Resume:

#### 1. By Row Number `[#]` (Fastest)
`agls` remembers your last viewed search / filter / pagination list in its View State Cache:
```bash
agls --agent claude
agls -r 1        # Resumes session #1 from your Claude list
agls -r 25       # Resumes session #25 from page 2
```

#### 2. By Session ID Prefix
```bash
agls -r 498f6e24 # Resumes by prefix
```

#### 3. Interactive Picker Menu
```bash
agls -r          # Shows an interactive list to choose from
```

---

## 📖 Pagination & Filtering

### Pagination
```bash
agls               # Page 1 (default: 20 sessions per page)
agls -p 2          # Go to Page 2
agls -p 3 -n 10    # Page 3 with 10 items per page
```

### Filtering & Search
```bash
# Filter by agent provider
agls --agent claude
agls --agent antigravity
agls --agent opencode
agls --agent codex
agls --agent pi

# Search by keyword in prompts
agls -s "authentication"
agls --search "refactor database"

# Search across ALL workspaces on your system
agls -a
agls --all -s "docker compose"
```

### Inspecting Session Transcripts
```bash
agls -i 1            # Inspect session #1 from last view
agls --show 498f6e24 # Inspect by session ID prefix
```

### JSON Output
```bash
agls --json | jq .
```

---

## 🔄 Self-Update & Uninstallation

### Update to Latest Stable Release
```bash
agls update
```

### Update to Bleeding Edge (`main` branch)
```bash
agls update --main
```

### Update / Switch to Specific Version
```bash
agls update v1.0.0
```

### Uninstall `agls`
```bash
agls uninstall
# or skip confirmation prompt:
agls uninstall -y
```

---

## 📋 Full Command Reference

```
USAGE:
    agls [COMMAND] [OPTIONS] [WORKSPACE_PATH]

COMMANDS:
    update [TARGET]       Update agls (default: latest tag, or pass '--main' / 'v1.0.0')
    uninstall             Remove agls symlinks and shell completions

ARGUMENTS:
    WORKSPACE_PATH        Target workspace directory (default: current directory '.')

OPTIONS:
    -p, --page <number>   Page number to display (default: 1)
    -n, --limit <number>  Number of sessions per page (default: 20)
    -a, --all             List sessions across all workspaces
    --agent <name>        Filter by agent: claude | antigravity | opencode | codex | pi | all
    -s, --search <query>  Filter sessions containing keyword in prompt or summary
    --json                Output results as JSON
    --show, -i [ID|NUM]   Inspect transcript for a session (by ID, prefix, or table row #)
    --resume, -r [ID|NUM] Resume session (by ID, prefix, or table row #)
    -y, --yes             Auto-confirm prompts (for uninstall/update)
    -v, --version         Show version information
    -h, --help            Show this help message
```

---

## 🔧 Storage Architecture

| Agent Harness | Storage Directory | Workspace Resolution |
| :--- | :--- | :--- |
| **Claude Code** | `~/.claude/projects/` | Path-slug encoded folder names (e.g. `-Users-name-work-app`) |
| **Antigravity** | `~/.gemini/antigravity*/brain/` (`antigravity`, `antigravity-cli`, `antigravity-ide`) | Conversation log traces, metadata, and tool execution CWDs |
| **OpenCode** | `~/.local/share/opencode/` | Workspace state DBs & JSON session logs |
| **Codex** | `~/.codex/sessions/` | JSON & JSONL session files with workspace metadata |
| **Pi Agent** | `~/.pi/agent/sessions/` | JSON & JSONL session files with workspace metadata |

---

## 📜 Changelog
See [CHANGELOG.md](CHANGELOG.md) for full release history and notes.

---

## 📄 License
[MIT License](LICENSE) © 2026 Bahruddin El Hayat
