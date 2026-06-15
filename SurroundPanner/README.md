# SurroundPanner

A web front-end for designing and driving **immersive object-based shows in REAPER**.

Define a room, drop sound objects into it, drag them around in a top‑down / front
view, and watch lines light up to the speakers each object is feeding (brightness =
gain). Moves stream live into REAPER over OSC, so a `ReaSurroundPan` (or any
OSC‑addressable panner) follows the object in real time.

Think of it as a lightweight, open take on the kind of object/room workflow you get
in tools like L‑ISA Studio — but talking to a REAPER session you already own.

> Part of the **tk Audio Services** [Audio](../) repo. Like the rest of it, the
> bridge is **standard‑library Python only** — no `pip install`, no build step.

---

## What's in here

| File | What it is |
|---|---|
| `index.html` | The control surface. Open it in any browser — it works standalone for design even with no bridge running. |
| `bridge/reaper_bridge.py` | A tiny HTTP→OSC bridge. Serves the UI and relays object positions to REAPER over OSC/UDP. |
| `Launch SurroundPanner.command` / `.bat` | Double‑click launchers (macOS / Windows) that start the bridge and open the UI. |

---

## Quick start

1. **Start the bridge** — double‑click the launcher, or from a terminal:
   ```bash
   python3 bridge/reaper_bridge.py
   ```
   It prints a banner and serves the UI at <http://localhost:9000/>.

2. **Open the UI** at <http://localhost:9000/> (the launcher does this for you).

3. **Point REAPER at the bridge** (one‑time setup, below), then click
   **Connect / test** in the UI's *REAPER connection* panel. The dot turns green.

4. **Move objects.** Drag the numbered circles in the top view (X = left/right,
   Y = front/rear) and the front view (X = left/right, Z = height). Positions
   stream to REAPER.

You can also just open `index.html` directly (double‑click / `file://`) and use it
purely as a design tool — the bridge is only needed for the live link to REAPER.

---

## REAPER setup (one time)

**Add an OSC device:**
`Preferences → Control/OSC/web → Add → OSC (Open Sound Control)`

- **Mode:** *Configure device IP + local port*
- **Local listen port:** `8000` &nbsp;← must match the bridge's `--reaper-port`
- Tick **Allow binding messages to REAPER actions and FX learn**

**Per object track:** add the panner you want to drive (e.g. `VST: ReaSurroundPan`),
then in the UI's *Objects* panel set that object's **Track**, **FX** and **param**
numbers.

**Finding the parameter indices:** open the FX, click the **UI** button at the top
of the plug‑in window to switch to REAPER's generic view. Parameters are then listed
top‑to‑bottom — the index (counting from 0) is what goes in the *X / Y / Z param*
fields. For `ReaSurroundPan` the per‑input X/Y/Z controls are what you want to map.

The UI sends normalised `0.0–1.0` values to:
```
/track/<track>/fx/<fx>/fxparam/<param>/value
```

---

## How the panning / latch lines work

Every object feeds every speaker, weighted by distance using **DBAP**
(distance‑based amplitude panning):

```
gain_i = 1 / (distance_i + blur) ^ rolloff      then constant‑power normalised
```

- **Rolloff** — how sharply gain falls with distance (higher = tighter, more
  localised).
- **Spread / blur** — softens the field so objects don't collapse to a single
  speaker; raise it to spread across more speakers.
- **Line cut** — hides lines below a gain threshold to keep the view readable.

This math runs in the browser purely for the **visualisation** — it predicts which
speakers an object latches to and how hard. REAPER's panner does the actual audio.
Because the law lives in the UI, SurroundPanner isn't locked to `ReaSurroundPan`; it
can drive anything that accepts OSC.

> Note: the prediction and REAPER's internal panner agree best when the room here
> matches your REAPER channel/speaker layout. The lines are a guide, not a meter.

---

## Speaker layouts

The room takes **fully custom speaker placement** — drag speakers in *Edit room*
mode, or click empty space in the top view to add one, and edit X/Y/Z and output
channel per speaker. Presets are provided as starting points: stereo, quad, 5.1,
7.1, 7.1.4 (Atmos), and an L‑ISA‑style frontal scene.

Coordinates are normalised: `X` −1…+1 (left→right), `Y` −1…+1 (rear→front),
`Z` 0…1 (floor→ceiling).

---

## Saving shows

**Export** writes the room, objects, OSC mapping and panner settings to a
`*.spp.json` file; **Import** loads one back. Plain JSON, friendly to version
control.

---

## Roadmap

- [ ] **Binaural mixdown** — a headphone render path for offline work. Two routes
      that share this same room/object model: a native REAPER **JSFX HRTF convolver**
      for monitoring, and an **offline Python renderer** (multichannel → binaural via
      a SOFA HRTF set) for final deliverables.
- [ ] Position **automation** — record/playback object trajectories, write to REAPER
      envelopes.
- [ ] Read computed speaker gains **back** from REAPER for a true output meter.
- [ ] Optional **WebSocket** transport for lower‑latency streaming.

---

## A note on safety

This talks to a **live REAPER session** and moves real panner parameters. It only
ever *sends* OSC — it won't change routing, arm tracks, or touch transport. Still,
test on a scratch project before pointing it at a show you care about, and confirm
the bridge's OSC port matches REAPER's listen port so messages land where you expect.

---

## Licence

[MIT](../LICENSE) — part of the tk Audio Services *Audio* repo.
