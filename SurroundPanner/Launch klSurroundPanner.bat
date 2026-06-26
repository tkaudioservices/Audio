@echo off
rem tkSurroundPanner launcher (Windows). Starts the bridge and opens the UI.
rem First time? Run "Install tkSurroundPanner.bat" to add the panner to REAPER.
cd /d "%~dp0"
start "" "http://localhost:9000/"
python bridge\reaper_bridge.py
pause
