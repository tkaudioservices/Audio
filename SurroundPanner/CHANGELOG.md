# Changelog — tkSurroundPanner

Versioning: `MAJOR.MINOR.PATCH`. The version shows in the web UI header and is
mirrored by the bridge's `/ping` protocol version.

## v0.18.0
- **Trajectory recording.** A **● Record moves** toggle (Objects panel) arms REAPER's **latch automation** on the selected object(s) — or all — and arms their X/Y/Z envelopes. Press play in REAPER and drag objects, and the moves record straight to **editable automation** (then re‑bake/edit/clear like any bake). Turn it off and the tracks return to read. The live‑capture complement to Bake. New bridge endpoint `POST /automation` + `automation.json`; protocol → 7.
- **Note:** this path is REAPER‑native (latch + envelope arming) and needs a REAPER test — see the caveat in the README.

## v0.17.0
- **Cue snapshots.** A new *Cues* panel stores the whole scene — every object's position, gain, mute/solo and effect (keyed by REAPER track). **Capture** the current scene, click a cue to **recall** it, and with **Morph > 0** the objects glide to the cue over that time (eased). **U** updates a cue to the current scene. Cues persist in the browser and **Export/Import** to a file, so a show's looks move between machines. The big one for live/theatre.
- **Per-object solo / mute.** **M** and **S** on each object in the list. Mute silences an object; Solo silences everything else. Drives both the preview (latch lines / meters drop out) and the plug-in (via each object's Gain), so it's audible. Captured in cues.

## v0.16.0
- **New plug-in: `tk SurroundMonitor` — rehearsal / headphone fold-down.** Put it on a stereo monitor track fed by your immersive bus and it folds all the speaker channels to stereo, so you can work without the full rig. It reads the **same gmem speaker layout** as the panner, so every channel is folded by its speaker's real angle.
  - **Stereo fold** — constant-power amplitude fold by each speaker's azimuth (mild rear attenuation, C at −3 dB, optional LFE fold). Light and robust; the rehearsal downmix.
  - **Binaural** — parametric HRTF per channel: ITD (inter-aural delay) + head-shadow (ILD low-pass) from the speaker azimuth. Static per layout, so it renders at full speed too. (A measured HRIR/SOFA path is a future upgrade; this covers the dominant cues.)
  - Controls: Mode, Output (dB), Width %, LFE drop/fold. Leaves the real speaker bus untouched (parallel monitor path). Added to both installers.

## v0.15.0
- **The plug-in's X/Y/Z faders now move with the effect.** While an Orbit/Oscillate/Drift effect runs, the panner writes the live position back to its X/Y/Z sliders, so the faders animate in the plug-in (not just the web view). The **base** position is kept safe internally (`bx/by/bz`, captured from host/UI moves and persisted via `@serialize`), so an effect overwriting the sliders never loses your set position — dragging the object during an effect still re-bases it, and a project saved mid-effect restores correctly.
- Under the hood this needed care so it doesn't fight the rest of the system: **Bake** now receives each object's base position from the UI (the sliders hold the live motion while an effect runs), and **Follow** no longer mirrors an fx object's live slider back as its base. Bridge protocol → 6 (bake payload carries base x/y/z).

## v0.14.0
- **The plug-in now shows the movement.** The `tk SurroundPanner` UI has a live **mini top-view** (speakers + a moving object dot) and a **`now x/y/z`** readout that track the effect-modulated position while playing — so you can see an effect working in the plug-in, not just the browser.
- **Phase offset + Stagger (complex group movement).** Each object effect has a **Phase** control (cycle offset), and with several objects selected, **Stagger phases** spreads the phase evenly across them — so a group orbits/oscillates in sequence (chase / flock) instead of in lockstep. One click → complex motion. Phase is baked too. New FX param tag 15 / JSFX `slider12`.
- **Classic presets now look right on the diagram.** Stereo / 5.1 / 7.1 / 7.1.4 get sensible mount types + coverage: bed/surround speakers become **wall wedges aimed at the centre**, height speakers become **ceiling footprints**, LFE becomes a **sub** — so the coverage drawing is meaningful the moment you pick a preset. (Throw/beam are generous, so the panning stays close to plain DBAP.)
- **Ceiling coverage with a single value now draws.** Setting only Cover W (or only Cover D) on a ceiling/sub speaker makes a **circle** instead of drawing nothing — fixes ceiling footprints appearing blank.
- **Coverage has its own colours.** Footprints/cones are now coloured by mount type (ceiling = green, wall = amber, sub = violet), distinct from the blue object latch lines.

## v0.13.0
- **Bake FX → envelopes.** Bake the selected object(s)' Orbit / Oscillate / Drift motion to X/Y/Z **FX‑parameter automation** over the time selection (whole project if none), then turn the live effect off — so an **offline render runs at full speed** instead of realtime through the plug‑in. The baked envelopes are normal REAPER automation: read and edit them on the track, **re‑bake to overwrite**, or **Clear bake** to remove the points and re‑enable the live effect. Operates on the multi‑selection. (Spread isn't a position move, so it can't be baked.) New bridge endpoint `POST /bake` and `bake.json` IPC; bridge protocol → 5.
- The bake math mirrors the JSFX effect exactly (Orbit/Oscillate phase‑exact; Drift is a deterministic smoothed random walk matching the live character), normalised into each slider's range.

## v0.12.0
- **Wall speakers are now a wedge/cone.** Wall-mounted speakers throw a triangular beam out from the point: **Throw** (how far the audio reaches, in metres), **Beam°** (cone width, default 90°), and **Aim°** (direction). Objects inside the cone get full feed with a soft edge outside — both the picture and the audio weighting. Ceiling/sub keep the ellipse footprint. (Replaces the old forward-ellipse lobe for walls.)
- **Coverage shows only in *Edit room*.** Speaker footprints/cones draw while you're shaping the room and hide once you're panning objects, so the planner stays clean. The selected speaker's coverage and a clear selection ring are highlighted.
- **Click a speaker in the list → it highlights on the canvas** (selecting an object or speaker in the side panel now updates the main view, not just the editor).
- **Pause FX.** A master *Pause FX* button freezes every object effect at its base position — in the preview **and** the plug-in (Effect → Off, settings kept) — so you can stop all motion at once and resume it exactly.
- **Save / Export / Import speaker layouts.** *Room & speakers* can export the whole room + speaker layout to a JSON file and import it back, for reusing venue rigs across shows.
- **Multi-select objects.** Ctrl/⌘-click and Shift-click in the *Objects* list to select several at once; the effect controls (type / rate / depth / axis) then apply to the whole selection, so you can shape a group of objects together.
- Under the hood: per-speaker shared-memory block grew 8 → 9 (adds wall **beam width**); the Live script and JSFX stay in lock-step.

## v0.11.0
- **Real-world units (metres).** The room now has a size (W × D × H in metres, in *Room & speakers*), and object positions, coverage and effect depth all read in metres (X/Y share one isotropic scale, Z uses the height). Internally still normalized, so the engine is unchanged.
- **Speaker mount types — ceiling / wall / sub.** Each speaker has a type. **Ceiling** keeps the down-facing footprint (the coverage ellipse centred under it); **wall** throws its coverage as a forward lobe along its Angle (so directional wall speakers only feed what they point at); **sub** for low-end. The panner and the browser preview both weight by the right shape per type.
- **Time Machine (AIDAnova) preset.** A new *Room & speakers* preset that builds the real 16-channel Time Machine rig — 9 wall FX (directional), 4 ceiling zones (L/N/O, A/B/C, E/F/H, I/J/K), stage centre, ceiling subs, and transition FX — placed from the venue map (`examples/Time Machine - Speaker Map.svg`) in a 42 × 26 × 6 m room.
- Under the hood: per-speaker shared-memory block grew 7 → 8 (adds `type`); the Live script and JSFX stay in lock-step.

## v0.10.1
- **Effect rate is now an exponential scale** (≈0.02–5 Hz) so the slow end — where movement design actually happens — has fine control, shown as seconds-per-cycle (e.g. "28.8 s") for slow rates and Hz for fast.
- **The X/Y/Z faders track the live effect motion** while an effect runs (so you can watch the position move), without changing the base position; they restore to the base when the effect is turned off. (A fader you're dragging is left alone.)

## v0.10.0
- **Effects engine (per-object motion).** Each object can run a movement effect, computed **inside the plug-in** so it renders to file: **Orbit** (circles a centre), **Oscillate** (sweeps along X/Y/Z), **Spread / size** (widens the object across more speakers), and **Random drift** (organic wander). Set Effect / Rate / Depth / Axis in the object editor. The web view **animates the object live** along its path (Orbit/Oscillate are phase-exact; Drift is an approximation since the plug-in's is random), and draws the effect's extent so you can see what it covers.
- The latch lines and meters follow the moving object, so what you see tracks what you hear.

## v0.9.0
- **Speaker coverage shapes.** Each speaker can be given an **elliptical footprint** (Cover W / Cover D / Angle in *Room & speakers*) marking the area it actually feeds. The DBAP gain to each speaker is now weighted by how far the object sits inside that speaker's ellipse, so the pan follows the real rig instead of leaking into speakers that don't cover an area. Coverage is **off by default** (0 = covers everywhere = unchanged behaviour); the ellipses draw on the top view, and the latch lines reflect the weighting. The identical weighting runs in the browser preview and the JSFX.
- Under the hood: the per-speaker shared-memory block grew from 4 to 7 values (adds cw/cd/ca) and the meter base moved clear of it; the Live script now parses each speaker object independently (robust to field order / new keys).

## v0.8.0
- **Panner law now actually reaches the plug-in.** The Live script was writing parameters with `TrackFX_SetParam`, whose out-of-0..1 handling silently no-ops some plug-ins (the classic "Rolloff won't move" trap). It now sets through `TrackFX_SetParamNormalized`, reading each slider's live min/max from the FX — so Focus/Spread (and X/Y/Z/Gain/LFE) land reliably.
- **Focus & Spread, in meaningful units.** "Rolloff" → **Focus** and "Blur" → **Spread**, both shown as **0–100 %** (mapped to the JSFX ranges). "Line cut" is gone — faint links auto-hide at a fixed threshold, and Spread now visibly drives the latch-line links and thicknesses.
- **Per-object LFE send.** Each object gets an **LFE send** fader: a low-passed (~120 Hz) mono feed routed to the room's LFE channel(s). (LFE is still excluded from the positional pan.)
- **Speaker check moved into the plug-in.** Removed the web *Speaker check* panel and the `/noise` IPC. **`tk SurroundNoise`** is now self-contained: **Test noise** on/off, **Speaker channel** (0 = all), and **Level in dB** — right on the plug-in. It still publishes to the shared meters, so the web Output meters confirm it.
- **Plug-in meters removed.** The panner's on-plug-in bar meters are gone (they fed nothing the web UI doesn't); a compact X/Y/Z/LFE + Gain/Focus/Spread readout remains. The web Output meters are unchanged.
- **Favicon** points at the tk mark with a PNG fallback so it renders in the tab.

## v0.7.0
- **Speaker check (per-speaker pink noise).** New **`tk SurroundNoise`** JSFX — drop one on your immersive bus — plus a *Speaker check* panel in the web UI. Click a speaker to send pink noise to just that output channel, or **All speakers**, with a level fader. It's driven from the UI (browser → `/noise` → `noise.json` → Live script → shared memory) and publishes into the same meter region as the panner, so the Output meters confirm it. Built for lining up, level-matching and verifying a real rig during system setup. Stopping the Live script (or hitting **Off**) silences it. Press play in REAPER so the bus processes audio.
- Installer now copies **both** JSFX into `Effects/tk`.

## v0.6.2
- **Output meters now show every speaker, not just L/R.** The web UI was rebuilding the room from the first track's channel count on each session load; a freshly-added panner track reports 2 channels (before the Live script widens it), which silently collapsed a 12-speaker room to stereo — so the meter panel only ever showed channels 1 & 2. The room is now treated as user/preset-defined and authoritative (it's already pushed to the plug-in and the Live script grows tracks/bus to match), so all speaker meters display. *(Verified headless: a session with a 2-channel track now renders 12 meter rows with channels 3–12 live.)*
- **Live session refresh no longer scrambles object positions.** Adding/removing a REAPER track used to re-fan every object onto a ring on reload; now only objects REAPER reports at the exact default origin (never placed) are fanned out for grabbability — real placements are left untouched.
- **Panner-law feedback + range parity.** The header now confirms each law send (`✓ law → N obj · roll · blur`) and warns when no panner object is loaded. The UI Blur slider minimum (was 0.001) now matches the JSFX Spread minimum (0.01), so no value is silently clamped. *(The law transport/mapping was already correct — `TrackFX_SetParam` takes the native range — so this is observability + parity, not a transport fix.)*
- **Robustness.** The Live script clamps the speaker layout it writes into shared memory to the JSFX's 16-output maximum, so an oversized room can never overwrite the meter region in `gmem`.
- *Get the fixes: reload the web UI, and re-run the `SurroundPanner_Live.lua` action (stop + start) so REAPER loads the new script. The JSFX logic is unchanged in 0.6.2 — re-running the installer only refreshes the version label.*

## v0.6.1
- **Panner law now drives the engine** — Rolloff and Blur in the web UI are sent to every object's JSFX (previously they only changed the on-screen latch lines). Per-object Gain is wired up too.
- **Web meters read straight from the panner** — output meters now come from the JSFX via shared memory (`gmem`), so they match the in-plugin display exactly and no longer depend on the bus being routed as a multichannel folder.
- The in-plugin display also shows the live Gain / Rolloff / Spread values, so law changes are visible in REAPER.
- **UI cleanup** — removed the vestigial "OSC mapping" panel and the stale Scan/OSC-feedback hints; the track/fx/param mapping is filled in automatically by the Live script. Docs (README / WORKFLOW) rewritten to match the current architecture.

## v0.6.0
- **In-plugin meters** — the JSFX now has its own display (`@gfx`): one bar per output channel plus a live X/Y/Z readout, so you can see the panner working right in REAPER.
- **Output meters** — live level per speaker in the web UI, named from the room (read off the bus).
- **Auto channel count** — the Live script widens each panner track (and its bus) to the speaker count.
- **Installer** — `Install tkSurroundPanner.command` / `.bat` copies the JSFX into REAPER's `Effects/tk`.
- Shared runtime files moved to REAPER's resource folder (`…/REAPER/tkSurroundPanner`) so the Live script can run from anywhere.
- Folder `reaper-scripts` renamed to `engine`.

## v0.5.0
- **Custom rooms** — define speaker positions (any count/shape) in the web UI; the
  `tk SurroundPanner` JSFX reads the layout live from REAPER shared memory (`gmem`).
- **Edit room mode** — toggle from the header to drag speakers on the canvas.
- **Live updates** — renaming, recolouring or regrouping a REAPER track updates the
  UI automatically (no reload). Track add/remove still triggers a full refresh.
- Presets corrected to REAPER channel order (with the LFE gap); LFE is non‑positional.

## v0.4.0
- **Own panner engine** — `tk_SurroundPanner.jsfx` (DBAP) replaces ReaSurroundPan,
  which ignored external parameter writes until hand‑touched.
- `SurroundPanner_Live.lua` drives the JSFX sliders directly (reliable on every
  track). No OSC device, no Import/Export. REAPER console silenced.

## v0.3.0
- Folder‑based grouping, track‑colour sync, hide/show objects.
- One‑click `.command` launcher with stale‑bridge detection; bridge version check.
- Real tk logo + favicon.

## v0.2.0
- Bidirectional bridge, `session.json` auto‑load, scan/import of ReaSurroundPan.
- REAPER setup/scan scripts; workflow docs.

## v0.1.0
- Web control surface: room + draggable objects + DBAP latch‑line view.
- Python OSC bridge.
