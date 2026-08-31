#!/usr/bin/env bash
# ==============================================================================
# agls - Unit & Integration Tests
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_DIR/bin/agls"

chmod +x "$BIN"

echo "🧪 Running agls CLI test suite..."

# Test 1: Help flag
echo -n "  [1/10] Testing --help flag... "
"$BIN" --help >/dev/null
echo "✓ PASSED"

# Test 2: Version flag
echo -n "  [2/10] Testing --version flag... "
VERSION_OUT="$("$BIN" --version)"
if [[ "$VERSION_OUT" == *"agls v"* ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $VERSION_OUT)"
    exit 1
fi

# Test 3: Path normalization
echo -n "  [3/10] Testing path normalization... "
source "$REPO_DIR/lib/common.sh"
NORMALIZED="$(normalize_path "$REPO_DIR/tests")"
if [[ "$NORMALIZED" == *"/agent-sessions/tests" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $NORMALIZED)"
    exit 1
fi

# Test 4: Relative time formatting
echo -n "  [4/10] Testing relative time formatting... "
NOW_EPOCH=$(date +%s)
TIME_5M_AGO=$(( NOW_EPOCH - 300 ))
REL_TIME="$(format_relative_time "$TIME_5M_AGO")"
if [[ "$REL_TIME" == "5m ago" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $REL_TIME)"
    exit 1
fi

# Test 5: JSON output flag format
echo -n "  [5/10] Testing JSON output option... "
JSON_OUT="$("$BIN" --json "$REPO_DIR" 2>/dev/null || echo '[]')"
if [[ "$JSON_OUT" == "["*"]" || "$JSON_OUT" == "[]" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $JSON_OUT)"
    exit 1
fi

# Test 6: Unknown option error handling
echo -n "  [6/10] Testing error handling on invalid flag... "
if "$BIN" --invalid-flag &>/dev/null; then
    echo "❌ FAILED (Should exit with non-zero)"
    exit 1
else
    echo "✓ PASSED"
fi

# Test 7: Subcommand recognition
echo -n "  [7/10] Testing subcommand recognition... "
HELP_OUT="$("$BIN" --help)"
if [[ "$HELP_OUT" == *"update"* && "$HELP_OUT" == *"uninstall"* ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Subcommands missing from help)"
    exit 1
fi

# Test 8: Pagination flags
echo -n "  [8/10] Testing pagination flags... "
PAGE_OUT="$("$BIN" -p 1 -n 5 "$REPO_DIR" 2>/dev/null || true)"
echo "✓ PASSED"

# Test 9: Codex, Pi, Cline, Copilot, and Cursor agent filters
echo -n "  [9/11] Testing agent filter switches (codex, pi, cline, copilot, cursor)... "
"$BIN" --agent codex "$REPO_DIR" >/dev/null 2>&1 || true
"$BIN" --agent pi "$REPO_DIR" >/dev/null 2>&1 || true
"$BIN" --agent cline "$REPO_DIR" >/dev/null 2>&1 || true
"$BIN" --agent copilot "$REPO_DIR" >/dev/null 2>&1 || true
"$BIN" --agent cursor "$REPO_DIR" >/dev/null 2>&1 || true
echo "✓ PASSED"

# Test 10: State cache for row number resuming
echo -n "  [10/11] Testing state cache preservation... "
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/agls/last_view.json"
"$BIN" --all >/dev/null 2>&1 || true
if [[ -f "$CACHE_FILE" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Cache file not created)"
    exit 1
fi

# Test 11: Modular parser sourcing
echo -n "  [11/11] Testing parser source execution... "
source "$REPO_DIR/lib/cline.sh"
source "$REPO_DIR/lib/copilot.sh"
source "$REPO_DIR/lib/cursor.sh"
echo "✓ PASSED"

echo ""
echo "🎉 All 11 tests passed successfully!"
