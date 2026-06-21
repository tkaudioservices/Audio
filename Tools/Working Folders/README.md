# Working Folders
**Created by tk Audio Services.**

One-click access to the folders you're working on **right now** — without
digging back through the whole Dropbox hierarchy every time, and without
relying on Finder tags (which Dropbox doesn't sync reliably).

## The idea
It keeps a small **"shelf" folder** — `~/Working Folders` — that you pin to the
**Finder sidebar once**. You drop the projects you're currently on onto the
shelf, and each one appears there as a **Finder alias** (a shortcut). Click
"Working Folders" in the sidebar, double-click a project, and you're straight
in — wherever it actually lives inside Dropbox. Take it off the shelf when the
job's done.

```
Finder sidebar                 ~/Working Folders  (the shelf)
  Favourites                     ├─ Smith Wedding   ──► …/Dropbox/Clients/2026/Smith Wedding
  ★ Working Folders  ◄───────┐   ├─ Theatre Show 3  ──► …/Dropbox/Live/Theatre/Show 3 Mix
  Locations                  └───┤   └─ Galileo Presets  ──► …/Dropbox/Presets/Galileo
```

**Why aliases, not tags.** Finder tags live in file metadata that Dropbox
doesn't sync well — which is exactly why your coloured tags keep dropping. This
uses no tags and no metadata, just a normal folder of shortcuts. And the shelf
lives **on your Mac, not inside Dropbox**, so Dropbox never gets to mangle it.
Nothing here ever moves, renames or deletes your real project folders — an
alias is only a pointer, and removing one deletes only the pointer.

## Requirements
- **macOS** (any recent version). It uses Finder + AppleScript, both built in.
- No installs, no `pip`, nothing to download. (One *optional* extra below.)

> macOS only — this is a Finder tool, so there's no Windows version.

## Quick start
1. Double-click **`Working Folders.command`**.
   (First time, macOS may block it: **right-click → Open → Open**.)
2. Choose **5) First-time setup**. It creates the shelf and reveals it in
   Finder. **Drag the “Working Folders” folder into your Finder sidebar**, under
   *Favourites* (the section just above *Locations*). You only do this once.
3. Choose **6) Build the drag-&-drop app** to get an
   **“Add to Working Folders”** app in your `~/Applications` folder. Keep it in
   your Dock (optional, but handy).

That's it. From now on:

## Daily use
- **Pin what you're working on** — three ways, whichever suits you:
  - Open the folder in Finder, run the menu, pick **1) Add the folder I'm
    looking at**.
  - **Drag the folder onto the “Add to Working Folders” app** (Dock or toolbar).
  - Command line: `./working-folders.sh add "/path/to/a/folder"`
- **Jump to a project** — click **Working Folders** in the Finder sidebar, then
  double-click the project. No hierarchy to wade through.
- **Take it off the shelf** when you're done — menu option **4**. This deletes
  only the shortcut; the real folder and its files are untouched.

## Command line (for scripting / Terminal folk)
```
./working-folders.sh                 # the interactive menu
./working-folders.sh add-current     # pin the folder in the front Finder window
./working-folders.sh add <folder>…   # pin folders by path
./working-folders.sh list            # what's on the shelf
./working-folders.sh remove          # take something off (interactive)
./working-folders.sh open            # open the shelf
./working-folders.sh setup           # create shelf + pin to sidebar
./working-folders.sh build-app       # build the drag-&-drop app
```
Want the shelf somewhere else? Set `WORKING_FOLDERS_HUB`:
```
export WORKING_FOLDERS_HUB="$HOME/Documents/Active Jobs"
```
Keep it **outside Dropbox** so Dropbox doesn't try to sync the aliases.

## “Can it go in the *Locations* section?”
Short answer: not really, and you don't want it to. macOS reserves **Locations**
for disks, servers and apps — you can't put script-managed folders there. User
folders go in **Favourites**, the section right above it, which is exactly where
this shelf sits. Functionally it's identical: a permanent, one-click item in the
sidebar of every Finder window.

## Optional: a real sidebar entry per folder (`mysides`)
Prefer each project to be its **own** sidebar item rather than living inside the
shelf? Install [`mysides`](https://github.com/mosen/mysides) (a small
open-source Finder-sidebar CLI):
```
brew install mysides
mysides add "Smith Wedding" "file:///Users/you/Dropbox/Clients/2026/Smith%20Wedding/"
mysides remove "Smith Wedding"      # take it out again
mysides list                        # see what's pinned
```
If `mysides` is installed, **setup** will also auto-pin the shelf for you
instead of asking you to drag it. (The shelf approach is the default because it
needs nothing extra and keeps the sidebar tidy — one item, not twenty.)

## Optional: a right-click “Add to Working Folders” in Finder
Want it on the Finder right-click menu too? It's a one-minute Automator job:
1. Open **Automator** → **New** → **Quick Action**.
2. Set *“Workflow receives current”* to **folders** in **Finder**.
3. Drag in a **Run Shell Script** action; set *Pass input* to **as arguments**.
4. Paste (edit the path to where this folder lives):
   ```bash
   "/Users/you/Dropbox/Audio/Tools/Working Folders/working-folders.sh" add "$@"
   ```
5. Save it as **Add to Working Folders**.

Now right-click any folder → **Quick Actions → Add to Working Folders**.

## Files in this folder
- `working-folders.sh` — the engine (menu + command line, bash + AppleScript)
- `Working Folders.command` — double-click launcher for the menu (macOS)
- `droplet.applescript` — source for the drag-&-drop app (built by `build-app`)
- `README.md` — this file

## Notes / caveats
- Aliases are smart: if you **move or rename** a project, its alias usually
  still finds it (that's a Finder alias doing its job — better than a symlink).
- If a project is **online-only** (the little cloud icon), double-clicking its
  alias downloads it first, same as opening it normally.
- The shelf is per-Mac. If you want the *same* shelf on two Macs, you'd be
  syncing aliases through Dropbox again — better to just run setup on each Mac
  and pin the folders you use there.
