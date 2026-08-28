#!/usr/bin/env bash
# ==============================================================================
# agls - Universal 1-Line Installer & Local Setup Script
# Supports:
#   1. Remote 1-line install:
#      curl -fsSL https://raw.githubusercontent.com/elhayat14/agent-sessions/main/install.sh | bash
#   2. Local repo install:
#      ./install.sh
# ==============================================================================

set -euo pipefail

REPO_URL="https://github.com/elhayat14/agent-sessions.git"
DEFAULT_TARGET_DIR="$HOME/.local/share/agent-sessions"

# Check if script is running from a local clone or via piped curl
IS_REMOTE=false
if [[ "${BASH_SOURCE[0]:-}" == "" || "${BASH_SOURCE[0]:-}" == "-" || ! -f "${BASH_SOURCE[0]:-}" ]]; then
    IS_REMOTE=true
elif [[ ! -d "$(dirname "${BASH_SOURCE[0]}")/bin" ]]; then
    IS_REMOTE=true
fi

if [[ "$IS_REMOTE" == "true" ]]; then
    echo "⚡ Installing agls from remote repository ($REPO_URL)..."
    
    # Create parent directory
    mkdir -p "$(dirname "$DEFAULT_TARGET_DIR")"
    
    if [[ -d "$DEFAULT_TARGET_DIR/.git" ]]; then
        echo "Updating existing installation in $DEFAULT_TARGET_DIR..."
        git -C "$DEFAULT_TARGET_DIR" pull --ff-only || true
    else
        echo "Cloning repository to $DEFAULT_TARGET_DIR..."
        rm -rf "$DEFAULT_TARGET_DIR"
        git clone "$REPO_URL" "$DEFAULT_TARGET_DIR"
    fi
    
    SOURCE_DIR="$DEFAULT_TARGET_DIR"
else
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

BIN_SOURCE="$SOURCE_DIR/bin/agls"
chmod +x "$BIN_SOURCE" "$SOURCE_DIR/install.sh" "$SOURCE_DIR/uninstall.sh" 2>/dev/null || true

# Determine install destination
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

echo "Creating symlinks in $INSTALL_DIR..."
ln -sf "$BIN_SOURCE" "$INSTALL_DIR/agls"
ln -sf "$BIN_SOURCE" "$INSTALL_DIR/agent-sessions"

echo "✓ Created symlink: $INSTALL_DIR/agls"
echo "✓ Created symlink: $INSTALL_DIR/agent-sessions"

# Setup completions
if [[ -n "${SHELL:-}" && "$SHELL" == *"zsh"* ]]; then
    ZSH_COMP_DIR="${ZDOTDIR:-$HOME}/.zsh/completion"
    if [[ -d "$ZSH_COMP_DIR" ]]; then
        cp "$SOURCE_DIR/completions/_agls" "$ZSH_COMP_DIR/" 2>/dev/null || true
        echo "✓ Installed Zsh completions to $ZSH_COMP_DIR/_agls"
    fi
elif [[ -n "${SHELL:-}" && "$SHELL" == *"bash"* ]]; then
    BASH_COMP_DIR="$HOME/.bash_completion.d"
    if [[ -d "$BASH_COMP_DIR" ]]; then
        cp "$SOURCE_DIR/completions/agls.bash" "$BASH_COMP_DIR/" 2>/dev/null || true
        echo "✓ Installed Bash completions to $BASH_COMP_DIR/agls.bash"
    fi
fi

# Check PATH
PATH_CONFIGURED=true
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    PATH_CONFIGURED=false
    SHELL_NAME="$(basename "${SHELL:-zsh}")"
    RC_FILE="$HOME/.zshrc"
    [[ "$SHELL_NAME" == "bash" ]] && RC_FILE="$HOME/.bashrc"
    
    echo ""
    echo "⚠️  '$INSTALL_DIR' is not currently in your PATH."
    if [[ -w "$RC_FILE" ]]; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$RC_FILE"
        echo "✓ Added '$INSTALL_DIR' to $RC_FILE"
        echo "Run: source $RC_FILE"
    else
        echo "Please add '$INSTALL_DIR' to your PATH in $RC_FILE"
    fi
fi

echo ""
echo "🎉 agls successfully installed! You can now run:"
echo "    agls"
echo "    agls --help"
