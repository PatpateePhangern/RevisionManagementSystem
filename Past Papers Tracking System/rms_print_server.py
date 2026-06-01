#!/usr/bin/env python3
"""
rms_print_server.exe — RMS LAN Print Receiver for Windows PC  v4.0
====================================================================
Run rms_print_server.exe on your Windows PC. It listens for PDF
payloads sent from the Mac RMS app.

SumatraPDF is bundled inside this exe — no extra downloads needed.

HOW TO TEST
-----------
  Open a browser on this Windows PC and go to:
      http://localhost:8999/
  You should see a green "Server is running" page.

Usage
-----
  Double-click rms_print_server.exe  (no installation needed)

  Find your LAN IP with:   ipconfig   (look for IPv4 Address)
  Then enter   <your-LAN-IP>:8999   in RMS → Settings → Windows Print Server.

Endpoints
---------
  GET  /            →  HTML status page
  GET  /status      →  {"ready": true}
  GET  /printers    →  ["Printer A", "Printer B"]
  POST /print-default  →  Silent print via bundled SumatraPDF
                           Header: X-Target-Printer: <name>  (optional)
  POST /print-manual   →  Opens print dialog via bundled SumatraPDF
"""

import json
import os
import sys
import time
import atexit
import shutil
import tempfile
import traceback
import subprocess

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

# ── Configuration ─────────────────────────────────────────────────────────────

BIND_HOST      = ""          # "" = all interfaces
BIND_PORT      = 8999
SAVE_DIRECTORY = r"C:\TempPrint"
OUT_PATH       = os.path.join(SAVE_DIRECTORY, "incoming.pdf")

# ── Bundled SumatraPDF extraction ─────────────────────────────────────────────
# When running as a PyInstaller exe, SumatraPDF.exe is bundled as a data file.
# We extract it to a temp folder once at startup so it can be executed.

_SUMATRA_TEMP_DIR:  str | None = None
_SUMATRA_EXEC_PATH: str | None = None


def _setup_sumatra() -> str | None:
    """Extract bundled SumatraPDF.exe to a temp folder and return its path.

    Falls back to a system-installed SumatraPDF if the bundle is not found
    (e.g. when running the raw .py script during development).
    """
    global _SUMATRA_TEMP_DIR, _SUMATRA_EXEC_PATH

    # ── PyInstaller bundle path ───────────────────────────────────────────────
    if getattr(sys, "frozen", False):
        bundle_dir = sys._MEIPASS                        # type: ignore[attr-defined]
        bundled = os.path.join(bundle_dir, "SumatraPDF.exe")
        if os.path.exists(bundled):
            _SUMATRA_EXEC_PATH = bundled
            print(f"[Server] SumatraPDF: using bundled copy at {bundled}")
            return bundled
        print("[Server] WARNING: SumatraPDF.exe not found inside bundle.")

    # ── Development / fallback: search common install locations ──────────────
    candidates = [
        r"C:\Program Files\SumatraPDF\SumatraPDF.exe",
        r"C:\Program Files (x86)\SumatraPDF\SumatraPDF.exe",
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "SumatraPDF", "SumatraPDF.exe"),
        os.path.join(os.path.expanduser("~"), "Downloads", "SumatraPDF.exe"),
        os.path.join(os.path.expanduser("~"), "Desktop",   "SumatraPDF.exe"),
    ]
    for p in candidates:
        try:
            if os.path.exists(p):
                _SUMATRA_EXEC_PATH = p
                print(f"[Server] SumatraPDF: found system install at {p}")
                return p
        except Exception:
            pass

    # ── Registry fallback ─────────────────────────────────────────────────────
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\SumatraPDF.exe"
        )
        val, _ = winreg.QueryValueEx(key, "")
        winreg.CloseKey(key)
        if val and os.path.exists(val):
            _SUMATRA_EXEC_PATH = val
            print(f"[Server] SumatraPDF: found via registry at {val}")
            return val
    except Exception:
        pass

    print("[Server] ERROR: SumatraPDF not found. Printing will fall back to PowerShell.")
    return None


def get_sumatra() -> str | None:
    """Return the SumatraPDF executable path (cached after first call)."""
    return _SUMATRA_EXEC_PATH


# ── Printer enumeration ───────────────────────────────────────────────────────

def _enumerate_printers(win32print_module) -> list:
    flags = (win32print_module.PRINTER_ENUM_LOCAL |
             win32print_module.PRINTER_ENUM_CONNECTIONS)

    def _name(item):
        if isinstance(item, dict):
            return item.get("pPrinterName", "")
        return item[0] if len(item) > 2 else ""

    for level in (4, 5, 2, 1):
        try:
            raw   = win32print_module.EnumPrinters(flags, None, level)
            names = [_name(p) for p in raw if _name(p)]
            if names or level == 1:
                return names
        except Exception as exc:
            print(f"[Server] PRINTERS level {level} failed ({exc}), trying next…")
    return []


