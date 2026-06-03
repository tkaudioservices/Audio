# Galileo Loader
**Created by tk Audio Services.**

A small, modern replacement for the old **TXTtoG616** MaxMSP standalone.
It reads a filter list exported from WaveCapture (or any plain list of
frequency / gain / bandwidth) and sends the parametric filters to a
**Meyer Sound Galileo** as OSC over UDP — the same thing the original did, but
as a few‑KB cross‑platform app instead of a 10 MB Windows Max runtime.

It runs a tiny **local web server** and opens the interface in your **browser**.
The Python process does the UDP sending, so nothing needs installing — not even
Tkinter (which many Macs ship without).

## Requirements
- **Python 3** (any recent version). Standard library only — no `pip install`.

It runs natively on **macOS, Windows and Linux** — same one file.

## Run it
- **Mac:** double‑click **`Launch Galileo Loader.command`**.
  (First time, macOS may block it: right‑click → Open.)
- **Windows:** double‑click **`Launch Galileo Loader.bat`**.
  (Install Python from python.org first, ticking *Add Python to PATH*.)
- **Any OS, manually:** `python3 galileo_loader.py` (or `py galileo_loader.py` on Windows)

A small console window opens and your browser pops up with the app.
*Leave that console window open while you use it; close it (or press Ctrl‑C)
when you're done.*

- **Command line (scripting):**
  `python3 galileo_loader.py "Live Room EQ.txt" --ip 192.168.1.171 --outputs 1,2,6`
  Add `--send` to transmit (without it you get a dry‑run preview).

## How to use
1. In Live‑Capture, export filters: **Output tab → Export Selection** as text
   (a "Biquad list", with `BW` in **Octaves**). Save it anywhere convenient.
2. Drop that file onto the app (or click to choose / paste it in).
3. Set the Galileo **IP** and **port** (default `15006`) — or press
   **🔍 Find on network** to scan your subnet and click the right device.
4. Tick the **output(s)** to load — you can pick several at once.
5. Check the **preview** (every OSC message is shown), then **Send** (it confirms first).

**Accepted files.** Either a WaveCapture **biquad list** (tab‑separated, with a
header) or a **headerless list** of three numbers per line — frequency, gain and
bandwidth in any order, comma‑ or space‑separated (the original Galileo tool's
format). The app auto‑detects which column is which and shows it; check the
preview. Only **PEQ** filters are sent.

**EQ curve.** Once a file loads, the app draws the combined EQ response so you
can eyeball the curve before sending.

## Finding Galileos on the network
Galileos are **DHCP by default**, so their IP can change. The **Find on network**
button probes your subnet (a tiny UDP packet to each address), reads the ARP
table and reverse‑resolves names, then flags likely Meyer devices — by name and
by **MAC prefix** (Meyer's `00:1C:AB` OUI and their `00:50:C2:21:6X` IAB block).
"Galileos only" is on by default; untick it to see every host. Each match shows
*why* it was flagged (**Meyer OUI** or **name match**), so if a new unit doesn't
appear, send me its MAC and we can add the prefix. **Confirm it's the right
unit** before sending; if yours doesn't appear, just type the IP (or use
Compass's own *Find Devices*). Works on Windows, macOS and Linux.

## What it sends
For each PEQ filter, three OSC messages:

```
/Output/<out>/EQ/<band>/Parametric/Frequency   <Hz>
/Output/<out>/EQ/<band>/Parametric/Bandwidth   <octaves>
/Output/<out>/EQ/<band>/Parametric/Gain        <dB>
```

Bands are numbered from "First EQ band #" (default 1). Only **PEQ** filters are
sent; other types are listed and skipped.

Messages are **paced** — a small delay between each, plus a longer pause when
the output number changes. This mirrors what the original *TXTtoG616* did, and
keeps the Galileo from dropping packets (or crashing) when several outputs are
loaded at once. A multi‑output send takes a second or two by design.

## Please read — safety
- This changes EQ on a **live** loudspeaker processor. It never sends until you
  press **Send** / pass `--send`, and the browser always asks you to confirm.
  **Verify on a spare output before a show.**
- The local page only talks to this script on `127.0.0.1`, and a one‑time random
  token guards the send/scan actions.

## Standalone Windows .exe (no Python needed)
A pre‑built `GalileoLoader-v<version>.exe` is published to the repo's
**GitHub Releases** page (built automatically on Windows by a GitHub Action).
Download it, double‑click, done — no Python install. Releases are cut by
pushing a `galileo-loader-v*` tag.

## Files in this folder
- `galileo_loader.py` — the app (web UI + command line in one file)
- `Launch Galileo Loader.command` — double‑click launcher for macOS
- `Launch Galileo Loader.bat` — double‑click launcher for Windows
- `tk_logo.png` — tk Audio Services logo shown in the app
- `README.md` — this file

_Verified: the OSC encoding is byte‑for‑byte identical to the `python‑osc`
library, and a full file round‑trips correctly over UDP. Use at your own risk —
same as the original._
