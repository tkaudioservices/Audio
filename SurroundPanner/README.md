# tkSurroundPanner

A web front‑end for designing and driving **immersive object‑based shows in REAPER**.

Your REAPER tracks appear as objects. Drag them around a top‑down (X/Y) and front
(X/Z) view and watch lines light up to the speakers each object is feeding
(brightness = gain). A small ReaScript running inside REAPER applies the moves to
each track's **tk SurroundPanner** plug‑in in real time — and the same panning law
runs in the browser, so what you see on screen is what you hear.

Think of it as a lightweight, open take on the object/room workflow you get in tools
like L‑ISA Studio or KLANG — but talking to a REAPER session you already own.

> Part of the **tk Audio Services** [Audio](../) repo. Like the rest of it, the
> bridge is **standard‑library Python only** — no `pip install`, no build step — and
> the panner is a single JSFX file. Nothing to compile.

See **[WORKFLOW.md](WORKFLOW.md)** for the full empty‑project‑to‑render walkthrough,
and **[CHANGELOG.md](CHANGELOG.md)** for what changed when.

---

## What's in here

| File | What it is |
|---|---|
| `index.html` | The control surface. Open it in any browser — it works standalone for design even with no REAPER or bridge running. |
| `engine/tk_SurroundPanner.jsfx` | **The panner.** A DBAP object panner (2 in → up to 16 out) whose sliders we drive directly, so external control is reliable. It reads the speaker layout live from REAPER shared memory, has a per‑object LFE send, and shows a compact value readout. Installed into REAPER's `Effects/tk`. |
| `engine/tk_SurroundNoise.jsfx` | **Rig‑setup noise.** A pink‑noise generator for your immersive bus. The UI's *Speaker check* drives it to send noise to one speaker (or all), so you can line up, level‑match and verify the real rig. Publishes into the same meters as the panner. Installed alongside the panner. |
| `engine/SurroundPanner_Live.lua` | **The live link.** Run once inside REAPER and leave it running. It drives every `tk SurroundPanner` instance from the UI, pushes the room layout into shared memory, auto‑grows track/bus channel counts, and publishes the scene + meters back to the UI. |
| `bridge/reaper_bridge.py` | Tiny stdlib HTTP bridge. Serves the UI and shuttles small JSON files between the browser and the Live script. No OSC, no extensions. |
| `Install tkSurroundPanner.command` / `.bat` | Double‑click installer — copies the JSFX into REAPER's `Effects/tk`. Run once, and again after an update. |
| `Launch SurroundPanner.command` / `.bat` | Double‑click launchers (macOS / Windows) that start the bridge and open the UI. |
| `assets/` | Logo and favicon. |

Why our own JSFX instead of `ReaSurroundPan`? ReaSurroundPan ignores parameter writes
from outside until its puck is touched by hand, which makes remote control unreliable.
Our plug‑in has ordinary sliders that accept writes instantly — and it lets us own the
room shape, the panning law, metering, and (later) binaural rendering.

---

## Quick start

1. **Install** — double‑click `Install tkSurroundPanner.command`. It copies the JSFX
   into REAPER's `Effects/tk`. (Re‑run it after every update; the installer prints the
   version so you can confirm.)
2. **In REAPER:**
   - Add **JS: tk SurroundPanner** (FX browser → tk) to each object track.
   - Actions → Load ReaScript → pick this repo's `engine/SurroundPanner_Live.lua`,
     run it once, and leave it running. (Running the action again stops it; the
     toolbar button reflects on/off.)
3. **Launch** — double‑click `Launch SurroundPanner.command`. It starts the bridge and
   opens the UI. Your tracks appear as objects, grouped by their REAPER folders;
   dragging them moves REAPER live.

Drag the numbered circles in the **top** view (X = left/right, Y = front/rear) and the
**front** view (X = left/right, Z = height). No OSC device, no preferences to change,
no Import/Export.

After an update: re‑run the installer, then re‑add the FX (or restart REAPER) to
refresh an instance in an already‑open project, and re‑run the Live action.

---

## How it fits together

```
  Browser (index.html)
        │  HTTP  (localhost:9000)
        ▼
  reaper_bridge.py  ──writes──►  cmds.json   ──►  SurroundPanner_Live.lua  ──►  tk SurroundPanner JSFX
        ▲                        room.json                 (in REAPER)              (sliders + gmem)
        └──────reads────────────  session.json  ◄──┘  publishes scene
                                   levels.json   ◄──┘  publishes meters
```

