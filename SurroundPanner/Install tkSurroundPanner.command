#!/bin/bash
# tkSurroundPanner — installer (macOS)
# Run this once, and again after an update, to copy the panner into REAPER.

cd "$(dirname "$0")" || exit 1
clear
echo "──────────────────────────────────────────────"
echo "  tkSurroundPanner — installer"
echo "──────────────────────────────────────────────"

RES="$HOME/Library/Application Support/REAPER"
if [ ! -d "$RES" ]; then
  echo "  REAPER resource folder not found at:"
  echo "    $RES"
  echo
  echo "  In REAPER: Options → Show REAPER resource path to find it, then copy"
  echo "  engine/tk_SurroundPanner.jsfx and engine/tk_SurroundNoise.jsfx into its Effects folder by hand."
  echo
  read -n 1 -s -r -p "  Press any key to close."
  exit 1
fi

mkdir -p "$RES/Effects/tk"
if cp engine/tk_SurroundPanner.jsfx engine/tk_SurroundNoise.jsfx "$RES/Effects/tk/"; then
  echo "  ✓ Installed  JS: tk SurroundPanner + tk SurroundNoise  (v0.13.0)  →  Effects/tk/"
  echo
  echo "  In REAPER:"
  echo "   • Add  JS: tk SurroundPanner  (FX browser → tk) to each object track."
  echo "   • Add  JS: tk SurroundNoise  to your immersive bus (optional — for Speaker check)."
  echo "   • Actions → Show action list → New action → Load ReaScript… → pick this repo's"
  echo "     engine/SurroundPanner_Live.lua  and run it once (leave it running)."
  echo "   • Then use  Launch SurroundPanner.command  for the bridge + UI."
  echo
  echo "  Updating an open project? Re-add the FX (or restart REAPER) to refresh it."
else
  echo "  ✗ Couldn't copy the JSFX — check folder permissions."
fi
echo
read -n 1 -s -r -p "  Press any key to close."
