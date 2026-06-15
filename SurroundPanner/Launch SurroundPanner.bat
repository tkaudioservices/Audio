@echo off
rem Double-click launcher (Windows). Starts the bridge and opens the UI.
cd /d "%~dp0"
start "" "http://localhost:9000/"
python bridge\reaper_bridge.py
pause
