#!/usr/bin/env python3
"""
Galileo Loader
==============
Created by tk Audio Services.
A small, modern replacement for the old "TXTtoG616" MaxMSP standalone.

It reads a WaveCapture biquad-list text export (Live-Capture / EQ-Capture /
FIR-Capture) and sends the parametric filters to a Meyer Sound Galileo as OSC
messages over UDP -- the same thing the original did, but as a few-KB
cross-platform Python app instead of a 10 MB Windows Max runtime.

HOW IT RUNS
  Default (no arguments):  starts a tiny LOCAL web server and opens the UI in
                           your browser. The Python process does the UDP send,
                           so nothing needs installing -- not even Tkinter.

      python3 galileo_loader.py

  Command line (scripting):
      python3 galileo_loader.py "Live Room EQ.txt" --ip 192.168.1.171 --outputs 1,2,6
      (add --send to actually transmit; without it you get a dry-run preview)

The local web page only talks to this script on 127.0.0.1, and a one-time
random token guards the /send endpoint.

------------------------------------------------------------------------------
WHAT IT SENDS (per PEQ filter, three OSC messages):
    /Output/<out>/EQ/<band>/Parametric/Frequency   <float Hz>
    /Output/<out>/EQ/<band>/Parametric/Bandwidth   <float octaves>
    /Output/<out>/EQ/<band>/Parametric/Gain        <float dB>

SAFETY: this changes EQ on a live loudspeaker processor. It never sends until
you press Send (browser) or pass --send (CLI). Verify on a spare output before
trusting it in a show.
------------------------------------------------------------------------------
Standard library only. Tested: OSC output is byte-for-byte identical to python-osc.
"""

import sys
import os
import re
import socket
import struct
import argparse
import json
import platform
import subprocess
import ipaddress
import concurrent.futures
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_IP = "192.168.1.171"
DEFAULT_PORT = 15006
ADDRESS_TEMPLATE = "/Output/{out}/EQ/{band}/Parametric/{param}"
MAX_OUTPUTS = 16            # Galileo 616 = 6 in / 16 out

_TOKEN = ""
_PAGE = ""
def _resource_dir():
    # works when run as a script and when frozen into a PyInstaller .exe
    if getattr(sys, "frozen", False):
        return getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        return os.getcwd()


LOGO_PATH = os.path.join(_resource_dir(), "tk_logo.png")


# ----------------------------------------------------------------------------
# OSC encoding (verified byte-for-byte against the python-osc library)
# ----------------------------------------------------------------------------
def osc_string(s):
    b = s.encode("ascii") + b"\x00"
    pad = (4 - len(b) % 4) % 4
    return b + b"\x00" * pad


def osc_message(address, value):
    return osc_string(address) + osc_string(",f") + struct.pack(">f", float(value))


# ----------------------------------------------------------------------------
# Parse / build / send
# ----------------------------------------------------------------------------
def _columns_from_simple(rows):
    """Given headerless rows of three numbers, work out which column is
    frequency, gain and bandwidth (order-independent), and build PEQ dicts.
    Frequency is the column with the largest values; gain is the column that
    goes negative; bandwidth is the remaining (small, positive) column."""
    import statistics
    cols = list(zip(*rows))
    med = [statistics.median(abs(v) for v in c) for c in cols]
    freq_i = max(range(3), key=lambda i: med[i])
    a, b = [i for i in range(3) if i != freq_i]
    neg = [any(v < 0 for v in cols[i]) for i in range(3)]
    if neg[a] and not neg[b]:
        gain_i, bw_i = a, b
    elif neg[b] and not neg[a]:
        gain_i, bw_i = b, a
    else:
        gain_i, bw_i = (a, b) if med[a] >= med[b] else (b, a)
    filters = [{"n": i + 1, "type": "PEQ", "freq": r[freq_i], "bw": r[bw_i], "gain": r[gain_i]}
               for i, r in enumerate(rows)]
    order = ["?", "?", "?"]
    order[freq_i], order[gain_i], order[bw_i] = "Freq", "Gain", "BW"
    return filters, " / ".join(order)


