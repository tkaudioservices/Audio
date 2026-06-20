#!/usr/bin/env python3
"""
tkSurroundPanner bridge — tk Audio Services  ·  app v0.17.0
=========================================================

Connects the web UI to the SurroundPanner_Live.lua script running inside REAPER,
using two small JSON files in REAPER's tkSurroundPanner folder (no OSC, no extensions):

  browser  --HTTP-->  this bridge  --writes cmds.json-->     Live.lua (REAPER)
  browser  <--HTTP--  this bridge  <--reads session.json--   Live.lua (REAPER)

Live.lua applies the commands with TrackFX_SetParamNormalized — reliable on every
track, and it publishes the current scene to session.json so the UI auto-loads
with no Scan/Import step.

Setup is now just:
  1. In REAPER, run SurroundPanner_Live.lua  (Actions -> Load ReaScript). Leave it running.
  2. Run this bridge:  python3 reaper_bridge.py
  3. Open http://localhost:9000/

Standard library only — no pip install.
"""
import argparse
import json
import os
import re
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = 6
HERE = os.path.dirname(os.path.abspath(__file__))
WEB_ROOT = os.path.dirname(HERE)

def _reaper_resource():
    home = os.path.expanduser("~")
    if sys.platform == "darwin":
        return os.path.join(home, "Library", "Application Support", "REAPER")
    if sys.platform.startswith("win"):
        return os.path.join(os.environ.get("APPDATA", home), "REAPER")
    return os.path.join(home, ".config", "REAPER")

# Shared with SurroundPanner_Live.lua, which uses reaper.GetResourcePath()/tkSurroundPanner
IPC_DIR = os.path.join(_reaper_resource(), "tkSurroundPanner")
CMDS = SESSION = ROOM = LEVELS = BAKE = ""
def _set_paths():
    global CMDS, SESSION, ROOM, LEVELS, BAKE
    CMDS = os.path.join(IPC_DIR, "cmds.json")
    SESSION = os.path.join(IPC_DIR, "session.json")
    ROOM = os.path.join(IPC_DIR, "room.json")
    LEVELS = os.path.join(IPC_DIR, "levels.json")
    BAKE = os.path.join(IPC_DIR, "bake.json")
_set_paths()

ADDR_RE = re.compile(r"^/track/(\d+)/fx/(\d+)/fxparam/(\d+)/value$")


