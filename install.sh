#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
mkdir -p ~/bin
ln -sf "$(pwd)/.build/release/nanomsg" ~/bin/nanomsg
echo "nanomsg installed to ~/bin/nanomsg"

case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "NOTE: ~/bin is not in your PATH. Add it to your shell profile:"; echo '  export PATH="$HOME/bin:$PATH"' ;;
esac
