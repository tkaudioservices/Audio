#!/usr/bin/env python3
"""
SurroundPanner bridge — tk Audio Services
=========================================

A tiny, dependency-free bridge between the SurroundPanner web UI and REAPER.

  browser  --HTTP/JSON-->  this bridge  --OSC/UDP-->  REAPER

It does two things:
  1. Serves the web UI (index.html) at  http://localhost:<port>/
  2. Accepts POST /osc  {"messages":[{"addr":"/...","value":0.5}, ...]}
     and forwards each as an OSC message to REAPER.

REAPER setup (once):
  Preferences -> Control/OSC/web -> Add -> OSC (Open Sound Control)
    Mode:                 "Configure device IP+local port"
    Device port:          (leave blank — we only send TO reaper)
    Local listen port:    8000        <-- must match --reaper-port below
  Tick "Allow binding messages to REAPER actions and FX learn".

Then run:   python3 reaper_bridge.py
and open:   http://localhost:9000/

Standard library only — no pip install, like the rest of this repo.
"""
import argparse
import json
import os
import socket
import struct
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
WEB_ROOT = os.path.dirname(HERE)  # serve index.html from the repo root folder

# ----------------------------------------------------------------- OSC encode
def _osc_string(s):
    b = s.encode("utf-8") + b"\x00"
    return b + b"\x00" * ((4 - len(b) % 4) % 4)

def osc_message(addr, *args):
    """Encode a minimal OSC message. Supports float and string args."""
    types = ","
    data = b""
    for a in args:
        if isinstance(a, str):
            types += "s"
            data += _osc_string(a)
        else:  # numbers -> 32-bit float (what REAPER fxparam expects)
            types += "f"
            data += struct.pack(">f", float(a))
    return _osc_string(addr) + _osc_string(types) + data


class OSCSender:
    def __init__(self, host, port):
        self.addr = (host, port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.count = 0
        self._last_log = 0.0

    def send(self, addr, value):
        self.sock.sendto(osc_message(addr, float(value)), self.addr)
        self.count += 1
        now = time.time()
        if now - self._last_log > 1.0:  # rate-limited heartbeat
            print(f"  -> OSC {self.addr[0]}:{self.addr[1]}  {self.count} msgs sent "
                  f"(last: {addr} = {float(value):.3f})", flush=True)
            self._last_log = now


# ----------------------------------------------------------------- HTTP server
class Handler(BaseHTTPRequestHandler):
    sender = None  # set in main()

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
        pass  # keep the console clean; OSCSender prints the useful stuff

    def do_OPTIONS(self):
        self._send(204)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/ping":
            return self._send(200, b'{"ok":true}', "application/json")
        if path in ("/", "/index.html"):
            return self._serve_file(os.path.join(WEB_ROOT, "index.html"), "text/html")
        # serve any other static file living next to index.html (defensive)
        safe = os.path.normpath(os.path.join(WEB_ROOT, path.lstrip("/")))
        if safe.startswith(WEB_ROOT) and os.path.isfile(safe):
            return self._serve_file(safe, "application/octet-stream")
        return self._send(404, b"not found")

    def _serve_file(self, full, ctype):
        try:
            with open(full, "rb") as f:
                self._send(200, f.read(), ctype)
        except OSError:
            self._send(404, b"not found")

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/osc":
            return self._send(404, b"not found")
        try:
            n = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(n) or b"{}")
            for m in payload.get("messages", []):
                self.sender.send(m["addr"], m["value"])
            self._send(200, b'{"ok":true}', "application/json")
        except Exception as e:  # never crash the bridge on a bad packet
            self._send(400, json.dumps({"ok": False, "error": str(e)}).encode())


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="SurroundPanner -> REAPER OSC bridge")
    ap.add_argument("--port", type=int, default=9000, help="web/bridge port (default 9000)")
    ap.add_argument("--host", default="127.0.0.1", help="bridge bind address")
    ap.add_argument("--reaper-host", default="127.0.0.1", help="REAPER OSC host")
    ap.add_argument("--reaper-port", type=int, default=8000, help="REAPER OSC listen port")
    args = ap.parse_args()

    Handler.sender = OSCSender(args.reaper_host, args.reaper_port)
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)

    print("=" * 60)
    print("  SurroundPanner bridge — tk Audio Services")
    print("=" * 60)
    print(f"  UI:      http://{args.host}:{args.port}/")
    print(f"  OSC ->   {args.reaper_host}:{args.reaper_port}  (set REAPER's local listen port to match)")
    print("  Press Ctrl-C to stop.")
    print("=" * 60, flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  stopped.")
        httpd.server_close()


if __name__ == "__main__":
    main()