The browser never talks to REAPER directly. It POSTs object moves and the room layout
to the bridge, which drops them into small JSON files in REAPER's resource folder
(`…/REAPER/tkSurroundPanner/`). The Live script, deferring ~30×/sec inside REAPER,
reads those files and applies them, and writes the current scene and live meter levels
back out for the UI to poll. Every file write is atomic, so neither side ever reads a
half‑written file. Because the link is file‑based, the Live script can run from
anywhere and there are no ports to match.

---

## The panner law

Every object feeds every speaker, weighted by distance, using **DBAP** (distance‑based
amplitude panning):

```
gain_i = 1 / (distance_i + blur) ^ rolloff      then constant‑power normalised
```

- **Focus** (`0–100 %`) — how tightly each object localises onto its nearest speakers
  (maps to the DBAP rolloff exponent, `0.5…4`). Higher = tighter.
- **Spread** (`0–100 %`) — how wide the object's field is (maps to the DBAP blur, `0.01…0.6`).
  Higher spreads it across more speakers. Both Focus and Spread drive the latch‑line links and
  thicknesses, so the picture follows the sound. Very faint links auto‑hide for readability.

The identical law runs in two places: in the browser to draw the latch lines, and in
the JSFX to do the actual audio. Focus and Spread changes in the UI are sent to every
object's plug‑in, so the on‑screen prediction and the sound stay in lock‑step — what
you see is what you hear, provided the room here matches your REAPER speaker layout
(which it does, since the UI pushes the layout to the plug‑in).

---

## Rooms & speaker layouts

The room takes **fully custom speaker placement**. Pick a preset as a starting point —
**Stereo, 5.1, 7.1, 7.1.4 (Atmos)** — then in *Edit room* mode drag speakers on the
canvas, or edit each speaker's X/Y/Z and LFE flag in the list. Add or remove speakers
freely; any count and shape works.

**Coverage shapes.** Each speaker can be given an elliptical **footprint** (Cover W / Cover D /
Angle) marking the area it actually feeds — e.g. a ceiling speaker's downward spot, or a wide
front fill. The panner weights each speaker's DBAP gain by how far the object sits inside that
speaker's ellipse, so objects only get signal from speakers that cover them — sharper, more
realistic panning. Coverage is **off by default** (0 = covers everywhere). The ellipses draw on
the top view and the latch lines follow the weighting, in the browser and the plug‑in alike.

Coordinates are normalised: `X` −1…+1 (left→right), `Y` −1…+1 (rear→front), `Z` 0…1
(floor→ceiling). Presets follow REAPER's channel order, including the LFE gap.

Whenever the room changes, the UI pushes it to the plug‑in live (browser → bridge →
`room.json` → Live → shared memory → JSFX), and the Live script grows each object
track **and its folder bus** to at least the speaker count so you never hit the
"track only has 2 channels" trap.

**Objects come from REAPER, not the page.** Each track running the panner is one
object and its name is the track name; you don't create objects in the UI. Renaming,
recolouring or regrouping a track updates the UI automatically, and adding/removing a
track refreshes the object list.

**LFE** is non‑positional: a speaker flagged LFE is excluded from the distance panning (it
draws no latch line). Instead, each object has an **LFE send** — a low‑passed (~120 Hz) mono
feed routed to the room's LFE channel(s) — so you can place bass energy into the sub without it
smearing the positional image.

---

## Output meters

Two views of the same signal, one bar per speaker:

- **In the web UI** — the *Output meters* panel, labelled from the room.
- **In the plug‑in** — the panner shows a compact live X/Y/Z/LFE + Gain/Focus/Spread
  readout, so you can confirm at a glance it's receiving the UI's values.

Both read the panner's per‑output peak straight from shared memory, so they match each
other and don't depend on how the bus is routed. Press play in REAPER to see them move.

---

## Speaker check (rig setup)

Add **JS: tk SurroundNoise** to your immersive bus — all its controls live on the plug‑in: flip
**Test noise** on, pick a **Speaker channel** (0 = all), and set the **Level (dB)**. It injects
pink noise into that output for lining up, level‑matching and verifying a real rig during system
setup. It publishes to the shared meters, so the web UI's **Output meters** confirm what's
playing. Press play in REAPER so the bus processes audio; flip **Test noise** off to silence it.

It's a single source on the bus (independent of how many object tracks you have), so the rig
check is predictable no matter what the show looks like.

---

## Versioning

`MAJOR.MINOR.PATCH`, kept **inside the files** (not in filenames — REAPER references
plug‑ins and scripts by path, so renaming them would break projects). The version
shows in the web UI header, the JSFX name, the Live script and bridge headers, and the
installer's confirmation line. See [CHANGELOG.md](CHANGELOG.md).

