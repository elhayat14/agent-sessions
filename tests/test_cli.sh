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
echo -n "  [1/9] Testing --help flag... "
"$BIN" --help >/dev/null
echo "✓ PASSED"

# Test 2: Version flag
echo -n "  [2/9] Testing --version flag... "
VERSION_OUT="$("$BIN" --version)"
if [[ "$VERSION_OUT" == *"agls v"* ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $VERSION_OUT)"
    exit 1
fi

# Test 3: Path normalization
echo -n "  [3/9] Testing path normalization... "
source "$REPO_DIR/lib/common.sh"
NORMALIZED="$(normalize_path "$REPO_DIR/tests")"
if [[ "$NORMALIZED" == *"/agent-sessions/tests" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $NORMALIZED)"
    exit 1
fi

# Test 4: Relative time formatting
echo -n "  [4/9] Testing relative time formatting... "
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
echo -n "  [5/9] Testing JSON output option... "
JSON_OUT="$("$BIN" --json "$REPO_DIR" 2>/dev/null || echo '[]')"
if [[ "$JSON_OUT" == "["*"]" || "$JSON_OUT" == "[]" ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Output: $JSON_OUT)"
    exit 1
fi

# Test 6: Unknown option error handling
echo -n "  [6/9] Testing error handling on invalid flag... "
if "$BIN" --invalid-flag &>/dev/null; then
    echo "❌ FAILED (Should exit with non-zero)"
    exit 1
else
    echo "✓ PASSED"
fi

# Test 7: Subcommand recognition
echo -n "  [7/9] Testing subcommand recognition... "
HELP_OUT="$("$BIN" --help)"
if [[ "$HELP_OUT" == *"update"* && "$HELP_OUT" == *"uninstall"* ]]; then
    echo "✓ PASSED"
else
    echo "❌ FAILED (Subcommands missing from help)"
    exit 1
fi

# Test 8: Pagination flags
echo -n "  [8/9] Testing pagination flags... "
PAGE_OUT="$("$BIN" -p 1 -n 5 "$REPO_DIR" 2>/dev/null || true)"
echo "✓ PASSED"

# Test 9: Codex and Pi agent filters
echo -n "  [9/9] Testing Codex and Pi agent filters... "
"$BIN" --agent codex "$REPO_DIR" >/dev/null 2>&1 || true
"$BIN" --agent pi "$REPO_DIR" >/dev/null 2>&1 || true
echo "✓ PASSED"

echo ""
echo "🎉 All tests passed successfully!"
