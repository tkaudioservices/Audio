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
- **macOS** (any recent version). Finder + AppleScript are built in; the core
  needs **no installs**.
- The optional **★ menu bar app** and the **automatic icon** use Apple's
  **PyObjC**. The installer checks for it and offers to add it (a quick,
  user-only `pip install` — no admin). Everything else works without it.

> macOS only — this is a Finder tool, so there's no Windows version.

## Quick start — two ways
**A) Install it properly (recommended).** Double-click **`install.command`**
(first time: **right-click → Open → Open**). It copies the tool into
`~/Library/Application Support`, creates and stars your shelf, pins it to the
Finder sidebar, and — if you let it add PyObjC — puts a **★ in your menu bar**
that starts automatically at login. Re-runnable; undo any time with
**`uninstall.command`**. See [Installed mode & the ★ menu bar app](#installed-mode--the--menu-bar-app).

**B) Just run it from here (no install).** Double-click
**`Working Folders.command`** → **5) First-time setup**. Good for trying it out,
or if you'd rather not install anything.

**The one-time sidebar step:** setup pins the shelf automatically if `mysides`
is installed; otherwise it opens the shelf so you can **drag “Working Folders”
into the sidebar under *Favourites*** (just above *Locations*). Either way it's a
one-time thing — from then on it's one click away.

From now on:

## Daily use
- **Pin what you're working on** — whichever suits you:
  - The **★ menu bar** → *Add the Folder I'm Looking At*.
  - Or the menu (**`Working Folders.command`**) → **1) Add the folder I'm
    looking at**.
  - Or command line: `./working-folders.sh add "/path/to/a/folder"`
- **Jump to a project** — click **Working Folders** in the Finder sidebar, then
  double-click the project. No hierarchy to wade through.
- **Take it off the shelf** when you're done — menu option **4**. This deletes
  only the shortcut; the real folder and its files are untouched.

## Installed mode & the ★ menu bar app
Running **`install.command`** gives you the always-there version:

- **A ★ in the menu bar** with a live dropdown: every folder on your shelf
  (click one to jump straight there), plus *Add the folder I'm looking at*,
  *Open the shelf*, and *Set up*. It starts at login and quietly relaunches if
  it ever crashes — though **Quit** in its own menu really does quit. It uses the
  same system `star`, drawn as a *template* image so it adapts perfectly to
  light/dark menu bars.
- **A stable home.** The tool is copied to `~/Library/Application Support/Working
  Folders/`, so it no longer matters where this repo folder lives (e.g. inside
  Dropbox).
- **A star in the sidebar.** Setup gives the shelf the same system `star` icon
  and bounces Finder's sidebar cache so it shows (not a generic folder). If it
  ever reverts to a plain folder, run **6) Refresh the sidebar star icon**.
- **Login item.** A LaunchAgent at
  `~/Library/LaunchAgents/com.tkaudioservices.workingfolders.menubar.plist`.

**It needs PyObjC.** The menu bar app and the automatic icon use Apple's PyObjC,
which macOS's `/usr/bin/python3` often doesn't ship. The installer offers to add
it for your user only — `/usr/bin/python3 -m pip install --user
pyobjc-framework-Cocoa`, no admin. Say no and everything else still works; you
just won't get the menu bar or the auto icon (you can still set one by hand).

**Why there's no background “service”/daemon.** There's nothing to run
continuously — the shelf is just aliases in the sidebar, and adding/removing is
on-demand. The menu bar app is the only always-running piece, and it exists only
to give you the dropdown; the shelf itself needs no process at all.

**Uninstall.** Double-click **`uninstall.command`** (a copy is kept in the
Application Support folder). It stops and removes the menu bar app and its login
item, and *asks* before touching your shelf. It can't unpin the sidebar item for
you — do that with right-click → *Remove from Sidebar*.

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
gallery), then refresh the sidebar icon:
```
WORKING_FOLDERS_SYMBOL=folder.fill   ./working-folders.sh refresh
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
./working-folders.sh refresh         # re-apply the sidebar star icon
./working-folders.sh doctor          # check every moving part
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

## The sidebar pin (and `mysides`)
Pinning the shelf to the sidebar is a **one-time** thing. Two ways:

- **Automatic** — if [`mysides`](https://formulae.brew.sh/cask/mysides) is
  installed, **setup** pins it for you and relaunches Finder. `mysides` is a
  Homebrew **cask** (note `--cask`), and the installer offers to add it:
  ```
  brew install --cask mysides
  ```
- **Manual (no install)** — setup opens the shelf with it highlighted; just
  **drag “Working Folders” into the sidebar under _Favourites_**. Three seconds,
  once, done.

setup **verifies** the pin actually took (mysides is an old tool and newer macOS
can be fussy); if it didn't, it falls back to guiding the manual drag.

> **Can't see Favourites / your pin?** macOS can collapse that section — hover
> next to the word **Favourites** in the sidebar and click **Show**. Or
> Finder → Settings → Sidebar to make sure Favourites is enabled.

Want each project as its **own** sidebar item instead of inside the shelf?
`mysides add "Smith Wedding" "file:///Users/you/Dropbox/Clients/2026/Smith%20Wedding/"`
(and `mysides remove …`, `mysides list`). The shelf is the default because it
keeps the sidebar tidy — one item, not twenty.

## Files in this folder
- `working-folders.sh` — the engine (menu + command line, bash + AppleScript).
  Also renders the system SF Symbol for the icon, on your Mac, no assets shipped.
- `Working Folders.command` — double-click launcher for the menu (macOS)
- `install.command` / `uninstall.command` — set up (or remove) the installed
  mode: Application Support copy and the ★ menu bar login item
- `menubar.py` — the ★ menu bar app (PyObjC); started at login by the installer
- `README.md` — this file

## Notes / caveats
- Aliases are smart: if you **move or rename** a project, its alias usually
  still finds it (that's a Finder alias doing its job — better than a symlink).
- If a project is **online-only** (the little cloud icon), double-clicking its
  alias downloads it first, same as opening it normally.
- The shelf is per-Mac. If you want the *same* shelf on two Macs, you'd be
  syncing aliases through Dropbox again — better to just run setup on each Mac
  and pin the folders you use there.