class Mailbox:
    """Accumulates the latest value per (track,fx,param) and writes cmds.json."""
    def __init__(self):
        self.params = {}          # "t/f/p" -> (t, f, p, value)
        self.seq = 0
        self.lock = threading.Lock()

    def update(self, messages):
        changed = False
        with self.lock:
            for m in messages:
                mt = ADDR_RE.match(m.get("addr", ""))
                if not mt:
                    continue
                t, f, p = int(mt.group(1)), int(mt.group(2)), int(mt.group(3))
                self.params["%d/%d/%d" % (t, f, p)] = (t, f, p, float(m["value"]))
                changed = True
            if not changed:
                return
            self.seq += 1
            payload = '{"seq":%d,"params":[%s]}' % (
                self.seq,
                ",".join('{"t":%d,"f":%d,"p":%d,"v":%.4f}' % v for v in self.params.values()),
            )
        # atomic write so the Lua never reads a half-written file
        fd, tmp = tempfile.mkstemp(dir=IPC_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as fh:
            fh.write(payload)
        os.replace(tmp, CMDS)


class BakeBox:
    """Writes bake.json with an incrementing seq so the Lua picks up each new bake/clear once.
    Each item is {t, x, y, z}: track number + the object's base position to bake around."""
    def __init__(self):
        self.seq = 0
        self.lock = threading.Lock()

    def write(self, action, items):
        action = "clear" if action == "clear" else "bake"
        parts = []
        for it in items:
            parts.append('{"t":%d,"x":%.4f,"y":%.4f,"z":%.4f}' % (
                int(it.get("t", 0)), float(it.get("x", 0)), float(it.get("y", 0)), float(it.get("z", 0))))
        with self.lock:
            self.seq += 1
            payload = '{"seq":%d,"action":"%s","items":[%s]}' % (self.seq, action, ",".join(parts))
        fd, tmp = tempfile.mkstemp(dir=IPC_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as fh:
            fh.write(payload)
        os.replace(tmp, BAKE)


class Handler(BaseHTTPRequestHandler):
    mailbox = None
    bakebox = None

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self._cors()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def log_message(self, *a):
        pass

    def do_OPTIONS(self):
        self._send(204)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/ping":
            live = os.path.isfile(SESSION)
            return self._send(200, ('{"ok":true,"version":%d,"live":%s}' % (VERSION, "true" if live else "false")).encode(), "application/json")
        if path == "/session":
            if os.path.isfile(SESSION):
                return self._serve_file(SESSION, "application/json")
            return self._send(404, b'{"error":"no session - run SurroundPanner_Live.lua in REAPER"}', "application/json")
        if path == "/levels":
            if os.path.isfile(LEVELS):
                return self._serve_file(LEVELS, "application/json")
            return self._send(200, b'{"levels":[]}', "application/json")
        if path in ("/", "/index.html"):
            return self._serve_file(os.path.join(WEB_ROOT, "index.html"), "text/html")
        safe = os.path.normpath(os.path.join(WEB_ROOT, path.lstrip("/")))
        if safe.startswith(WEB_ROOT) and os.path.isfile(safe):
            ext = safe.rsplit(".", 1)[-1].lower()
            ctype = {"png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon",
                     "json": "application/json", "html": "text/html"}.get(ext, "application/octet-stream")
            return self._serve_file(safe, ctype)
        return self._send(404, b"not found")

    def _serve_file(self, full, ctype):
        try:
            with open(full, "rb") as f:
                self._send(200, f.read(), ctype)
        except OSError:
            self._send(404, b"not found")

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        try:
            n = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(n) or b"{}"
            if path == "/room":                       # speaker layout for the JSFX
                fd, tmp = tempfile.mkstemp(dir=IPC_DIR, suffix=".tmp")
                with os.fdopen(fd, "wb") as fh:
                    fh.write(raw)
                os.replace(tmp, ROOM)
                return self._send(200, b'{"ok":true}', "application/json")
            if path in ("/set", "/osc"):              # object positions
                self.mailbox.update(json.loads(raw).get("messages", []))
                return self._send(200, b'{"ok":true}', "application/json")
            if path == "/bake":                       # bake / clear FX -> envelopes
                d = json.loads(raw)
                self.bakebox.write(d.get("action", "bake"), d.get("items", []))
                return self._send(200, b'{"ok":true}', "application/json")
            self._send(404, b"not found")
        except Exception as e:
            self._send(400, json.dumps({"ok": False, "error": str(e)}).encode())


def main():
    ap = argparse.ArgumentParser(description="tkSurroundPanner <-> REAPER (file bridge)")
    ap.add_argument("--port", type=int, default=9000)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--ipc-dir", default=None, help="folder shared with the Live script (default: REAPER resource path/tkSurroundPanner)")
    args = ap.parse_args()

    if args.ipc_dir:
        global IPC_DIR
        IPC_DIR = args.ipc_dir
        _set_paths()
    os.makedirs(IPC_DIR, exist_ok=True)
    Handler.mailbox = Mailbox()
    Handler.bakebox = BakeBox()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)

    print("=" * 64)
    print("  tkSurroundPanner bridge — tk Audio Services   (v%d)" % VERSION)
    print("=" * 64)
    print("  UI:       http://%s:%d/" % (args.host, args.port))
    print("  link:     %s" % IPC_DIR)
    print("  REAPER:   run SurroundPanner_Live.lua and leave it running.")
    if not os.path.isfile(SESSION):
        print("  note:     session.json not found yet — start the Live script in REAPER.")
    print("  Ctrl-C to stop.")
    print("=" * 64, flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  stopped.")
        httpd.server_close()


if __name__ == "__main__":
    main()
