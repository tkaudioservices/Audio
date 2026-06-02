@echo off
rem Double-click this on Windows to open Galileo Loader in your browser.
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
    py "galileo_loader.py"
) else (
    where python >nul 2>nul
    if %errorlevel%==0 (
        python "galileo_loader.py"
    ) else (
        echo Python 3 is not installed. Get it from https://www.python.org/downloads/
        echo Be sure to tick "Add Python to PATH" during install, then try again.
        pause
    )
)
