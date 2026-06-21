#!/bin/bash
# Working Folders — one-click access to the folders you're working on right now.
# Created by tk Audio Services.
#
# The idea: keep a small "shelf" folder (default: ~/Working Folders) that you
# pin to the Finder sidebar ONCE. Add a project to the shelf and it shows up
# there as a Finder alias — double-click to jump straight in, no digging
# through the Dropbox hierarchy. Take it off the shelf when the job's done.
#
# Why this instead of Finder tags: tags live in file metadata that Dropbox
# doesn't sync reliably, so coloured tags come and go. This uses no tags and
# no metadata — just a normal folder of aliases that lives on your Mac (not in
# Dropbox), pointing into wherever your work actually is.
#
# Usage:
#   ./working-folders.sh                  # interactive menu (same as double-click)
#   ./working-folders.sh add-current      # pin the folder shown in the front Finder window
#   ./working-folders.sh add <folder>...  # pin one or more folders by path
#   ./working-folders.sh list             # list what's on the shelf
#   ./working-folders.sh remove           # take something off the shelf (interactive)
#   ./working-folders.sh open             # open the shelf in Finder
#   ./working-folders.sh setup            # create the shelf + pin it to the sidebar
#   ./working-folders.sh build-app        # build the drag-&-drop app
#
# Change where the shelf lives:  export WORKING_FOLDERS_HUB="$HOME/.../Shelf"

# (Deliberately no 'set -u': this is an interactive menu tool, and a single
# unset variable should never hard-crash it. Important vars use :- defaults.)

HUB="${WORKING_FOLDERS_HUB:-$HOME/Working Folders}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Add to Working Folders"

# Which built-in Apple icon to use (an SF Symbol name — line art, rendered on
# your Mac so nothing proprietary is shipped). Try others: folder, star.fill,
# tray.full, pin, bookmark, folder.badge.gearshape.  Override per-run with
# WORKING_FOLDERS_SYMBOL=folder ./working-folders.sh setup
ICON_SYMBOL="${WORKING_FOLDERS_SYMBOL:-star}"

if [ "$(uname)" != "Darwin" ]; then
  echo "Working Folders is macOS-only — it talks to Finder via AppleScript." >&2
  exit 1
fi

# ---------------------------------------------------------------- helpers ---
say()   { printf '%s\n' "$*"; }
die()   { printf 'Error: %s\n' "$*" >&2; exit 1; }
pause() { printf '\nPress return to continue… '; read -r _ || true; }

ensure_hub() { mkdir -p "$HUB" || die "couldn't create the shelf at: $HUB"; }

# The classic custom-folder-icon file is literally named "Icon" + carriage
# return; it lives in the shelf but is not a project, so we never list it.
ICONFILE=$'Icon\r'

# List the real shelf entries (skips dotfiles and the Icon file). Extra args
# are passed through to find (e.g. -exec).
shelf_find() {
  find "$HUB" -mindepth 1 -maxdepth 1 ! -name '.*' ! -name "$ICONFILE" "$@" 2>/dev/null
}

count_items() {
  local n
  n="$(shelf_find | wc -l | tr -d ' ')"
  printf '%s' "${n:-0}"
}

# Create a Finder alias to "$1" inside the shelf. Skips duplicates by name.
make_alias() {
  local target="$1"
  if [ ! -e "$target" ]; then
    say "  • skipped (not found): $target"
    return 1
  fi
  ensure_hub
  local result
  result="$(/usr/bin/osascript - "$target" "$HUB" <<'OSA' 2>/dev/null
on run argv
    set targetPosix to item 1 of argv
    set hubPosix to item 2 of argv
    tell application "Finder"
        set tgt to (POSIX file targetPosix) as alias
        set hubFolder to (POSIX file hubPosix) as alias
        set tgtName to name of tgt
        try
            if (exists item tgtName of hubFolder) then return "exists"
        end try
        make new alias file at hubFolder to tgt
        return "ok"
    end tell
end run
OSA
)"
  case "$result" in
    ok)     say "  • added: $(basename "$target")" ;;
    exists) say "  • already on the shelf: $(basename "$target")" ;;
    *)      say "  • couldn't add (is Finder running?): $(basename "$target")" ;;
  esac
}