def parse_biquad(text):
    """Return (meta, filters, warnings). Accepts two layouts:
       1) a WaveCapture biquad list  (tab/space, header, BIQ# Type Freq BW Gain ...)
       2) a headerless list of three numbers per line (comma or space), order
          auto-detected -- e.g. the original Galileo tool's gain,bandwidth,frequency."""
    meta, structured, simple, warnings = {}, [], [], []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or set(line) <= set("-= "):
            continue
        low = line.lower()
        if ":" in line and not (line[0].isdigit() or line[0] in "+-."):
            if "parametric eq type" in low:
                meta["eq_type"] = line.split(":", 1)[1].strip()
            elif "bandwidth type" in low:
                meta["bw_type"] = line.split(":", 1)[1].strip()
            continue
        toks = [t for t in re.split(r"[,\s]+", line) if t]
        if len(toks) >= 5 and toks[0].isdigit() and re.match(r"^[A-Za-z]", toks[1]):
            try:
                structured.append({"n": int(toks[0]), "type": toks[1], "freq": float(toks[2]),
                                   "bw": float(toks[3]), "gain": float(toks[4])})
                continue
            except ValueError:
                pass
        try:
            nums = [float(t) for t in toks]
        except ValueError:
            continue
        if len(nums) == 3:
            simple.append(nums)

    if structured:
        filters = structured
    elif simple:
        filters, order = _columns_from_simple(simple)
        warnings.append("Headerless list detected -- columns read as %s. Check the preview." % order)
    else:
        filters = []
        warnings.append("No filter rows found -- expected a WaveCapture biquad list, or rows of "
                        "frequency / gain / bandwidth.")

    bw_type = meta.get("bw_type", "")
    if bw_type and "oct" not in bw_type.lower():
        warnings.append("Bandwidth type is '%s', not Octaves -- the Galileo expects octaves." % bw_type)
    non_peq = sorted({f["type"] for f in filters if f["type"].upper() != "PEQ"})
    if non_peq:
        warnings.append("Skipping non-PEQ type(s): %s -- only PEQ maps to the Parametric path."
                        % ", ".join(non_peq))
    return meta, filters, warnings


def peq_filters(filters):
    return [f for f in filters if f["type"].upper() == "PEQ"]


def build_messages(filters, outputs, start_band=1):
    msgs = []
    for out in outputs:
        for idx, f in enumerate(peq_filters(filters)):
            band = start_band + idx
            base = dict(out=out, band=band)
            msgs.append((ADDRESS_TEMPLATE.format(param="Frequency", **base), f["freq"]))
            msgs.append((ADDRESS_TEMPLATE.format(param="Bandwidth", **base), f["bw"]))
            msgs.append((ADDRESS_TEMPLATE.format(param="Gain", **base), f["gain"]))
    return msgs


def send_messages(messages, ip, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        for addr, val in messages:
            sock.sendto(osc_message(addr, val), (ip, port))
    finally:
        sock.close()
    return len(messages)


def messages_as_text(messages):
    return "\n".join("%s   %g" % (a, v) for a, v in messages)


# ----------------------------------------------------------------------------
# LAN discovery
# Compass finds Galileos over mDNS, and they're DHCP by default (floating IPs),
# so this lists live hosts on your subnet and flags ones that look like Meyer
# devices, letting you click to fill the IP instead of typing it.
# ----------------------------------------------------------------------------
GALILEO_HINTS = ("galileo", "galaxy", "meyer", "compass")
# Meyer Sound IEEE MAC prefixes. The first is Meyer's classic 24-bit OUI; the
# second is their 28-bit IAB allocation under the shared 00:50:C2 pool (newer
# units). Extend this tuple whenever a new Galileo turns up with a MAC the scan
# doesn't flag.
MEYER_PREFIXES = ("00:1c:ab", "00:50:c2:21:6")


def _local_ipv4():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))     # no data sent; just learns the chosen interface
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def _no_window():
    # avoid a flashing console window for subprocess calls on Windows
    if platform.system() == "Windows":
        return {"creationflags": 0x08000000}   # CREATE_NO_WINDOW
    return {}


