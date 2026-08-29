# Changelog

All notable changes to **`agls`** (AI Agent Sessions CLI) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-08-29

### 🚀 Initial Stable Release

#### ✨ Multi-Agent Support
- **Claude Code**: Scans `~/.claude/projects/` with path-slug resolution, turn counters, and prompts. Resumes with `claude --resume <id>`.
- **Antigravity IDE & CLI (`agy`)**: Scans conversation brain stores (`~/.gemini/antigravity/brain/`) and tool execution workspaces. Resumes with `agy --conversation=<id>`.
- **OpenCode**: Scans state SQLite databases and JSON session logs in `~/.local/share/opencode/`. Resumes with `opencode -s <id>`.
- **Codex**: Scans `~/.codex/sessions/`, extracts session UUIDs, and unpacks nested event payloads. Resumes with `codex resume <id>`.
- **Pi Agent**: Scans `~/.pi/agent/sessions/` with turn counting and prompt previews. Resumes with `pi --session <id>`.

#### 🔍 Discovery & Filtering
- **Strict Workspace Resolution**: Automatically confines session listings to the active workspace directory without parent-folder directory leaks.
- **Global Search (`-a, --all`)**: List sessions across all projects and workspaces.
- **Keyword Search (`-s, --search`)**: Filter sessions matching prompt queries and summary text.
- **Agent Provider Filter (`--agent`)**: Filter by `claude`, `antigravity`, `opencode`, `codex`, `pi`, or `all`.

#### 📑 Pagination & View State Cache
- **Continuous Pagination**: `-p, --page` and `-n, --limit` with continuous numbering (`[1]`, `[2]`, `[21]`, `[22]`...).
- **View State Cache**: Automatically caches displayed session lists in `~/.cache/agls/last_view.json`.
- **Accurate Row Resuming**: Running `agls -r <#>` or `agls -i <#>` seamlessly resumes the exact row from your previous filtered/search view.

#### 🛠️ Resumption & Inspection
- **3 Resumption Modes**:
  - By row number: `agls -r 1`
  - By session ID / prefix: `agls -r 498f6e24`
  - By interactive picker: `agls -r`
- **Transcript Inspection (`-i, --show`)**: Pretty-printed step-by-step turn inspection with role-colored transcripts.
- **JSON Export (`--json`)**: Structured JSON output for piping into tools like `jq` and custom automation scripts.

#### 📦 Distribution & Self-Management
- **1-Line Remote Installer**: `curl -fsSL https://raw.githubusercontent.com/elhayat14/agent-sessions/main/install.sh | bash`
- **Self-Updating**: `agls update` (pulls latest release and refreshes symlinks/completions).
- **Clean Uninstallation**: `agls uninstall` and standalone `uninstall.sh`.
- **Shell Auto-Completions**: Full completion scripts for **Zsh** (`_agls`) and **Bash** (`agls.bash`).
- **Platform Compatibility**: Tested and verified on **macOS**, **Linux**, and **Windows (WSL)**.
- **Test Suite**: Automated unit and integration test suite (`tests/test_cli.sh`).
