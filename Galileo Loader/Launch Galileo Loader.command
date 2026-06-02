#!/bin/bash
# Double-click this on macOS to open the Galileo Loader window.
# (It just runs galileo_loader.py with Python 3.)
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is not installed. Install it from https://www.python.org/downloads/ and try again."
  echo "Press any key to close."; read -n 1 -s; exit 1
fi
exec python3 "galileo_loader.py"
