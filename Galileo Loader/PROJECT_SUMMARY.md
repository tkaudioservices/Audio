# Galileo Loader — Project Summary (for development)

A small cross‑platform tool that reads a WaveCapture filter export and sends the
parametric EQ to a **Meyer Sound Galileo** as OSC over UDP. It's a modern
replacement for the old **TXTtoG616** MaxMSP standalone — a single Python file
(standard library only) instead of a 10 MB Windows Max runtime.

It runs a tiny **local web server** and opens the UI in the browser; the Python
process does the UDP sending. That sidesteps both the "browser can't send UDP"
limit and the "Mac Python has no Tkinter" problem, and keeps the UI nice.

---

## File layout
```
Galileo Loader/
├─ galileo_loader.py            ← the whole app (UI + server + logic)
├─ tk_logo.png                 ← logo (served at /logo.png; bundled into the .exe)
├─ Launch Galileo Loader.command  ← double‑click launcher (macOS)
├─ Launch Galileo Loader.bat      ← double‑click launcher (Windows)
├─ README.md                   ← user‑facing usage & safety
└─ PROJECT_SUMMARY.md          ← this file
   (CI build: ../.github/workflows/build-galileo-loader.yml)
```

## Architecture (one file, no dependencies)
`galileo_loader.py` is organised top‑to‑bottom:

1. **OSC encoding** — `osc_string`, `osc_message`. Builds raw OSC (4‑byte aligned,
   big‑endian float). Verified byte‑for‑byte against the `python‑osc` library.
2. **Parsing** — `parse_biquad` accepts two layouts:
   - WaveCapture **biquad list** (tab/space, header, `BIQ# Type Freq BW Gain …`)
   - **headerless** rows of three numbers (comma or space). `_columns_from_simple`
     auto‑detects which column is frequency / gain / bandwidth (freq = largest
     values, gain = the column that goes negative, bandwidth = the rest).
3. **Build / send** — `build_messages` makes `(address, value)` pairs for each
   selected output; `send_messages` fires them over a UDP socket.
4. **LAN discovery** — `scan_network`: UDP‑probes every address on the local /24 to
   populate the ARP cache, reads it (`arp -a` / `ip neigh`, parsed for the Windows,
   macOS and Linux formats), reverse‑resolves names, and flags likely Galileos by
   hostname keywords **and** Meyer's MAC prefixes (`MEYER_PREFIXES` — currently
   the 24‑bit OUI `00:1C:AB` plus the 28‑bit IAB `00:50:C2:21:6X` under the
   shared IEEE Registration Authority pool; extend the tuple when new units
   surface). Each host is returned with a `match` string (`"Meyer OUI"`,
   `"name match"`, or empty) so the UI can show *why* it was flagged.
5. **Local web app** — `ThreadingHTTPServer`; routes: `GET /` (page),
   `GET /logo.png`, `POST /scan`, `POST /send`. Binds `127.0.0.1` on an ephemeral
   port and opens the browser. A one‑time random **token** guards `/scan` and
   `/send`.
6. **Embedded UI** — `PAGE_TEMPLATE` (HTML/CSS/JS): drag‑drop parse + live preview,
   output chips, the **EQ response canvas** (sum of RBJ peaking biquads), and the
   scan results with the **Galileos only** filter. The JS parser mirrors the Python
   one so preview and send agree.
7. **CLI** — `run_cli` for scripting: `--ip --port --outputs --start-band --send`.
8. **`main()`** — arguments → CLI; no arguments → web app.

## Run it (development)
```bash
python3 galileo_loader.py                       # opens the browser UI
python3 galileo_loader.py file.txt --ip 192.168.1.171 --outputs 1,2,6        # dry‑run preview
python3 galileo_loader.py file.txt --ip 192.168.1.171 --outputs 1,2,6 --send # actually send
```
No runtime dependencies, so a virtualenv is optional. In VS Code, select any
Python 3 interpreter and run/debug `galileo_loader.py` directly.

## Build the Windows .exe
Built automatically by GitHub Actions on `windows-latest`
(`.github/workflows/build-galileo-loader.yml`):

- **Manual build:** Actions tab → *Build Galileo Loader (Windows)* → *Run workflow*.
  `GalileoLoader.exe` is uploaded as a workflow artifact (90‑day retention).
- **Release build:** push a tag matching `galileo-loader-v*`
  (e.g. `git tag galileo-loader-v0.2.0 && git push origin galileo-loader-v0.2.0`).
  The exe is attached to the matching GitHub Release.

Pipeline: `pip install pyinstaller` → `pyinstaller --onefile --name GalileoLoader
--add-data "tk_logo.png;." galileo_loader.py`. No local Windows machine needed
(exes can't be cross‑built from macOS, which is exactly why this lives in CI).

## Things that are reverse‑engineered (verify on hardware)
- OSC addresses `/Output/<n>/EQ/<band>/Parametric/{Frequency,Bandwidth,Gain}` and
  UDP port **15006**, taken from the original tool — **test on a spare output**.
- Bandwidth is sent **as‑is in octaves**; only **PEQ** filters are sent.
- Open question: whether a band needs an explicit "enable"/type message, and the
  exact band‑numbering the firmware expects. Confirm in Compass.

## What's already verified (in this sandbox)
OSC encoding == python‑osc · both parser formats incl. the real sample · RBJ EQ
maths (a +6 dB band reads +6.00 at centre) · ARP parser on Win/macOS/Linux output ·
OUI flag · token‑guarded `/scan` and `/send` · full file round‑trips over UDP.

## Ideas / next steps
- **Test‑band button** — set one band to an obvious value on a chosen output to
  confirm the mapping live.
- **Shelves / HP / LP** — currently PEQ only; needs the Galileo OSC paths for those.
- **Presets** — save/recall target + output mapping.
- **Optional refactor** — if it grows, split into `osc.py`, `parser.py`,
  `scan.py`, `server.py` and a `web/index.html`. The single file is intentional
  for now (trivial to copy/run); only split if it earns its keep.

---

## Windows distribution notes
The CI workflow produces a PyInstaller **`--onefile`** exe — picked over `--onedir`
because the audience is crew (one file is easier to share via Dropbox/WhatsApp).
Tradeoffs to know if anything starts misbehaving:

- **SmartScreen** will say *"Windows protected your PC"* on first run of any
  unsigned exe (*More info → Run anyway*). The only fix is a code‑signing
  certificate (~£100–400/yr) — not worth it for internal use.
- **Defender / AV false positives** occasionally flag PyInstaller `--onefile`
  builds. If it bites, switch the workflow to `--onedir` (a folder you zip;
  faster startup, fewer flags) — or escape to **Nuitka** (real compiled binary,
  fewer false positives, slower builds).
- The Python source path (install Python + run `Launch Galileo Loader.bat`)
  stays viable for crew machines where the exe is awkward.
