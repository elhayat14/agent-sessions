#!/usr/bin/env bash
# ==============================================================================
# agls - Uninstallation script
# Removes symlinks, shared directories, and shell completions
# ==============================================================================

set -euo pipefail

echo "Uninstalling agls and agent-sessions..."

# Possible binary directories
BIN_DIRS=(
    "$HOME/.local/bin"
    "/usr/local/bin"
)

# Remove symlinks
for dir in "${BIN_DIRS[@]}"; do
    if [[ -L "$dir/agls" || -f "$dir/agls" ]]; then
        rm -f "$dir/agls"
        echo "✓ Removed: $dir/agls"
    fi
    if [[ -L "$dir/agent-sessions" || -f "$dir/agent-sessions" ]]; then
        rm -f "$dir/agent-sessions"
        echo "✓ Removed: $dir/agent-sessions"
    fi
done

# Remove shared installation folder if installed remotely
REMOTE_INSTALL_DIR="$HOME/.local/share/agent-sessions"
if [[ -d "$REMOTE_INSTALL_DIR" ]]; then
    rm -rf "$REMOTE_INSTALL_DIR"
    echo "✓ Removed: $REMOTE_INSTALL_DIR"
fi

# Remove Zsh completion if present
ZSH_COMP_DIR="${ZDOTDIR:-$HOME}/.zsh/completion"
if [[ -f "$ZSH_COMP_DIR/_agls" ]]; then
    rm -f "$ZSH_COMP_DIR/_agls"
    echo "✓ Removed: $ZSH_COMP_DIR/_agls"
fi

# Remove Bash completion if present
BASH_COMP_DIR="$HOME/.bash_completion.d"
if [[ -f "$BASH_COMP_DIR/agls.bash" ]]; then
    rm -f "$BASH_COMP_DIR/agls.bash"
    echo "✓ Removed: $BASH_COMP_DIR/agls.bash"
fi

echo ""
echo "✨ agls has been completely uninstalled from your system."
