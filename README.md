# Audio

Small open‑source audio tools and experiments by **tk Audio Services**.
Things I've built for my own live‑sound and AV work that I'm happy to share.

Each project lives in its own folder with its own README and (where relevant)
its own release pipeline. Pick one below.

## Projects

| Project | What it does |
|---|---|
| [SurroundPanner](SurroundPanner/) | A browser **control surface for immersive, object‑based mixing in REAPER**. Your tracks become objects you drag around a room; a small ReaScript drives a custom **tk SurroundPanner** JSFX so moves apply live and render to file. DBAP panning, real speaker layouts (directional walls + ceiling zones), per‑object motion effects you can **bake to automation**, **cue snapshots**, a **stereo/binaural rehearsal fold**, depth cue and a radial view. A lightweight open take on the L‑ISA / KLANG workflow — talking to a session you already own. Standard‑library Python bridge, single JSFX, no build step. See its [README](SurroundPanner/) to get started. |
| [Galileo Loader](Galileo%20Loader/) | Reads a WaveCapture / FIR‑Capture biquad export and sends the parametric EQ to a **Meyer Sound Galileo** as OSC over UDP. A small, cross‑platform replacement for the 2015 MaxMSP *TXTtoG616* standalone — one Python file, no install. Bundled UI, network discovery and a Windows .exe via GitHub Actions. |

## Tools

Smaller standalone utilities live under **[Tools/](Tools/)** to keep the root
tidy — each in its own folder with its own README.

| Tool | What it does |
|---|---|
| [Working Folders](Tools/Working%20Folders/) | One‑click Finder‑sidebar access to the folders you're working on right now — a small "shelf" of aliases you pin once, instead of fighting Finder tags that Dropbox won't sync. macOS, no installs. |

## Downloads

Pre‑built binaries (currently Windows only) are on the
**[Releases](https://github.com/tkaudioservices/Audio/releases)** page —
look for the tag matching the project, e.g. `galileo-loader-v0.2.0`.

Tools that ship as a single Python script also run directly from source —
clone or download the file, then follow that project's README.

## Running from source

Most projects here are deliberately **standard library only** Python — no
`pip install`, no virtualenv required. If a project needs extra deps it'll
say so in its README.

## A note on safety

These tools talk to **real, live audio equipment**. They're "as‑is" — read
each project's safety notes before pointing them at gear you care about, and
test on a spare output first.

## Licence

[MIT](LICENSE) — use, modify, redistribute. Attribution appreciated.

---

by tk Audio Services
