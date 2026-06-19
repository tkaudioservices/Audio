# tkSurroundPanner — session workflow

How a show goes together, from an empty REAPER project to a render. No OSC, no Scan,
no Import/Export — the Live script syncs your tracks into the UI automatically.

## The shape of a session

```
tk SurroundPanner Bus      (folder track, N channels = speaker count)  ──► Master / hardware
   └─ JS: tk SurroundNoise   (optional — pink noise for Speaker check / rig setup)
├─ Object 1   JS: tk SurroundPanner   (2 in → N out)   ┐
├─ Object 2   JS: tk SurroundPanner                     │  all fold up into the bus
├─ Object 3   JS: tk SurroundPanner                     │  via the folder parent send
└─ …                                                    ┘
```

Every object track runs its own **tk SurroundPanner** and folds up into one **bus** (a
REAPER folder track). That bus is your immersive master: monitor it, and at render
time render the bus (or the master) and the whole mix comes with it. You don't have to
set the channel counts by hand — the Live script grows each object track and the bus to
the speaker count for you.

## 0 · Install (once, and after updates)

Double‑click `Install tkSurroundPanner.command` (macOS) or `.bat` (Windows). It copies
`tk_SurroundPanner.jsfx` and `tk_SurroundNoise.jsfx` into REAPER's `Effects/tk` and prints the
version. Re‑run it whenever you pull an update.

## 1 · Build the session

One object = one track:

1. Add a track and **name it** — that name is what you'll see in the UI.
2. Insert **JS: tk SurroundPanner** (FX browser → tk).
3. Drop the track into your surround **bus** (a folder track), so everything folds into
   one bus for monitoring and render.

Repeat per object. Group related objects in folders — the UI shows those folders as
groups you can show/hide together. You keep full control of the track layout; there's
no setup script.

## 2 · Start the live link

1. Actions → Show action list → Load ReaScript… → pick this repo's
   `engine/SurroundPanner_Live.lua`. Run it once and **leave it running** (running the
   action again stops it; the toolbar button shows on/off).
2. Double‑click `Launch SurroundPanner.command` — it starts the bridge and opens the UI
   at <http://localhost:9000/>. The header shows **bridge online** once connected.

Your tracks load automatically as objects, named and coloured from REAPER and grouped
by folder. If nothing appears, check that the Live action is running and the FX name
matches (it must contain "tk SurroundPanner").

## 3 · Set the room

Open **Room & speakers**. Pick a preset (Stereo / 5.1 / 7.1 / 7.1.4) as a start, then
fine‑tune: toggle **Edit room** to drag speakers on the canvas, or edit X/Y/Z and the
LFE flag per speaker in the list. Add/remove speakers for any custom shape.

The room pushes to the plug‑in live, and the Live script grows your tracks and bus to
match the speaker count. Coordinates are normalised: X −1…+1 (L→R), Y −1…+1
(rear→front), Z 0…1 (floor→ceiling).

**Lining up the rig?** Add **JS: tk SurroundNoise** to your bus. On the plug‑in: flip **Test
noise** on, dial **Speaker channel** (0 = all), set **Level (dB)**, and press play — pink noise
goes to that output and the web **Output meters** confirm it. Great for checking every speaker
is wired to the channel you think it is. Flip **Test noise** off to silence.

## 4 · Mix

Drag objects in the top view (X/Y) and front view (X/Z); moves stream to REAPER live
and the latch lines show which speakers each object is feeding. Per object you can set
**Gain**, an **LFE send** (a low‑passed feed to the sub), and a movement **Effect** (Orbit /
Oscillate / Spread / Drift — runs in the plug‑in, so it renders); globally, **Panner law** sets
**Focus** (how tightly each object localises) and **Spread** (how wide its field is), both
`0–100 %` and sent to every object's plug‑in. The latch‑line links and thicknesses follow them.

Watch **Output meters** (or the plug‑in's own display) to see the level on each
speaker. Tick **Follow** to mirror REAPER's own moves back into the UI (it polls the
live scene; no OSC needed). Use **Test · sweep X param** on a selected object to confirm
the link end‑to‑end.

## 5 · Render

Render the **bus** (or the master) — File → Render, output channels = your speaker
count. Because every object folds into the bus, the full immersive mix renders in one
pass. (A binaural headphone render is on the roadmap — see `README.md`.)

## Not working? Quick checklist

- **No objects / "no session"** — the Live action isn't running, or no track has the
  plug‑in. Run `SurroundPanner_Live.lua` and add **JS: tk SurroundPanner** to a track.
- **Header not "bridge online"** — the bridge isn't running or the browser can't reach
  it. Re‑launch, and confirm the UI's Bridge URL is `http://localhost:9000`.
- **Objects move on screen but not in REAPER** — re‑run the Live action; make sure the
  FX is the **tk** one (not ReaSurroundPan). Use **Test · sweep X param** to probe.
- **Only L/R show on the meters** — meters read the panner directly, so this means the
  object really is panning near the L/R pair, *or* you're on an old build; re‑install
  and confirm the version. (The bus routing no longer affects the meters.)
- **"Track only has 2 channels"** — the Live script widens tracks and the bus
  automatically; if you just added a track, give it a second or re‑run the action.
- **Live errors** — the script logs to `…/REAPER/tkSurroundPanner/live_error.log`
  instead of the console.
