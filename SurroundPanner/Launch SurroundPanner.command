#!/bin/bash
# Double-click launcher (macOS). Starts the bridge and opens the UI.
cd "$(dirname "$0")"
( sleep 1.5; open "http://localhost:9000/" ) &
exec python3 bridge/reaper_bridge.py