# POSIX path of the folder shown in the frontmost Finder window ("" if none).
front_finder_path() {
  /usr/bin/osascript <<'OSA' 2>/dev/null
tell application "Finder"
    if (count of Finder windows) is 0 then return ""
    try
        set t to target of front Finder window
        return POSIX path of (t as alias)
    on error
        return ""
    end try
end tell
OSA
}

# Build an .icns from a PNG using macOS built-ins.  $1=source png  $2=dest icns
make_icns() {
  command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 || return 1
  local src="$1" out="$2" work iconset s rc
  work="$(mktemp -d)"; iconset="$work/icon.iconset"; mkdir -p "$iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$src" --out "$iconset/icon_${s}x${s}.png" >/dev/null 2>&1
    sips -z "$((s * 2))" "$((s * 2))" "$src" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$iconset" -o "$out" >/dev/null 2>&1; rc=$?
  rm -rf "$work"
  return $rc
}

# Render a built-in Apple SF Symbol (line art) and either set it as a folder's
# icon or write it to a PNG. Done with the macOS system Python + Cocoa, so no
# Apple artwork is shipped — the current system symbol is drawn on this Mac.
# Best-effort: returns non-zero (changing nothing) on anything older/missing.
#   render_symbol folder <symbol> <px> <folder-path>
#   render_symbol png    <symbol> <px> <out.png>
render_symbol() {
  /usr/bin/python3 - "$1" "$2" "$3" "$4" >/dev/null 2>&1 <<'PY'
import sys
mode, symbol, size, dest = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    from AppKit import (NSImage, NSWorkspace, NSColor, NSColorSpace, NSBezierPath,
                        NSImageSymbolConfiguration, NSBitmapImageRep, NSGraphicsContext)
    from Foundation import NSMakeRect, NSZeroRect
except Exception:
    sys.exit(3)  # PyObjC / AppKit not available

# the system line-art symbol (macOS 11+); None if the OS is older or the name is unknown
base = NSImage.imageWithSystemSymbolName_accessibilityDescription_(symbol, None)
if base is None:
    sys.exit(2)
cfg = NSImageSymbolConfiguration.configurationWithPointSize_weight_scale_(200.0, 0.0, 3)
sym = base.imageWithSymbolConfiguration_(cfg) or base

# tint to the system accent colour so it stays visible in light AND dark sidebars
try:
    col = NSColor.controlAccentColor().colorUsingColorSpace_(NSColorSpace.sRGBColorSpace())
    if col is None:
        raise ValueError
except Exception:
    col = NSColor.colorWithSRGBRed_green_blue_alpha_(10/255.0, 132/255.0, 255/255.0, 1.0)

canvas = NSImage.alloc().initWithSize_((size, size))
canvas.lockFocus()
s = sym.size()
if s.width <= 0 or s.height <= 0:
    canvas.unlockFocus(); sys.exit(2)
box = size * 0.62
scale = box / (s.width if s.width >= s.height else s.height)
dw, dh = s.width * scale, s.height * scale
sym.drawInRect_fromRect_operation_fraction_(
    NSMakeRect((size - dw) / 2.0, (size - dh) / 2.0, dw, dh), NSZeroRect, 2, 1.0)  # 2 = sourceOver
NSGraphicsContext.currentContext().setCompositingOperation_(5)  # 5 = sourceAtop -> recolour the glyph
col.set()
NSBezierPath.bezierPathWithRect_(NSMakeRect(0, 0, size, size)).fill()
canvas.unlockFocus()

if mode == "folder":
    sys.exit(0 if NSWorkspace.sharedWorkspace().setIcon_forFile_options_(canvas, dest, 0) else 1)
rep = NSBitmapImageRep.imageRepWithData_(canvas.TIFFRepresentation())
data = rep.representationUsingType_properties_(4, {})  # 4 = PNG
sys.exit(0 if data and data.writeToFile_atomically_(dest, True) else 1)
PY
}

# ----------------------------------------------------------------- actions --
cmd_add_current() {
  local p
  p="$(front_finder_path)"
  if [ -z "$p" ]; then
    say "Couldn't read a front Finder window."
    say "Open a Finder window, go INTO the folder you want to pin, then try again."
    return 1
  fi
  say "Pinning the folder you're looking at:"
  say "  $p"
  make_alias "$p"
}

cmd_add() {
  [ "$#" -gt 0 ] || die "usage: add <folder>…"
  local p
  for p in "$@"; do make_alias "$p"; done
}

