#!/bin/bash
# Working Folders — installer.  Double-click to install.
# Created by tk Audio Services.
#
# Puts the tool in a stable home (~/Library/Application Support/Working Folders),
# builds the drag-&-drop app into ~/Applications, sets up your shelf, and (if
# PyObjC is available) starts the ★ menu bar app and keeps it running at login.
# Nothing here needs admin/sudo. Re-runnable. Undo with uninstall.command.

set -u

if [ "$(uname)" != "Darwin" ]; then
  echo "Working Folders is macOS-only."; exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/Working Folders"
LABEL="com.tkaudioservices.workingfolders.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PY="/usr/bin/python3"
SYMBOL="${WORKING_FOLDERS_SYMBOL:-star}"

say() { printf '%s\n' "$*"; }
hr()  { say "------------------------------------------------------------"; }

hr
say "  Installing Working Folders"
hr

# 1) copy the tool into a stable location -----------------------------------
mkdir -p "$SUPPORT"
for f in working-folders.sh droplet.applescript menubar.py \
         "Working Folders.command" uninstall.command README.md; do
  [ -e "$SRC/$f" ] && cp -f "$SRC/$f" "$SUPPORT/$f"
done
chmod +x "$SUPPORT/working-folders.sh" "$SUPPORT/Working Folders.command" \
         "$SUPPORT/uninstall.command" 2>/dev/null
say "• Installed to:  $SUPPORT"

# 2) build the drag-&-drop app (into ~/Applications, with the star icon) -----
if bash "$SUPPORT/working-folders.sh" build-app; then
  say "• Built the drag-&-drop app in ~/Applications."
else
  say "• (Skipped the app build — see messages above.)"
fi

# 3) create the shelf + give it the icon + sidebar instructions -------------
say
bash "$SUPPORT/working-folders.sh" setup
say

# 4) PyObjC — needed for the menu bar app AND the auto icon ------------------
hr
if "$PY" -c "import AppKit" >/dev/null 2>&1; then
  say "• PyObjC is present — enabling the ★ menu bar app."
  HAVE_PYOBJC=1
else
  say "The ★ menu bar app (and the automatic star icon) need Apple's PyObjC,"
  say "which isn't in this Mac's /usr/bin/python3 yet. I can add it just for"
  say "your user (no admin needed) with:"
  say "    $PY -m pip install --user pyobjc-framework-Cocoa"
  printf 'Install it now? [y/N] '
  read -r ans
  case "$ans" in
    y | Y | yes | YES)
      "$PY" -m pip install --user --upgrade pip >/dev/null 2>&1
      if "$PY" -m pip install --user pyobjc-framework-Cocoa && "$PY" -c "import AppKit" >/dev/null 2>&1; then
        say "• PyObjC installed."
        HAVE_PYOBJC=1
        # backfill the icons now that we can render them
        bash "$SUPPORT/working-folders.sh" build-app >/dev/null 2>&1
        "$PY" - "$SYMBOL" "$HOME/Working Folders" >/dev/null 2>&1 <<'PY' || true
import sys
from AppKit import (NSImage, NSWorkspace, NSColor, NSColorSpace, NSBezierPath,
                    NSImageSymbolConfiguration, NSGraphicsContext)
from Foundation import NSMakeRect, NSZeroRect
sym, dest, size = sys.argv[1], sys.argv[2], 512
base = NSImage.imageWithSystemSymbolName_accessibilityDescription_(sym, None)
if base is None:
    sys.exit(0)
cfg = NSImageSymbolConfiguration.configurationWithPointSize_weight_scale_(200.0, 0.0, 3)
glyph = base.imageWithSymbolConfiguration_(cfg) or base
try:
    col = NSColor.controlAccentColor().colorUsingColorSpace_(NSColorSpace.sRGBColorSpace())
except Exception:
    col = NSColor.colorWithSRGBRed_green_blue_alpha_(10/255.0, 132/255.0, 255/255.0, 1.0)
canvas = NSImage.alloc().initWithSize_((size, size))
canvas.lockFocus()
s = glyph.size(); box = size * 0.62
k = box / (s.width if s.width >= s.height else s.height)
dw, dh = s.width * k, s.height * k
glyph.drawInRect_fromRect_operation_fraction_(NSMakeRect((size-dw)/2.0, (size-dh)/2.0, dw, dh), NSZeroRect, 2, 1.0)
NSGraphicsContext.currentContext().setCompositingOperation_(5)
col.set(); NSBezierPath.bezierPathWithRect_(NSMakeRect(0, 0, size, size)).fill()
canvas.unlockFocus()
NSWorkspace.sharedWorkspace().setIcon_forFile_options_(canvas, dest, 0)
PY
      else
        say "• PyObjC install didn't complete — skipping the menu bar app and"
        say "  the auto icon. Everything else still works."
        HAVE_PYOBJC=0
      fi
      ;;
    *)
      say "• Skipped PyObjC. The shelf, the app and the sidebar all still work;"
      say "  you just won't get the menu bar app or the auto icon (set an icon"
      say "  by hand any time — see the README)."
      HAVE_PYOBJC=0
      ;;
  esac
fi

# 5) install + start the menu bar LaunchAgent -------------------------------
if [ "${HAVE_PYOBJC:-0}" = "1" ]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$PY</string>
		<string>$SUPPORT/menubar.py</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>WORKING_FOLDERS_HUB</key>
		<string>${WORKING_FOLDERS_HUB:-$HOME/Working Folders}</string>
		<key>WORKING_FOLDERS_SYMBOL</key>
		<string>$SYMBOL</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLISTEOF
  GUI="gui/$(id -u)"
  launchctl bootout "$GUI/$LABEL" >/dev/null 2>&1
  launchctl unload "$PLIST" >/dev/null 2>&1
  if launchctl bootstrap "$GUI" "$PLIST" >/dev/null 2>&1 || launchctl load -w "$PLIST" >/dev/null 2>&1; then
    launchctl kickstart -k "$GUI/$LABEL" >/dev/null 2>&1
    say "• ★ menu bar app is running, and will start automatically at login."
  else
    say "• Couldn't auto-start the menu bar app; it'll come up at next login."
  fi
fi

hr
say "  Done."
say
say "  • Look for the ★ in your menu bar (if PyObjC was enabled)."
say "  • Drag the “Working Folders” folder into the Finder sidebar once"
say "    (under Favourites) — see the setup note above."
say "  • The drag-&-drop app is in ~/Applications; keep it in your Dock if you like."
say
say "  To remove everything later: run uninstall.command (it's in $SUPPORT)."
hr
printf '\nPress return to close.'; read -r _ || true
