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

set -u

HUB="${WORKING_FOLDERS_HUB:-$HOME/Working Folders}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Add to Working Folders"

if [ "$(uname)" != "Darwin" ]; then
  echo "Working Folders is macOS-only — it talks to Finder via AppleScript." >&2
  exit 1
fi

# ---------------------------------------------------------------- helpers ---
say()   { printf '%s\n' "$*"; }
die()   { printf 'Error: %s\n' "$*" >&2; exit 1; }
pause() { printf '\nPress return to continue… '; read -r _ || true; }

ensure_hub() { mkdir -p "$HUB" || die "couldn't create the shelf at: $HUB"; }

count_items() {
  local n
  n="$(find "$HUB" -mindepth 1 -maxdepth 1 ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
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

# Give a folder (or file) a custom icon, via the macOS system Python + Cocoa.
# Best-effort: returns non-zero (and changes nothing) if it can't.  $1=png $2=path
set_custom_icon() {
  [ -f "$1" ] || return 1
  /usr/bin/python3 - "$1" "$2" >/dev/null 2>&1 <<'PY'
import sys
try:
    from Cocoa import NSImage, NSWorkspace
except Exception:
    sys.exit(1)
img = NSImage.alloc().initWithContentsOfFile_(sys.argv[1])
if img is None:
    sys.exit(1)
sys.exit(0 if NSWorkspace.sharedWorkspace().setIcon_forFile_options_(img, sys.argv[2], 0) else 1)
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
  find "$HUB" -mindepth 1 -maxdepth 1 ! -name '.*' -exec basename {} \; | sort | sed 's/^/  • /'
}

cmd_remove() {
  ensure_hub
  local items=() it
  while IFS= read -r it; do items+=("$it"); done < <(find "$HUB" -mindepth 1 -maxdepth 1 ! -name '.*' | sort)
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
  if [ -f "$SCRIPT_DIR/assets/working-folders-folder.png" ] \
     && set_custom_icon "$SCRIPT_DIR/assets/working-folders-folder.png" "$HUB"; then
    say "Gave the shelf a ★ star icon so it stands out in the sidebar."
  fi
  say
  if command -v mysides >/dev/null 2>&1; then
    local url="file://$(printf '%s' "$HUB" | sed 's/ /%20/g')/"
    if mysides add "Working Folders" "$url" >/dev/null 2>&1; then
      say "Pinned it to your Finder sidebar (under Favourites) automatically. ✓"
    else
      say "Couldn't auto-pin — drag it into the sidebar by hand (steps below)."
    fi
  else
    say "Now pin it to the Finder sidebar so it's always one click away:"
    say "  1) A Finder window has opened with the shelf selected."
    say "  2) Drag the “Working Folders” folder into the sidebar, dropping it"
    say "     under “Favourites” (the section just above “Locations”)."
    say
    say "  Once it's there, clicking it shows every project you're working on."
    say
    say "  (Optional: 'brew install mysides' then re-run setup to auto-pin.)"
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
    if [ -f "$SCRIPT_DIR/assets/working-folders-app.png" ] \
       && make_icns "$SCRIPT_DIR/assets/working-folders-app.png" "$app/Contents/Resources/applet.icns"; then
      touch "$app"
      say "Gave it the gold-star icon. ★"
    fi
    say
    say "Now you can DRAG any folder onto it to pin that folder to your shelf."
    say "Keep it in your Dock, or drag it onto a Finder window's toolbar, so a"
    say "folder is one drag away from the shelf."
    open -R "$app" 2>/dev/null || true
  else
    die "build failed."
  fi
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
    say "  6) Build the drag-&-drop app (“$APP_NAME”)"
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
    help | -h | --help) show_help ;;
    *) die "unknown command: $cmd  (try: menu, add-current, add, list, remove, open, setup, build-app)" ;;
  esac
}

main "$@"
