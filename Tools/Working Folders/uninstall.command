#!/bin/bash
# Working Folders — uninstaller.  Double-click to remove.
# Created by tk Audio Services.
#
# Stops and removes the menu bar app, its login item and the ~/Applications app.
# It does NOT delete your shelf or your real folders unless you say yes.

set -u

if [ "$(uname)" != "Darwin" ]; then
  echo "macOS only."; exit 1
fi

SUPPORT="$HOME/Library/Application Support/Working Folders"
LABEL="com.tkaudioservices.workingfolders.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/Add to Working Folders.app"
HUB="${WORKING_FOLDERS_HUB:-$HOME/Working Folders}"

say() { printf '%s\n' "$*"; }
ask() { local p="$1" a; printf '%s ' "$p"; read -r a || a=""; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

say "------------------------------------------------------------"
say "  Uninstalling Working Folders"
say "------------------------------------------------------------"

# 1) stop + remove the menu bar login item
GUI="gui/$(id -u)"
launchctl bootout "$GUI/$LABEL" >/dev/null 2>&1
launchctl unload "$PLIST" >/dev/null 2>&1
rm -f "$PLIST" && say "• Removed the menu bar login item."
pkill -f "$SUPPORT/menubar.py" >/dev/null 2>&1 || true

# 2) remove the drag-&-drop app
[ -d "$APP" ] && rm -rf "$APP" && say "• Removed $APP"

# 3) unpin the sidebar entry if mysides is around (otherwise it's a manual step)
if command -v mysides >/dev/null 2>&1; then
  mysides remove "Working Folders" >/dev/null 2>&1 && say "• Unpinned the shelf from the sidebar."
else
  say "• Note: remove the 'Working Folders' item from the Finder sidebar by"
  say "  right-clicking it → 'Remove from Sidebar' (Finder doesn't allow that"
  say "  from a script)."
fi

# 4) optional: the shelf itself (your aliases)
say
if [ -d "$HUB" ]; then
  if ask "Also delete your shelf of shortcuts at \"$HUB\"? (your real folders are NOT affected) [y/N]"; then
    rm -rf "$HUB" && say "• Deleted the shelf. (Your actual project folders are untouched.)"
  else
    say "• Kept your shelf at: $HUB"
  fi
fi

# 5) the installed program files
say
if ask "Delete the installed program files at \"$SUPPORT\"? [y/N]"; then
  # don't yank the directory out from under this running script
  TMP="$(mktemp -d)"; cp -f "$0" "$TMP/uninstall.command" 2>/dev/null
  rm -rf "$SUPPORT" && say "• Removed $SUPPORT"
else
  say "• Kept the program files at: $SUPPORT"
fi

say "------------------------------------------------------------"
say "  Done. Working Folders has been removed."
say "------------------------------------------------------------"
printf '\nPress return to close.'; read -r _ || true