cmd_list() {
  ensure_hub
  if [ "$(count_items)" -eq 0 ]; then
    say "Your shelf is empty:  $HUB"
    return
  fi
  say "On your shelf  ($HUB):"
  shelf_find -exec basename {} \; | sort | sed 's/^/  • /'
}

cmd_remove() {
  ensure_hub
  local items=() it
  while IFS= read -r it; do items+=("$it"); done < <(shelf_find | sort)
  if [ "${#items[@]}" -eq 0 ]; then
    say "Nothing on the shelf to remove."
    return
  fi
  say "Take which folder off the shelf?"
  local i=1
  for it in "${items[@]}"; do
    printf '  %d) %s\n' "$i" "$(basename "$it")"
    i=$((i + 1))
  done
  printf 'Number (or return to cancel): '
  local choice; read -r choice || true
  [ -z "$choice" ] && { say "Cancelled."; return; }
  case "$choice" in *[!0-9]*) say "That's not a number."; return ;; esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#items[@]}" ]; then
    say "Out of range."
    return
  fi
  local victim="${items[$((choice - 1))]}"
  # Removing an alias only deletes the shortcut — the real folder is untouched.
  rm -f "$victim" && say "Off the shelf: $(basename "$victim")  (the real folder is untouched)"
}

cmd_open() {
  ensure_hub
  open "$HUB"
}

cmd_setup() {
  ensure_hub
  say "Created your shelf:  $HUB"
  if render_symbol folder "$ICON_SYMBOL" 512 "$HUB"; then
    say "Gave the shelf the system '$ICON_SYMBOL' line-art icon so it stands out."
  else
    say "(Couldn't auto-apply the icon on this Mac — see 'Set the icon by hand'"
    say " in the README if you'd like one. The shelf still works fine without.)"
  fi
  say
  local pinned=""
  if command -v mysides >/dev/null 2>&1; then
    local url="file://$(printf '%s' "$HUB" | sed 's/ /%20/g')/"
    mysides remove "Working Folders" >/dev/null 2>&1   # avoid a stale duplicate
    mysides add "Working Folders" "$url" >/dev/null 2>&1
    killall Finder >/dev/null 2>&1                      # refresh the sidebar now
    mysides list 2>/dev/null | grep -qi "Working Folders" && pinned="yes"
  fi
  if [ "$pinned" = "yes" ]; then
    say "Pinned 'Working Folders' to your Finder sidebar (Favourites). ✓"
    say "Don't see it? Hover next to the word 'Favourites' in the sidebar and"
    say "click 'Show' — macOS sometimes collapses that whole section."
  else
    say "One-time step — pin the shelf to your sidebar (takes 3 seconds):"
    say "  1) A Finder window has opened with 'Working Folders' highlighted."
    say "  2) Drag it into the sidebar, under 'Favourites'."
    say "     (No 'Favourites' showing? Hover there and click 'Show'.)"
    command -v mysides >/dev/null 2>&1 \
      || say "  (Or: 'brew install --cask mysides', then re-run setup, to automate it.)"
  fi
  open -R "$HUB" 2>/dev/null || open "$HOME"
}

cmd_build_app() {
  command -v osacompile >/dev/null 2>&1 || die "osacompile not found (it ships with macOS)."
  [ -f "$SCRIPT_DIR/droplet.applescript" ] || die "droplet.applescript isn't next to this script."
  local outdir="$HOME/Applications"
  mkdir -p "$outdir"
  local app="$outdir/$APP_NAME.app"
  rm -rf "$app"
  if osacompile -o "$app" "$SCRIPT_DIR/droplet.applescript" 2>/dev/null; then
    say "Built the app:  $app"
    local iconpng; iconpng="$(mktemp -d)/icon.png"
    if render_symbol png "$ICON_SYMBOL" 1024 "$iconpng" \
       && make_icns "$iconpng" "$app/Contents/Resources/applet.icns"; then
      touch "$app"
      say "Gave it the system '$ICON_SYMBOL' line-art icon."
    fi
    rm -rf "$(dirname "$iconpng")"
    say
    say "Now you can DRAG any folder onto it to pin that folder to your shelf."
    say "Keep it in your Dock, or drag it onto a Finder window's toolbar, so a"
    say "folder is one drag away from the shelf."
    open -R "$app" 2>/dev/null || true
  else
    die "build failed."
  fi
}

