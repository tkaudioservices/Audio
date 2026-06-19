@echo off
rem tkSurroundPanner installer (Windows). Run once, and after updates.
cd /d "%~dp0"
if not exist "%APPDATA%\REAPER" ( echo REAPER resource folder not found. & pause & exit /b 1 )
if not exist "%APPDATA%\REAPER\Effects\tk" mkdir "%APPDATA%\REAPER\Effects\tk"
copy /Y "engine\tk_SurroundPanner.jsfx" "%APPDATA%\REAPER\Effects\tk\" >nul && echo Installed JS: tk SurroundPanner -^> Effects\tk\
copy /Y "engine\tk_SurroundNoise.jsfx" "%APPDATA%\REAPER\Effects\tk\" >nul && echo Installed JS: tk SurroundNoise -^> Effects\tk\
echo.
echo Next: add "JS: tk SurroundPanner" to your object tracks (and "JS: tk SurroundNoise" to your bus for Speaker check); Actions -^> Load ReaScript -^> engine\SurroundPanner_Live.lua (run once); then use the launcher.
pause
