#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$HOME/.local/bin"
ln -sfn "$SCRIPT_DIR/scripts/yr-bk" "$HOME/.local/bin/yr-bk"
chmod +x "$SCRIPT_DIR/scripts/yr-bk"
echo "Installed yr-bk -> $HOME/.local/bin/yr-bk"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo 'Note: add ~/.local/bin to PATH if yr-bk is not found.' ;;
esac
