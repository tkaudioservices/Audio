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
2. Choose **5) First-time setup**. It creates the shelf, gives it the **system
   line-art star icon** (see [The icon](#the-icon)) so it stands out, and
   reveals it in Finder. **Drag the “Working Folders” folder into your Finder
   sidebar**, under *Favourites* (the section just above *Locations*). You only
   do this once.
3. Choose **6) Build the drag-&-drop app** to get an
   **“Add to Working Folders”** app (same line-art icon) in your `~/Applications`
   folder. Keep it in your Dock (optional, but handy).

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

## Removing things — two different things
There are two separate "removes", depending on what you mean:

1. **Stop a project showing up on the shelf** (the usual one). Menu option
   **4) Take a folder off the shelf**, or `./working-folders.sh remove`, or just
   open the shelf and **drag the alias to the Trash**. Either way you're only
   deleting the *shortcut* — the real folder and everything in it is untouched.

2. **Remove the shelf itself (or anything) from the Finder sidebar.** That's a
   Finder thing, not this tool: **right-click the item in the sidebar →
   “Remove from Sidebar”** (or just drag it out until you see the ✕). This only
   *unpins* it — it doesn't delete the folder. Works for any sidebar entry,
   including ones you no longer use under *Favourites*. (You can't remove the
   *Locations* items like iCloud/Dropbox this way — those are managed by Finder
   and the apps themselves.)

If you'd already pinned the shelf **before** it got its icon, remove it from the
sidebar and drag it back in (or just log out/in) so the sidebar picks up the new
icon.

## The icon
It uses a **built-in Apple icon** — an [SF Symbol](https://developer.apple.com/sf-symbols/),
the same line-art set the Finder sidebar itself uses — so it looks native rather
than like a pasted-on logo. The default is the line-art **`star`**.

Nothing is downloaded or committed: the symbol is **rendered on your Mac** at
setup/build time (via the system Python + Cocoa) and tinted to your **accent
colour**, so it stays readable in both light and dark sidebars.

**Use a different symbol** — pick any name from the *SF Symbols* app (or Apple's
gallery):
```
WORKING_FOLDERS_SYMBOL=folder        ./working-folders.sh setup       # set the shelf icon
WORKING_FOLDERS_SYMBOL=folder.fill   ./working-folders.sh build-app   # and/or the app icon
```
Good ones to try: `star`, `star.fill`, `folder`, `folder.fill`, `tray.full`,
`pin`, `bookmark`. (Or change the `ICON_SYMBOL` default near the top of
`working-folders.sh`.)

**Set the icon by hand** (if your macOS is older than 11, or you just prefer to):
select the shelf folder → **⌘I** (Get Info) → drag any image onto the little
icon top-left, or copy an icon from another Get Info window and paste with **⌘V**.
The shelf works fine with no custom icon at all.

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
- `working-folders.sh` — the engine (menu + command line, bash + AppleScript).
  Also renders the system SF Symbol for the icon, on your Mac, no assets shipped.
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