# ── HTTP handler ──────────────────────────────────────────────────────────────

class PrintHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[Server] {self.address_string()} — {fmt % args}")

    # ── Response helpers ──────────────────────────────────────────────────────

    def _send_json(self, body: bytes, status: int = 200):
        self.send_response(status)
        self.send_header("Content-Type",   "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: bytes, status: int = 200):
        self.send_response(status)
        self.send_header("Content-Type",   "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _ok(self):
        self.send_response(200)
        self.end_headers()

    def _error(self, status: int, message: str):
        self._send_json(json.dumps({"error": message}).encode(), status=status)

    # ── GET ───────────────────────────────────────────────────────────────────

    def do_GET(self):
        try:
            if   self.path == "/":         self._handle_root()
            elif self.path == "/status":   self._send_json(b'{"ready": true}')
            elif self.path == "/printers": self._handle_printers()
            else:                          self._error(404, f"Unknown path: {self.path}")
        except Exception:
            print(f"[Server] ERROR in GET {self.path}:\n{traceback.format_exc()}")
            self._error(500, "Internal server error")

    def _handle_root(self):
        sumatra_path = get_sumatra()
        sumatra_ok   = "✅ Bundled SumatraPDF is ready" if sumatra_path else "⚠️ SumatraPDF not found"
        try:
            import win32print
            py32_status = "✅ pywin32 is available (printer enumeration ready)"
        except ImportError:
            py32_status = "⚠️ pywin32 not available — printer list will be empty"

        html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>rms_print_server v4.0</title>
<style>
  body {{ font-family: Segoe UI, Arial, sans-serif; max-width: 640px;
          margin: 40px auto; padding: 0 20px; color: #222; }}
  h1 {{ color: #1a7f37; }}
  code {{ background: #f3f4f6; padding: 2px 6px; border-radius: 4px; }}
  table {{ border-collapse: collapse; width: 100%; margin: 16px 0; }}
  td, th {{ border: 1px solid #d1d5db; padding: 8px 12px; text-align: left; }}
  th {{ background: #f9fafb; }}
</style></head><body>
<h1>✅ rms_print_server v4.0 is running</h1>
<p>{sumatra_ok}</p>
<p>{py32_status}</p>
<p>To stop the server: close this window or press <strong>Ctrl+C</strong>.</p>
<h2>Endpoints</h2>
<table>
<tr><th>Method</th><th>Path</th><th>Description</th></tr>
<tr><td>GET</td> <td><a href="/">/</a></td>         <td>This page</td></tr>
<tr><td>GET</td> <td><a href="/status">/status</a></td>   <td>Connectivity check (used by Mac app)</td></tr>
<tr><td>GET</td> <td><a href="/printers">/printers</a></td> <td>List installed printers</td></tr>
<tr><td>POST</td><td>/print-default</td>            <td>Silent print (X-Target-Printer header)</td></tr>
<tr><td>POST</td><td>/print-manual</td>             <td>Opens SumatraPDF print dialog</td></tr>
</table>
<h2>Save location</h2>
<p>Received PDFs are saved to <code>{SAVE_DIRECTORY}</code></p>
</body></html>""".encode("utf-8")
        self._send_html(html)

    def _handle_printers(self):
        try:
            import win32print
            names = _enumerate_printers(win32print)
            self._send_json(json.dumps(names).encode())
            print(f"[Server] PRINTERS — returned {len(names)}: {names}")
        except ImportError:
            self._send_json(b'[]')
        except Exception:
            print(f"[Server] PRINTERS error:\n{traceback.format_exc()}")
            self._send_json(b'[]')

    # ── POST ──────────────────────────────────────────────────────────────────

    def do_POST(self):
        try:
            if self.path not in ("/print-default", "/print-manual"):
                self._error(404, f"Unknown path: {self.path}")
                return
            if not self._save_pdf():
                return
            if self.path == "/print-default":
                self._handle_express()
            else:
                self._handle_manual()
        except Exception:
            print(f"[Server] UNHANDLED ERROR in POST {self.path}:\n{traceback.format_exc()}")
            try:
                self._error(500, "Server error — see console for details")
            except Exception:
                pass

    # ── Save incoming PDF ─────────────────────────────────────────────────────

    def _save_pdf(self) -> bool:
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if not length:
            self._error(400, "Missing or zero Content-Length")
            return False
        try:
            pdf_data = self.rfile.read(length)
            os.makedirs(SAVE_DIRECTORY, exist_ok=True)
            with open(OUT_PATH, "wb") as f:
                f.write(pdf_data)
            print(f"[Server] Saved {len(pdf_data):,} bytes → {OUT_PATH}")
            return True
        except Exception:
            print(f"[Server] ERROR saving PDF:\n{traceback.format_exc()}")
            self._error(500, f"Could not save PDF to {SAVE_DIRECTORY}")
            return False

    # ── Express print (silent) ────────────────────────────────────────────────

    def _handle_express(self):
        target_printer = self.headers.get("X-Target-Printer", "").strip()
        sumatra = get_sumatra()

        if sumatra:
            if self._print_silent(sumatra, target_printer):
                self._ok()
                return

        # Fallback: PowerShell with system default printer
        print("[Server] EXPRESS: falling back to PowerShell (no printer selection)")
        self._try_powershell_fallback()
        self._ok()

    def _print_silent(self, sumatra: str, target_printer: str) -> bool:
        """Silent print via SumatraPDF -print-to / -print-to-default."""
        try:
            if target_printer:
                cmd = [sumatra, "-print-to", target_printer, "-silent", OUT_PATH]
                print(f"[Server] EXPRESS: SumatraPDF → printer {target_printer!r}")
            else:
                cmd = [sumatra, "-print-to-default", "-silent", OUT_PATH]
                print("[Server] EXPRESS: SumatraPDF → system default printer")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                print(f"[Server] EXPRESS: SumatraPDF error: {result.stderr.strip()}")
                return False
            print("[Server] EXPRESS: spool submitted ✓")
            return True
        except subprocess.TimeoutExpired:
            print("[Server] EXPRESS: SumatraPDF timed out")
            return False
        except Exception:
            print(f"[Server] EXPRESS: SumatraPDF failed:\n{traceback.format_exc()}")
            return False

    def _try_powershell_fallback(self):
        """Last-resort print via PowerShell — system default printer only."""
        try:
            result = subprocess.run(
                ["powershell", "-Command",
                 f'Start-Process -FilePath "{OUT_PATH}" -Verb Print'],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                print(f"[Server] POWERSHELL error: {result.stderr.strip()}")
            else:
                print("[Server] POWERSHELL: spool submitted ✓")
        except Exception:
            print(f"[Server] POWERSHELL failed:\n{traceback.format_exc()}")

    # ── Manual print (shows dialog) ───────────────────────────────────────────

    def _handle_manual(self):
        """Open the PDF in SumatraPDF with the print dialog pre-opened."""
        sumatra = get_sumatra()

        if sumatra:
            try:
                # -print-dialog opens SumatraPDF's native print dialog
                subprocess.Popen([sumatra, "-print-dialog", OUT_PATH])
                print("[Server] MANUAL: opened SumatraPDF print dialog ✓")
                self._ok()
                return
            except Exception:
                print(f"[Server] MANUAL: SumatraPDF failed:\n{traceback.format_exc()}")

        # Fallback: open with system default viewer
        try:
            os.startfile(OUT_PATH, "print")
            print("[Server] MANUAL: opened with system default viewer (print verb)")
        except Exception:
            print(f"[Server] MANUAL: os.startfile failed:\n{traceback.format_exc()}")
            self._error(500, "Could not open PDF for printing")
            return

        self._ok()


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":

    # Extract / locate SumatraPDF before starting the server
    _setup_sumatra()

    try:
        server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), PrintHandler)
    except OSError as exc:
        print(f"\n[ERROR] Cannot bind to port {BIND_PORT}: {exc}")
        print(f"  Another program may already be using port {BIND_PORT}.")
        print(f"  Close it, or change BIND_PORT at the top of this file.")
        sys.exit(1)

    sumatra_status = f"✓ Bundled SumatraPDF ready" if get_sumatra() else "✗ SumatraPDF not found"

    print("=" * 65)
    print("  rms_print_server.exe  —  RMS LAN Print Receiver  v4.0")
    print("=" * 65)
    print(f"  Listening on  : :{BIND_PORT}  (all interfaces)")
    print(f"  Save path     : {SAVE_DIRECTORY}")
    print(f"  {sumatra_status}")
    print()
    print("  Verify the server is running:")
    print(f"    Open a browser on this PC → http://localhost:{BIND_PORT}/")
    print()
    print("  Routes:")
    print(f"    GET  /           — Status page")
    print(f"    GET  /status     — Connectivity check")
    print(f"    GET  /printers   — List installed printers")
    print(f"    POST /print-default  — Silent spool (X-Target-Printer header)")
    print(f"    POST /print-manual   — Opens print dialog")
    print()
    print("  Press Ctrl+C to stop.")
    print("=" * 65)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[Server] Stopped.")
