#!/usr/bin/env python3
"""Working Folders — menu bar app.

A small ★ in the macOS menu bar with a live dropdown of your shelf: click a
project to jump to it, or add the folder you're looking at. Created by tk Audio
Services.

Always-running UI, started at login by a LaunchAgent (see install.command).
Needs PyObjC (AppKit) — the installer checks for it and offers to add it.

Run directly to test:  /usr/bin/python3 menubar.py
"""
import os
import subprocess
import sys

try:
    import objc
    from AppKit import (NSApplication, NSStatusBar, NSMenu, NSMenuItem, NSImage,
                        NSVariableStatusItemLength,
                        NSApplicationActivationPolicyAccessory)
    from Foundation import NSObject
except Exception:
    sys.stderr.write("Working Folders menu bar needs PyObjC (AppKit). "
                     "Run install.command and let it add PyObjC.\n")
    sys.exit(3)

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, "working-folders.sh")
HUB = os.environ.get("WORKING_FOLDERS_HUB", os.path.expanduser("~/Working Folders"))
SYMBOL = os.environ.get("WORKING_FOLDERS_SYMBOL", "star")
ICON_FILE = "Icon\r"  # the custom-folder-icon file — never show it as an entry


def _engine(*args):
    """Run the shell engine without blocking the menu bar."""
    try:
        subprocess.Popen(["/bin/bash", ENGINE, *args])
    except Exception:
        pass


class WorkingFoldersDelegate(NSObject):

    # --- Objective-C selectors (these are called by AppKit) -----------------
    def applicationDidFinishLaunching_(self, _note):
        self.statusItem = NSStatusBar.systemStatusBar().statusItemWithLength_(
            NSVariableStatusItemLength)
        button = self.statusItem.button()
        # a real system symbol — template, so it adapts to light/dark menu bars
        image = NSImage.imageWithSystemSymbolName_accessibilityDescription_(
            SYMBOL, "Working Folders")
        if image is not None:
            image.setTemplate_(True)
            button.setImage_(image)
        else:
            button.setTitle_("★")
        self.menu = NSMenu.alloc().init()
        self.menu.setDelegate_(self)          # rebuild each time it opens
        self.statusItem.setMenu_(self.menu)
        self.rebuild()

    def menuWillOpen_(self, _menu):           # NSMenuDelegate — keep it fresh
        self.rebuild()

    def openEntry_(self, sender):
        path = sender.representedObject()
        if path:
            subprocess.Popen(["/usr/bin/open", str(path)])

    def addCurrent_(self, _sender):
        _engine("add-current")

    def openShelf_(self, _sender):
        subprocess.Popen(["/usr/bin/open", HUB])

    def runSetup_(self, _sender):
        # open Terminal so the setup prompts are visible
        subprocess.Popen(["/usr/bin/open", "-a", "Terminal",
                          os.path.join(HERE, "Working Folders.command")])

    def quit_(self, _sender):
        NSApplication.sharedApplication().terminate_(self)

    # --- pure-Python helpers (hidden from the Obj-C runtime) ----------------
    @objc.python_method
    def add_item(self, title, action, key=""):
        item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, action, key)
        if action is not None:
            item.setTarget_(self)
        else:
            item.setEnabled_(False)
        self.menu.addItem_(item)
        return item

    @objc.python_method
    def rebuild(self):
        self.menu.removeAllItems()
        self.add_item("Working Folders", None)
        self.menu.addItem_(NSMenuItem.separatorItem())
        try:
            entries = sorted(e for e in os.listdir(HUB)
                             if not e.startswith(".") and e != ICON_FILE)
        except OSError:
            entries = []
        if entries:
            for name in entries:
                item = self.add_item(name, b"openEntry:")
                item.setRepresentedObject_(os.path.join(HUB, name))
        else:
            self.add_item("(shelf is empty — add something below)", None)
        self.menu.addItem_(NSMenuItem.separatorItem())
        self.add_item("Add the Folder I’m Looking At", b"addCurrent:")
        self.add_item("Open Working Folders Shelf", b"openShelf:")
        self.add_item("Set Up / Pin to Sidebar…", b"runSetup:")
        self.menu.addItem_(NSMenuItem.separatorItem())
        self.add_item("Quit", b"quit:", "q")


def main():
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)  # no Dock icon
    delegate = WorkingFoldersDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.run()


if __name__ == "__main__":
    main()