def _provoke_arp(net):
    """Send a tiny UDP packet to every address in the subnet so the OS has to
    ARP-resolve each one, populating the ARP cache. No reply is needed. This
    works the same on Windows, macOS and Linux and needs no 'ping' binary."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        for ip in net.hosts():
            try:
                s.sendto(b"\x00", (str(ip), 9))     # port 9 = discard
            except Exception:
                pass
    finally:
        s.close()


def _arp_table():
    """Return {ip: mac} from the OS ARP / neighbour table on Windows, macOS or
    Linux. Parses the BSD '(ip) at mac', Windows 'ip   mac   type' and Linux
    'ip dev .. lladdr mac' formats with one generic matcher."""
    ip_re = re.compile(r"(\d{1,3}(?:\.\d{1,3}){3})")
    mac_re = re.compile(r"([0-9a-fA-F]{1,2}(?:[:-][0-9a-fA-F]{1,2}){5})")
    out = ""
    for cmd in (["arp", "-a"], ["ip", "neigh", "show"]):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=5, **_no_window())
            out = res.stdout or ""
            if out.strip():
                break
        except Exception:
            continue
    table = {}
    for line in out.splitlines():
        ipm = ip_re.search(line)
        macm = mac_re.search(line)
        if not (ipm and macm):
            continue
        mac = ":".join(p.zfill(2) for p in re.split(r"[:-]", macm.group(1))).lower()
        if mac in ("00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff"):
            continue
        table[ipm.group(1)] = mac
    return table


def _rdns(ip):
    try:
        return socket.gethostbyaddr(ip)[0]      # on macOS this also consults mDNS (.local)
    except Exception:
        return ""


def scan_network(settle=1.3):
    """Find live hosts on the local /24 and flag likely Meyer devices.
    Sends a UDP probe to each subnet address to populate the ARP table, reads it,
    reverse-resolves names, and returns {subnet, mine, hosts:[{ip,name,mac,likely}]}.
    Cross-platform: Windows, macOS and Linux."""
    import time
    mine = _local_ipv4()
    try:
        net = ipaddress.ip_network(mine + "/24", strict=False)
    except Exception:
        return {"subnet": mine, "mine": mine, "hosts": [], "note": "Could not determine subnet."}

    _provoke_arp(net)
    time.sleep(settle)              # let the ARP replies land
    arp = _arp_table()

    live = set()
    for ip in arp:
        try:
            if ipaddress.ip_address(ip) in net:
                live.add(ip)
        except Exception:
            pass
    live.discard(mine)

    names = {}
    if live:
        with concurrent.futures.ThreadPoolExecutor(max_workers=40) as ex:
            futs = {ex.submit(_rdns, ip): ip for ip in live}
            done, not_done = concurrent.futures.wait(futs, timeout=3)
            for f in done:
                try:
                    names[futs[f]] = f.result()
                except Exception:
                    names[futs[f]] = ""
            for f in not_done:
                f.cancel()

    hosts = []
    for ip in sorted(live, key=lambda x: tuple(int(o) for o in x.split("."))):
        name = names.get(ip, "") or ""
        mac = arp.get(ip, "")
        if any(mac.lower().startswith(p) for p in MEYER_PREFIXES):
            match = "Meyer OUI"
        elif any(k in name.lower() for k in GALILEO_HINTS):
            match = "name match"
        else:
            match = ""
        hosts.append({"ip": ip, "name": name, "mac": mac, "match": match})
    return {"subnet": str(net), "mine": mine, "hosts": hosts}


# ----------------------------------------------------------------------------
# Local web app
# ----------------------------------------------------------------------------
def build_page(token):
    html = PAGE_TEMPLATE
    html = html.replace("__TOKEN__", token)
    html = html.replace("__IP__", DEFAULT_IP)
    html = html.replace("__PORT__", str(DEFAULT_PORT))
    html = html.replace("__MAXOUT__", str(MAX_OUTPUTS))
    return html


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass  # keep the terminal quiet

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", ""):
            body = _PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == "/logo.png":
            try:
                with open(LOGO_PATH, "rb") as fh:
                    body = fh.read()
            except OSError:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self):
        path = self.path.split("?")[0]
        if path not in ("/send", "/scan"):
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            self._json(400, {"error": "bad request"})
            return
        if data.get("token") != _TOKEN:
            self._json(403, {"error": "bad token"})
            return
        if path == "/scan":
            try:
                self._json(200, scan_network())
            except Exception as e:
                self._json(500, {"error": str(e)})
            return
        ip = str(data.get("ip", "")).strip()
        try:
            port = int(data.get("port"))
        except Exception:
            self._json(400, {"error": "port must be a number"})
            return
        try:
            msgs = [(str(a), float(v)) for a, v in data.get("messages", [])]
        except Exception:
            self._json(400, {"error": "malformed messages"})
            return
        if not ip or not msgs:
            self._json(400, {"error": "nothing to send (set an IP and pick an output)"})
            return
        try:
            n = send_messages(msgs, ip, port)
        except OSError as e:
            self._json(500, {"error": str(e)})
            return
        self._json(200, {"sent": n, "ip": ip, "port": port})


def run_webapp(open_browser=True):
    global _TOKEN, _PAGE
    import secrets
    _TOKEN = secrets.token_urlsafe(16)
    _PAGE = build_page(_TOKEN)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    url = "http://127.0.0.1:%d/" % port
    print("\n  Galileo Loader  ·  created by tk Audio Services")
    print("  Running. Open this in your browser:  %s" % url)
    print("  (Leave this window open while you use it. Press Ctrl-C here when you're done.)\n")
    if open_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")
    return 0


# ----------------------------------------------------------------------------
# Command line
# ----------------------------------------------------------------------------
def run_cli(argv):
    ap = argparse.ArgumentParser(
        prog="galileo_loader.py",
        description="Send a WaveCapture biquad list to a Meyer Galileo over OSC/UDP.")
    ap.add_argument("file", help="WaveCapture biquad-list .txt export")
    ap.add_argument("--ip", default=DEFAULT_IP, help="Galileo/Compass IP (default %(default)s)")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT, help="UDP port (default %(default)s)")
    ap.add_argument("--outputs", default="6", help="comma list, e.g. 1,2,6 (default %(default)s)")
    ap.add_argument("--start-band", type=int, default=1, help="EQ band # for the first filter")
    ap.add_argument("--send", action="store_true", help="actually transmit (default: dry-run preview)")
    args = ap.parse_args(argv)

    try:
        text = open(args.file, "r", encoding="utf-8", errors="replace").read()
    except OSError as e:
        ap.error("cannot read file: %s" % e)
    meta, filters, warnings = parse_biquad(text)
    try:
        outputs = [int(x) for x in args.outputs.split(",") if x.strip()]
    except ValueError:
        ap.error("--outputs must be a comma list of integers, e.g. 1,2,6")
    msgs = build_messages(filters, outputs, args.start_band)

    print("Galileo Loader  ·  tk Audio Services")
    print("File        : %s" % os.path.basename(args.file))
    if meta:
        print("EQ type     : %s   BW type: %s" % (meta.get("eq_type", "?"), meta.get("bw_type", "?")))
    print("PEQ filters : %d" % len(peq_filters(filters)))
    print("Outputs     : %s" % ", ".join(map(str, outputs)))
    print("Target      : %s:%d" % (args.ip, args.port))
    print("OSC messages: %d" % len(msgs))
    for w in warnings:
        print("  ! %s" % w)
    print("-" * 60)
    print(messages_as_text(msgs))
    print("-" * 60)
    if not msgs:
        print("Nothing to send.")
        return 1
    if args.send:
        print("SENT %d OSC messages to %s:%d" % (send_messages(msgs, args.ip, args.port), args.ip, args.port))
    else:
        print("Dry run (no network). Re-run with --send to transmit.")
    return 0


def main():
    if len(sys.argv) > 1:
        return run_cli(sys.argv[1:])
    return run_webapp()


# ----------------------------------------------------------------------------
# Embedded web UI  (parse + preview happen in the browser; Python does the send)
# ----------------------------------------------------------------------------
PAGE_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Galileo Loader</title>
<style>
  :root{--ink:#161a20;--muted:#6b7480;--paper:#f6f7f9;--card:#fff;--line:#e3e6ea;
        --accent:#0e8a9b;--accent2:#e08a2b;--good:#1f9d6b;--warn:#c2521a;--info:#1f6fb2;
        --mono:ui-monospace,Menlo,Consolas,monospace;--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
  *{box-sizing:border-box}
  body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.5}
  .wrap{max-width:880px;margin:0 auto;padding:22px 20px 60px}
  header h1{font-size:23px;margin:0 0 2px}
  header p{margin:0 0 16px;color:var(--muted);font-size:14px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:12px 0}
  .card h2{font-size:13px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);margin:0 0 10px}
  #drop{border:2px dashed #c7ccd3;border-radius:12px;padding:22px;text-align:center;color:var(--muted);cursor:pointer;transition:.15s}
  #drop.hover{border-color:var(--accent);background:#f0fbfc;color:var(--ink)}
  #drop b{color:var(--accent)}
  .row{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-end}
  .fld{display:flex;flex-direction:column;gap:4px}
  .fld label{font-size:12px;color:var(--muted)}
  input[type=text],input[type=number]{font:inherit;padding:7px 9px;border:1px solid var(--line);border-radius:8px;background:#fff}
  input[type=text].ip{width:160px}.num{width:90px}.bnd{width:70px}
  .chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:4px}
  .chip{border:1px solid var(--line);background:#fff;border-radius:8px;padding:6px 0;width:42px;text-align:center;cursor:pointer;font-variant-numeric:tabular-nums;user-select:none}
  .chip.on{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
  .mini{font-size:12px;color:var(--accent);background:none;border:0;cursor:pointer;padding:4px 6px}
  .info{font-size:13.5px;color:var(--info)}
  .warn{font-size:13px;color:var(--warn);background:#fdf1e7;border:1px solid #f1d4bf;border-radius:8px;padding:8px 10px;margin-top:8px}
  pre#preview{background:#0f1115;color:#cfe6e9;border-radius:10px;padding:12px;max-height:300px;overflow:auto;font-family:var(--mono);font-size:12.5px;margin:0}
  .actions{display:flex;gap:10px;align-items:center;margin-top:12px}
  button.primary{background:var(--accent);color:#fff;border:0;border-radius:9px;padding:11px 20px;font:inherit;font-weight:600;cursor:pointer}
  button.primary:disabled{background:#b9c2c9;cursor:not-allowed}
  button.ghost{background:#fff;border:1px solid var(--line);border-radius:9px;padding:10px 16px;font:inherit;cursor:pointer}
  #status{margin-left:auto;font-size:13px;color:var(--muted)}
  .safe{font-size:12.5px;color:var(--muted);background:#fbf7ef;border:1px solid #ece3cf;border-radius:8px;padding:9px 11px;margin-top:10px}
  .count{font-variant-numeric:tabular-nums;font-weight:600}
  .logo{height:42px;width:auto;display:block;margin-bottom:12px}
  .foot{display:flex;align-items:center;gap:12px;margin-top:26px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12.5px}
  .foot img{height:24px;width:auto;opacity:.9}
  .scanres{margin-top:12px}
  .scanres .hosthead{font-size:12.5px;color:var(--muted);margin-bottom:6px}
  .host{display:flex;align-items:center;gap:10px;padding:7px 10px;border:1px solid var(--line);border-radius:8px;margin-bottom:5px;cursor:pointer;font-size:13px}
  .host:hover{border-color:var(--accent);background:#f0fbfc}
  .host b{font-variant-numeric:tabular-nums;min-width:108px}
  .host code{font-family:var(--mono);font-size:11.5px;color:var(--muted)}
  .host em{margin-left:auto;font-style:normal;font-size:11px;font-weight:700;color:#fff;background:var(--good);padding:2px 8px;border-radius:20px}
  .host.likely{border-color:var(--good);background:#f0fbf5}
  .galtog{cursor:pointer;user-select:none}
  .galtog input{vertical-align:-1px}
  #eqcanvas{width:100%;height:200px;display:block}
</style></head>
<body><div class="wrap">
  <header>
    <img src="/logo.png" alt="tk Audio Services" class="logo" onerror="this.style.display='none'">
    <h1>Galileo Loader</h1>
    <p>Send a WaveCapture biquad list to a Meyer Galileo over OSC. Preview here, then send.</p>
  </header>

  <div class="card">
    <h2>1 · Biquad list</h2>
    <div id="drop">Drop a <b>biquad list .txt</b> here, or <b>click to choose</b> &nbsp;·&nbsp; or paste below
      <input id="file" type="file" accept=".txt,text/plain" hidden>
    </div>
    <textarea id="paste" placeholder="…or paste the exported biquad list text here" style="width:100%;height:0;opacity:0;position:absolute;left:-9999px"></textarea>
    <div id="meta" class="info" style="margin-top:10px"></div>
    <div id="warns"></div>
  </div>

  <div class="card">
    <h2>2 · Galileo target</h2>
    <div class="row">
      <div class="fld"><label>IP address</label><input id="ip" class="ip" type="text" value="__IP__"></div>
      <div class="fld"><label>UDP port</label><input id="port" class="num" type="number" value="__PORT__"></div>
      <div class="fld"><label>First EQ band #</label><input id="band" class="bnd" type="number" value="1" min="1"></div>
      <div class="fld"><label>&nbsp;</label><button class="ghost" id="scanBtn" type="button">🔍 Find on network</button></div>
    </div>
    <div id="scanres" class="scanres"></div>
    <div style="margin-top:12px">
      <label style="font-size:12px;color:var(--muted)">Send to outputs</label>
      <div id="chips" class="chips"></div>
      <button class="mini" id="allBtn">All</button><button class="mini" id="noneBtn">None</button>
    </div>
  </div>

  <div class="card" id="eqcard" style="display:none">
    <h2>3 · EQ response <span class="count" id="eqsub"></span></h2>
    <canvas id="eqcanvas"></canvas>
  </div>

  <div class="card">
    <h2>4 · OSC preview <span id="pcount" class="count"></span></h2>
    <pre id="preview">Load a file and pick at least one output…</pre>
    <div class="actions">
      <button class="ghost" id="saveBtn">Save OSC list…</button>
      <button class="primary" id="sendBtn" disabled>Send to Galileo</button>
      <span id="status"></span>
    </div>
    <div class="safe">⚠ This changes EQ on a <b>live</b> system — verify on a spare output before a show.</div>
  </div>

  <footer class="foot">
    <img src="/logo.png" alt="" onerror="this.style.display='none'">
    <span>Created by <b>tk Audio Services</b></span>
  </footer>
</div>
<script>
const TOKEN="__TOKEN__", MAXOUT=__MAXOUT__;
let FILTERS=[], NAME="galileo";
const $=id=>document.getElementById(id);
const outs=new Set();

function columnsFromSimple(rows){
  const med=i=>{const a=rows.map(r=>Math.abs(r[i])).sort((x,y)=>x-y);const k=Math.floor(a.length/2);return a.length%2?a[k]:(a[k-1]+a[k])/2;};
  const m=[med(0),med(1),med(2)];
  let freq=0; if(m[1]>m[freq])freq=1; if(m[2]>m[freq])freq=2;
  const o=[0,1,2].filter(i=>i!==freq);
  const neg=i=>rows.some(r=>r[i]<0);
  let gain,bw;
  if(neg(o[0])&&!neg(o[1])){gain=o[0];bw=o[1];}
  else if(neg(o[1])&&!neg(o[0])){gain=o[1];bw=o[0];}
  else if(m[o[0]]>=m[o[1]]){gain=o[0];bw=o[1];}
  else {gain=o[1];bw=o[0];}
  const filters=rows.map((r,i)=>({n:i+1,type:"PEQ",freq:r[freq],bw:r[bw],gain:r[gain]}));
  const order=["?","?","?"]; order[freq]="Freq"; order[gain]="Gain"; order[bw]="BW";
  return {filters,order:order.join(" / ")};
}
function parseBiquad(text){
  const meta={},structured=[],simple=[],warnings=[];
  for(const raw of text.split(/\r?\n/)){
    const line=raw.trim();
    if(!line || /^[-=\s]+$/.test(line)) continue;
    const low=line.toLowerCase();
    if(line.includes(":") && !/^[0-9+\-.]/.test(line)){
      if(low.includes("parametric eq type")) meta.eq=line.split(":").slice(1).join(":").trim();
      else if(low.includes("bandwidth type")) meta.bw=line.split(":").slice(1).join(":").trim();
      continue;
    }
    const t=line.split(/[,\s]+/).filter(x=>x!=="");
    if(t.length>=5 && /^\d+$/.test(t[0]) && /^[A-Za-z]/.test(t[1])){
      const f=parseFloat(t[2]),b=parseFloat(t[3]),g=parseFloat(t[4]);
      if(![f,b,g].some(isNaN)){structured.push({n:+t[0],type:t[1],freq:f,bw:b,gain:g}); continue;}
    }
    const nums=t.map(Number);
    if(nums.length===3 && nums.every(v=>!isNaN(v))) simple.push(nums);
  }
  let filters=[];
  if(structured.length) filters=structured;
  else if(simple.length){
    const r=columnsFromSimple(simple); filters=r.filters;
    warnings.push("Headerless list detected — columns read as "+r.order+". Check the preview.");
  } else {
    warnings.push("No filter rows found — expected a WaveCapture biquad list, or rows of frequency / gain / bandwidth.");
  }
  if(meta.bw && !meta.bw.toLowerCase().includes("oct"))
    warnings.push("Bandwidth type is '"+meta.bw+"', not Octaves — the Galileo expects octaves.");
  const np=[...new Set(filters.filter(f=>f.type.toUpperCase()!=="PEQ").map(f=>f.type))];
  if(np.length) warnings.push("Skipping non-PEQ type(s): "+np.join(", ")+" — only PEQ maps to the Parametric path.");
  return {meta,filters,warnings};
}
function buildMessages(){
  const start=parseInt($("band").value)||1, peqs=FILTERS.filter(f=>f.type.toUpperCase()==="PEQ"), m=[];
  for(const o of [...outs].sort((a,b)=>a-b)) peqs.forEach((f,i)=>{
    const band=start+i, a="/Output/"+o+"/EQ/"+band+"/Parametric/";
    m.push([a+"Frequency",f.freq]); m.push([a+"Bandwidth",f.bw]); m.push([a+"Gain",f.gain]);
  });
  return m;
}
// --- EQ response curve (sum of RBJ peaking biquads) ---
function qFromBw(bw){ const b=Math.max(0.05,bw); return 1/(2*Math.sinh(Math.LN2/2*b)); }
function peakDb(f,f0,gain,bw,fs){
  const A=Math.pow(10,gain/40),w0=2*Math.PI*f0/fs,c=Math.cos(w0),s=Math.sin(w0),al=s/(2*qFromBw(bw));
  const b0=1+al*A,b1=-2*c,b2=1-al*A,a0=1+al/A,a1=-2*c,a2=1-al/A;
  const w=2*Math.PI*f/fs,cw=Math.cos(w),sw=Math.sin(w),c2=Math.cos(2*w),s2=Math.sin(2*w);
  const nr=b0+b1*cw+b2*c2,ni=-(b1*sw+b2*s2),dr=a0+a1*cw+a2*c2,di=-(a1*sw+a2*s2);
  return 10*Math.log10((nr*nr+ni*ni)/(dr*dr+di*di));
}
function drawEQ(){
  const card=$("eqcard"),cv=$("eqcanvas");
  const peqs=FILTERS.filter(f=>f.type.toUpperCase()==="PEQ");
  if(!peqs.length){card.style.display="none";return;}
  card.style.display="block";
  const dpr=window.devicePixelRatio||1, W=cv.clientWidth||700, H=200;
  cv.width=W*dpr; cv.height=H*dpr; const g=cv.getContext("2d"); g.setTransform(dpr,0,0,dpr,0,0);
  const fs=48000,f0=20,f1=20000,N=320,padL=32,padR=8,padT=8,padB=18,pw=W-padL-padR,ph=H-padT-padB;
  const xs=[],ys=[]; let ym=6;
  for(let i=0;i<N;i++){const f=f0*Math.pow(f1/f0,i/(N-1));let db=0;for(const p of peqs)db+=peakDb(f,p.freq,p.gain,p.bw,fs);xs.push(f);ys.push(db);ym=Math.max(ym,Math.abs(db));}
  ym=Math.ceil(ym/3)*3;
  const X=f=>padL+pw*Math.log(f/f0)/Math.log(f1/f0);
  const Y=db=>padT+ph*(1-(db+ym)/(2*ym));
  g.clearRect(0,0,W,H); g.font="10px -apple-system,system-ui,sans-serif"; g.textBaseline="middle"; g.lineWidth=1;
  [20,50,100,200,500,1000,2000,5000,10000,20000].forEach(f=>{const x=X(f);g.strokeStyle="#eef0f3";g.beginPath();g.moveTo(x,padT);g.lineTo(x,padT+ph);g.stroke();g.fillStyle="#9aa6b4";g.textAlign="center";g.fillText(f>=1000?(f/1000)+"k":f,x,H-8);});
  for(let db=-ym;db<=ym;db+=ym/2){const y=Y(db);g.strokeStyle=db===0?"#c7ccd3":"#f2f4f6";g.beginPath();g.moveTo(padL,y);g.lineTo(padL+pw,y);g.stroke();g.fillStyle="#9aa6b4";g.textAlign="right";g.fillText((db>0?"+":"")+db,padL-4,y);}
  g.beginPath();xs.forEach((f,i)=>{const x=X(f),y=Y(ys[i]);i?g.lineTo(x,y):g.moveTo(x,y);});
  g.lineTo(X(f1),Y(0));g.lineTo(X(f0),Y(0));g.closePath();g.fillStyle="rgba(14,138,155,0.10)";g.fill();
  g.beginPath();xs.forEach((f,i)=>{const x=X(f),y=Y(ys[i]);i?g.lineTo(x,y):g.moveTo(x,y);});g.strokeStyle="#0e8a9b";g.lineWidth=2;g.stroke();
  g.fillStyle="#e08a2b";peqs.forEach(p=>{let db=0;for(const q of peqs)db+=peakDb(p.freq,q.freq,q.gain,q.bw,fs);const x=X(p.freq),y=Y(db);g.beginPath();g.arc(x,y,2.6,0,2*Math.PI);g.fill();});
  $("eqsub").textContent="· "+peqs.length+" bands, ±"+ym+" dB";
}
function refresh(){
  const m=buildMessages();
  $("preview").textContent = m.length ? m.map(x=>x[0]+"   "+x[1]).join("\n")
                                      : "Load a file and pick at least one output…";
  $("pcount").textContent = m.length ? "· "+m.length+" messages" : "";
  $("sendBtn").disabled = m.length===0;
  $("status").textContent = m.length ? ("outputs "+[...outs].sort((a,b)=>a-b).join(",")) : "";
}
function loadText(text,name){
  const r=parseBiquad(text); FILTERS=r.filters; if(name) NAME=name.replace(/\.[^.]*$/,"");
  const n=FILTERS.filter(f=>f.type.toUpperCase()==="PEQ").length;
  $("meta").textContent = n+" PEQ filter(s)"+(r.meta.eq?("   ·   EQ: "+r.meta.eq):"")+(r.meta.bw?("   ·   BW: "+r.meta.bw):"");
  $("warns").innerHTML = r.warnings.map(w=>'<div class="warn">'+w+'</div>').join("");
  refresh(); drawEQ();
}
// outputs chips
const chips=$("chips");
for(let i=1;i<=MAXOUT;i++){
  const c=document.createElement("div"); c.className="chip"; c.textContent=i; c.dataset.n=i;
  c.onclick=()=>{ if(outs.has(i)){outs.delete(i);c.classList.remove("on");} else {outs.add(i);c.classList.add("on");} refresh(); };
  chips.appendChild(c);
}
$("allBtn").onclick=()=>{outs.clear();document.querySelectorAll(".chip").forEach(c=>{outs.add(+c.dataset.n);c.classList.add("on");});refresh();};
$("noneBtn").onclick=()=>{outs.clear();document.querySelectorAll(".chip").forEach(c=>c.classList.remove("on"));refresh();};
["band","ip","port"].forEach(id=>$(id).addEventListener("input",refresh));
// file input + drag/drop + paste
const drop=$("drop");
drop.onclick=()=>$("file").click();
$("file").onchange=e=>{const f=e.target.files[0]; if(f){f.text().then(t=>loadText(t,f.name));}};
["dragenter","dragover"].forEach(ev=>drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.add("hover");}));
["dragleave","drop"].forEach(ev=>drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.remove("hover");}));
drop.addEventListener("drop",e=>{const f=e.dataTransfer.files[0]; if(f) f.text().then(t=>loadText(t,f.name));});
document.addEventListener("paste",e=>{const t=(e.clipboardData||window.clipboardData).getData("text"); if(t&&t.length>20) loadText(t,"pasted");});
window.addEventListener("resize",()=>{if(FILTERS.length)drawEQ();});
// save
$("saveBtn").onclick=()=>{
  const m=buildMessages(); if(!m.length) return;
  const blob=new Blob([m.map(x=>x[0]+"   "+x[1]).join("\n")+"\n"],{type:"text/plain"});
  const a=document.createElement("a"); a.href=URL.createObjectURL(blob); a.download=NAME+"_osc.txt"; a.click();
};
// send
$("sendBtn").onclick=async()=>{
  const m=buildMessages(); if(!m.length) return;
  const ip=$("ip").value.trim(), port=parseInt($("port").value);
  if(!confirm("Send "+m.length+" OSC messages to "+ip+":"+port+"?\n\nOutputs: "+[...outs].sort((a,b)=>a-b).join(", ")+"\n\nThis changes EQ on a LIVE system. Continue?")) return;
  $("status").textContent="Sending…"; $("sendBtn").disabled=true;
  try{
    const res=await fetch("/send",{method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({token:TOKEN,ip,port,messages:m})});
    const d=await res.json();
    if(d.error){$("status").textContent="Error: "+d.error;}
    else{$("status").textContent="✓ Sent "+d.sent+" messages to "+d.ip+":"+d.port;}
  }catch(err){$("status").textContent="Network error: "+err;}
  $("sendBtn").disabled=false;
};
// find galileos on the network
let lastScan=null, galOnly=true;
function escHtml(s){return (s||"").replace(/[<>&]/g,c=>({"<":"&lt;",">":"&gt;","&":"&amp;"}[c]));}
function renderScan(){
  const box=$("scanres"); if(!lastScan) return;
  const d=lastScan;
  if(d.error){box.innerHTML='<div class="hosthead">Scan error: '+d.error+'</div>';return;}
  if(!d.hosts || !d.hosts.length){
    box.innerHTML='<div class="hosthead">No devices found on '+(d.subnet||"your subnet")+'. Some gear stays quiet — you can still type the IP.</div>';return;
  }
  const gals=d.hosts.filter(h=>h.match);
  let show=(galOnly && gals.length)?gals:d.hosts;
  show=show.slice().sort((a,b)=>(b.match?1:0)-(a.match?1:0));
  const tog='<label class="galtog"><input type="checkbox" id="galOnly"'+(galOnly?' checked':'')+'> Galileos only</label>';
  const note=(galOnly && !gals.length)?' <span style="color:var(--warn)">— none matched, showing all</span>':'';
  const rows=show.map(h=>'<div class="host'+(h.match?' likely':'')+'" data-ip="'+h.ip+'"><b>'+h.ip+'</b><span>'+escHtml(h.name)+'</span>'+(h.mac?'<code>'+h.mac+'</code>':'')+(h.match?'<em>'+escHtml(h.match)+'</em>':'')+'</div>').join("");
  box.innerHTML='<div class="hosthead">Found '+d.hosts.length+' device(s) on '+d.subnet+' &nbsp; '+tog+note+'</div>'+rows;
  $("galOnly").onchange=e=>{galOnly=e.target.checked;renderScan();};
  box.querySelectorAll(".host").forEach(el=>el.onclick=()=>{$("ip").value=el.dataset.ip;refresh();box.querySelectorAll(".host").forEach(x=>x.style.outline="");el.style.outline="2px solid var(--accent)";});
}
$("scanBtn").onclick=async()=>{
  $("scanres").innerHTML='<div class="hosthead">Scanning your network… (a few seconds)</div>';
  $("scanBtn").disabled=true;
  try{
    const res=await fetch("/scan",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({token:TOKEN})});
    lastScan=await res.json(); renderScan();
  }catch(e){$("scanres").innerHTML='<div class="hosthead">Scan failed: '+e+'</div>';}
  $("scanBtn").disabled=false;
};
</script>
</body></html>
"""


if __name__ == "__main__":
    sys.exit(main() or 0)