cmd_doctor() {
  local AG="com.tkaudioservices.workingfolders.menubar"
  local app="$HOME/Applications/$APP_NAME.app"
  say "Working Folders — doctor"
  say "────────────────────────"
  say "macOS:          $(sw_vers -productVersion 2>/dev/null || echo '?')"
  say "shelf:          $HUB  ($(count_items) item(s))"
  say "shelf icon:     $([ -e "$HUB/$ICONFILE" ] && echo 'set' || echo 'none')"
  say "drag-drop app:  $([ -d "$app" ] && echo 'present' || echo 'MISSING')"
  local line; line="$(launchctl list 2>/dev/null | grep "$AG")"
  if [ -n "$line" ]; then
    say "menu bar agent: loaded (pid $(printf '%s' "$line" | awk '{print $1}'), last exit $(printf '%s' "$line" | awk '{print $2}'))"
  else
    say "menu bar agent: not loaded"
  fi
  say "PyObjC:         $(/usr/bin/python3 -c 'import AppKit' >/dev/null 2>&1 && echo 'OK' || echo 'missing')"
  if command -v mysides >/dev/null 2>&1; then
    say "mysides:        yes"
    say "pinned to bar:  $(mysides list 2>/dev/null | grep -qi 'Working Folders' && echo 'yes' || echo 'no')"
  else
    say "mysides:        no  (needed to auto-pin the sidebar)"
  fi
  say "Homebrew:       $(command -v brew >/dev/null 2>&1 && echo 'yes' || echo 'no')"
}

show_help() {
  cat <<'TXT'
Working Folders — what it is
----------------------------
A "shelf" folder you pin to the Finder sidebar once. Put the projects you're
actively working on onto the shelf and they're one click away — double-click an
item to jump straight into that folder, wherever it lives in Dropbox.

It uses Finder ALIASES (shortcuts), not tags. Tags rely on metadata Dropbox
doesn't sync well, which is why coloured tags keep dropping. Aliases don't have
that problem, and the shelf itself lives on your Mac (not inside Dropbox), so
Dropbox never gets to mangle it.

Day to day
----------
  • Add what you're on: open the folder in Finder, then "Add the folder I'm
    looking at" (or drag it onto the drag-&-drop app).
  • Jump to it: click "Working Folders" in the Finder sidebar, double-click.
  • Done with it: "Remove a folder from the shelf" — deletes only the shortcut,
    never the real folder or its files.

Nothing here ever moves, renames or deletes your actual project folders.
TXT
}

cmd_menu() {
  while true; do
    clear 2>/dev/null || true
    say "══════════════════════════════════════════════════"
    say "  Working Folders — quick Finder access"
    say "  by tk Audio Services"
    say "══════════════════════════════════════════════════"
    say "  Shelf:  $HUB"
    say "  On the shelf:  $(count_items) folder(s)"
    say
    say "  1) Add the folder I'm looking at in Finder right now"
    say "  2) Open my Working Folders shelf"
    say "  3) List what's on the shelf"
    say "  4) Take a folder off the shelf"
    say "  5) First-time setup (create shelf + pin to the sidebar)"
    say "  6) Build the drag-&-drop app ('$APP_NAME')"
    say "  d) Check everything is working (doctor)"
    say "  h) Help / what is this"
    say "  q) Quit"
    say
    printf 'Choose: '
    local c; read -r c || break
    case "$c" in
      1) cmd_add_current; pause ;;
      2) cmd_open ;;
      3) cmd_list; pause ;;
      4) cmd_remove; pause ;;
      5) cmd_setup; pause ;;
      6) cmd_build_app; pause ;;
      d | D) cmd_doctor; pause ;;
      h | H | "help") show_help; pause ;;
      q | Q | "") say "Bye."; break ;;
      *) ;;
    esac
  done
}

# ------------------------------------------------------------------- main ---
main() {
  local cmd="${1:-menu}"
  [ "$#" -gt 0 ] && shift
  case "$cmd" in
    menu)           cmd_menu ;;
    add)            cmd_add "$@" ;;
    add-current)    cmd_add_current ;;
    list)           cmd_list ;;
    remove)         cmd_remove ;;
    open)           cmd_open ;;
    setup)          cmd_setup ;;
    build-app)      cmd_build_app ;;
    doctor)         cmd_doctor ;;
    help | -h | --help) show_help ;;
    *) die "unknown command: $cmd  (try: menu, add-current, add, list, remove, open, setup, build-app, doctor)" ;;
  esac
}

main "$@"
