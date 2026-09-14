#!/usr/bin/env bash
# ==============================================================================
# ollama-top (otop) — Linux / macOS 1-Click Installer
# Run via: curl -fsSL https://raw.githubusercontent.com/glueck-it/ollama-top/main/install.sh | bash
# ==============================================================================

set -e

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

SCRIPT_URL="https://raw.githubusercontent.com/glueck-it/ollama-top/main/ollama-top.sh"
TARGET="$INSTALL_DIR/otop"

echo "Downloading ollama-top (otop)..."
curl -fsSL "$SCRIPT_URL" -o "$TARGET"
chmod +x "$TARGET"

echo ""
echo "ollama-top installed successfully to $TARGET!"
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "Notice: Add $INSTALL_DIR to your PATH in ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo "Type 'otop' in your terminal to launch the monitor."
echo "Author: Frank Glück (Glück IT) — https://dozent.net"