---

## Technical reference

**Shared JSON files** (in `…/REAPER/tkSurroundPanner/`, override with `--ipc-dir`):

| File | Direction | Contents |
|---|---|---|
| `cmds.json` | UI → REAPER | `{"seq":N,"params":[{"t","f","p","v"}, …]}` — latest value per (track, fx, param). |
| `room.json` | UI → REAPER | `{"speakers":[{"x","y","z","lfe","cw","cd","ca"}, …]}` — layout + per‑speaker coverage ellipse (`cw`/`cd` half‑axes, `ca` angle°; 0 = off). |
| `session.json` | REAPER → UI | Objects (name, colour, group, x/y/z, param tags) + track list. |
| `levels.json` | REAPER → UI | `{"levels":[…]}` — per‑speaker peak, ~12×/sec. |

**Param tags** (the `p` in `cmds.json`) → JSFX slider:

| Tag | Meaning | JSFX param (0‑based) | Scope |
|---|---|---|---|
| 4 | X (UI sends `(1−x)/2`) | 0 | per object |
| 5 | Y (UI sends `(y+1)/2`) | 1 | per object |
| 6 | Z (`0…1`) | 2 | per object |
| 7 | Gain (`0…1`) | 3 | per object |
| 8 | Focus → rolloff (`0.5…4`) | 4 | panner law (all objects) |
| 9 | Spread → blur (`0.01…0.6`) | 5 | panner law (all objects) |
| 10 | LFE send (`0…1`) | 6 | per object |

**Shared memory** (`gmem` namespace `tkSurroundPanner`):

- `gmem[0]` = speaker count; then per speaker `i` a 7‑wide block at `gmem[1 + i*7 ..]`:
  `x`, `y`, `z`, `lfe`, `cw`, `cd`, `ca` (coverage half‑axes + angle°). The count is written
  last, so the JSFX never reads a partial layout (it falls back to a built‑in 7.1.4 if none is set).
- `gmem[1000 + ch]` = per‑output peak. Each JSFX instance (panner **and** `tk SurroundNoise`)
  maxes its level in; the Live script reads and clears these for the meters. (The meter base sits
  at 1000 to stay clear of the layout block, which can reach ~112 at 16 speakers.)

**Bridge** — `python3 bridge/reaper_bridge.py [--port 9000] [--host 127.0.0.1] [--ipc-dir DIR]`.
Endpoints: `GET /ping`, `/session`, `/levels`, static files; `POST /set` (object moves),
`/room` (layout).

---

## Roadmap

- [x] Bidirectional link — UI ↔ REAPER (control out; **Follow** mirrors REAPER's moves back in).
- [x] Our own reliable panner engine (DBAP JSFX), driven live from the UI.
- [x] Objects are REAPER tracks; track colour + folder grouping sync automatically.
- [x] **Custom rooms** — any speaker count/shape, pushed to the plug‑in live.
- [x] **Output meters** — per speaker, in the UI and in the plug‑in.
- [x] **Panner law** (rolloff / spread) drives the engine, not just the view.
- [x] **Auto channel count** — tracks and the bus grow to the speaker count.
- [x] **Per‑object LFE send** — low‑passed mono feed per object to the room's LFE channel(s).
- [x] **Speaker coverage + pink noise** — ✅ per‑speaker pink‑noise solo (*Speaker check*, via
      `tk SurroundNoise` on the bus) and ✅ per‑speaker elliptical coverage footprints weighting
      the pan. (Future: union coverage across a group; couple it to object spread.)
- [ ] **Multi‑channel sources / effect engine** — spread a stereo (or N‑channel) source
      across the field with movement/FX (orbit, spread, centre‑of‑gravity), à la L‑ISA.
- [ ] **Binaural mixdown** — a headphone render path for offline work: an HRTF convolver
      in the JSFX for monitoring, and an offline renderer for deliverables.
- [ ] Position **automation** — record/playback object trajectories to REAPER envelopes.
- [ ] **Radial / spherical** room view (L‑ISA / KLANG style) alongside the X‑Y / X‑Z views.

---

## A note on safety

This drives a **live REAPER session**. It only sets the panner's own parameters and
grows track/bus channel counts — it won't change routing, arm tracks, or touch
transport. The one thing that makes sound on its own is **Speaker check**, and only when you
explicitly enable it and `tk SurroundNoise` is on the bus — mind the level, and it stops when
you hit **Off** or stop the Live script. Still, test on a scratch project before pointing it
at a show you care about.

---

## Licence

[MIT](../LICENSE) — part of the tk Audio Services *Audio* repo.
