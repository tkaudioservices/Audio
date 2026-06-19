#!/bin/bash
# tkSurroundPanner — one-click launcher (macOS)
# Double-click. It installs the panner into REAPER, starts the bridge, opens the UI.

cd "$(dirname "$0")" || exit 1
clear
echo "──────────────────────────────────────────────"
echo "  tkSurroundPanner — tk Audio Services"
echo "──────────────────────────────────────────────"
echo "  (first time? run 'Install tkSurroundPanner.command' to add the panner to REAPER)"
echo

URL="http://localhost:9000/"

# Already running? (any versioned bridge is current; an unversioned one is stale.)
PING=$(curl -s --max-time 1 "${URL}ping")
if echo "$PING" | grep -q '"version"'; then
  echo "  Bridge already running — opening the UI."
  open "$URL"
  exit 0
elif [ -n "$PING" ]; then
  echo "  An OLD bridge is running on port 9000 — close that window (Ctrl-C), then re-run."
  read -n 1 -s -r -p "  Press any key to close."
  exit 1
fi

# Find a Python 3 interpreter.
PY=""
for c in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3 python; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  echo "  Python 3 was not found. Install from https://www.python.org/downloads/ and retry."
  read -n 1 -s -r -p "  Press any key to close."
  exit 1
fi

# Open the browser once the bridge answers.
(
  for _ in $(seq 1 40); do
    if curl -s -o /dev/null --max-time 1 "${URL}ping"; then open "$URL"; break; fi
    sleep 0.25
  done
) &

echo "  Starting bridge…  (close this window to stop everything)"
echo
"$PY" bridge/reaper_bridge.py

echo
echo "  Bridge stopped."
read -n 1 -s -r -p "  Press any key to close."
