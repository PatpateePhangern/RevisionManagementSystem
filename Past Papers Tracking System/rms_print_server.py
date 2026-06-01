#!/usr/bin/env python3
"""
rms_print_server.exe — RMS LAN Print Receiver for Windows PC  v3.0
=======================================================================
Run rms_print_server.exe on your Windows PC. It listens for PDF payloads sent from
the Mac RMS app.

HOW TO TEST (you cannot type commands into this window)
-------------------------------------------------------
  Open a browser on this Windows PC and go to:
      http://localhost:8999/
  You should see a green "Server is running" page.

  From a SECOND Command Prompt window, you can also run:
      curl http://localhost:8999/status

Requirements
------------
  pip install pywin32          (needed for all routes; fallback exists without it)
  Python 3.7+

Usage
-----
  python rms_print_server.exe

  Find your LAN IP with:   ipconfig   (look for IPv4 Address)
  Then enter   <your-LAN-IP>:8999   in PaperTracker → Settings.

Endpoints
---------
  GET  /            →  HTML status page (open in browser to verify server is alive)
  GET  /status      →  {"ready": true}              (used by Mac app)
  GET  /printers    →  ["Printer A", "Printer B"]   (enumerate installed printers)
  POST /print-default  →  Silent spool via win32api.ShellExecute "printto"
                           Header: X-Target-Printer: <name>  (optional)
  POST /print-manual   →  Opens PDF in Brave Browser + Ctrl+Shift+P
"""

import json
import os
import sys
import time
import traceback
import subprocess

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

# ── Configuration ─────────────────────────────────────────────────────────────

BIND_HOST      = ""                         # "" = all interfaces (LAN + localhost)
BIND_PORT      = 8999
SAVE_DIRECTORY = r"C:\TempPrint"
OUT_PATH       = os.path.join(SAVE_DIRECTORY, "incoming.pdf")

# ── SumatraPDF helper ─────────────────────────────────────────────────────────

def _find_sumatra() -> str | None:
    """Return the path to SumatraPDF.exe if installed, else None.
    SumatraPDF does NOT need to be the default PDF viewer — it can be
    installed as a utility alongside Brave."""
    import os
    candidates = [
        r"C:\Program Files\SumatraPDF\SumatraPDF.exe",
        r"C:\Program Files (x86)\SumatraPDF\SumatraPDF.exe",
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "SumatraPDF", "SumatraPDF.exe"),
        os.path.join(os.environ.get("APPDATA", ""), "SumatraPDF", "SumatraPDF.exe"),
        # Portable installs — check Downloads and Desktop
        os.path.join(os.path.expanduser("~"), "Downloads", "SumatraPDF.exe"),
        os.path.join(os.path.expanduser("~"), "Desktop", "SumatraPDF.exe"),
    ]
    for path in candidates:
        try:
            if os.path.exists(path):
                return path
        except Exception:
            pass
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\SumatraPDF.exe"
        )
        val, _ = winreg.QueryValueEx(key, "")
        winreg.CloseKey(key)
        if val and os.path.exists(val):
            return val
    except Exception:
        pass
    return None


# ── Brave Browser helper ──────────────────────────────────────────────────────

def _find_brave() -> str | None:
    """Return the absolute path to brave.exe, or None if not found."""
    import os
    candidates = [
        r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
        r"C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe",
        os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
        os.path.join(os.environ.get("APPDATA", ""),
                     "..", "Local", "BraveSoftware", "Brave-Browser",
                     "Application", "brave.exe"),
    ]
    for path in candidates:
        try:
            if os.path.exists(path):
                return path
        except Exception:
            pass

    # Registry fallback
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe"
        )
        val, _ = winreg.QueryValueEx(key, "")
        winreg.CloseKey(key)
        if val and os.path.exists(val):
            return val
    except Exception:
        pass

    return None


# ── Printer enumeration helper ────────────────────────────────────────────────

def _enumerate_printers(win32print_module) -> list:
    """Return a list of printer name strings.

    Tries EnumPrinters at levels 4 → 5 → 2 → 1 in order so that a failing
    level doesn't crash the whole endpoint.  Handles both dict-style and
    tuple-style results returned by different pywin32 versions.
    """
    flags = (win32print_module.PRINTER_ENUM_LOCAL |
             win32print_module.PRINTER_ENUM_CONNECTIONS)

    def _name(item):
        if isinstance(item, dict):
            return item.get('pPrinterName', '')
        # Tuple layouts: level 4/5 → name is [0], level 1 → name is [2]
        if len(item) > 2:
            return item[0]
        return ''

    for level in (4, 5, 2, 1):
        try:
            raw   = win32print_module.EnumPrinters(flags, None, level)
            names = [_name(p) for p in raw if _name(p)]
            if names or level == 1:
                return names
        except Exception as exc:
            print(f"[Server] PRINTERS level {level} failed ({exc}), trying next level…")

    return []

# ── HTTP handler ──────────────────────────────────────────────────────────────

class AdvancedPrintHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):       # noqa: N802
        print(f"[Server] {self.address_string()} — {fmt % args}")

    # ── Low-level response helpers ────────────────────────────────────────────

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
        body = json.dumps({"error": message}).encode()
        self._send_json(body, status=status)

    # ── GET ───────────────────────────────────────────────────────────────────

    def do_GET(self):                        # noqa: N802
        try:
            if self.path == "/":
                self._handle_root()
            elif self.path == "/status":
                self._send_json(b'{"ready": true}')
            elif self.path == "/printers":
                self._handle_printers()
            else:
                self._error(404, f"Unknown path: {self.path}")
        except Exception:
            print(f"[Server] ERROR in GET {self.path}:\n{traceback.format_exc()}")
            self._error(500, "Internal server error — see console for details")

    def _handle_root(self):
        """Browser-friendly status page so users can verify the server is alive."""
        try:
            import win32print
            py32_status = "✅ pywin32 is installed"
        except ImportError:
            py32_status = "⚠️ pywin32 NOT installed — run: pip install pywin32"

        html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>rms_print_server v3.0</title>
<style>
  body {{ font-family: Segoe UI, Arial, sans-serif; max-width: 640px;
          margin: 40px auto; padding: 0 20px; color: #222; }}
  h1 {{ color: #1a7f37; }} .ok {{ color: #1a7f37; }} .warn {{ color: #b45309; }}
  code {{ background: #f3f4f6; padding: 2px 6px; border-radius: 4px; }}
  table {{ border-collapse: collapse; width: 100%; margin: 16px 0; }}
  td, th {{ border: 1px solid #d1d5db; padding: 8px 12px; text-align: left; }}
  th {{ background: #f9fafb; }}
</style></head><body>
<h1>✅ rms_print_server.exe v3.0 is running</h1>
<p>{py32_status}</p>
<p>This window is <strong>not interactive</strong> — you cannot type commands here.<br>
   To stop the server, close this window or press <strong>Ctrl+C</strong>.</p>
<h2>Endpoints</h2>
<table>
<tr><th>Method</th><th>Path</th><th>Description</th></tr>
<tr><td>GET</td><td><a href="/">/</a></td><td>This page</td></tr>
<tr><td>GET</td><td><a href="/status">/status</a></td><td>Connectivity check (used by Mac app)</td></tr>
<tr><td>GET</td><td><a href="/printers">/printers</a></td><td>List installed printer drivers</td></tr>
<tr><td>POST</td><td>/print-default</td><td>Silent spool (X-Target-Printer header)</td></tr>
<tr><td>POST</td><td>/print-manual</td><td>Brave Browser + Ctrl+Shift+P</td></tr>
</table>
<h2>Save location</h2>
<p>Received PDFs are saved to <code>{SAVE_DIRECTORY}</code></p>
<h2>Testing from another window</h2>
<p>Open a second Command Prompt and run:<br>
<code>curl http://localhost:{BIND_PORT}/status</code></p>
</body></html>""".encode("utf-8")
        self._send_html(html)

    def _handle_printers(self):
        try:
            import win32print
            names = _enumerate_printers(win32print)
            self._send_json(json.dumps(names).encode())
            print(f"[Server] PRINTERS — returned {len(names)}: {names}")
        except ImportError:
            print("[Server] WARNING: pywin32 not installed — run: pip install pywin32")
            self._send_json(b'[]')
        except Exception:
            print(f"[Server] PRINTERS error:\n{traceback.format_exc()}")
            self._send_json(b'[]')   # return empty rather than 500 so Mac shows "no printers"

    # ── POST ─────────────────────────────────────────────────────────────────

    def do_POST(self):                       # noqa: N802
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
            # Send error response so the Mac client gets a proper HTTP response
            # instead of a dropped connection ("network connection was lost").
            try:
                self._error(500, "Server error — see console for details")
            except Exception:
                pass   # response pipe may already be broken

    # ── Save incoming PDF ─────────────────────────────────────────────────────

    def _save_pdf(self) -> bool:
        """Read the POST body and save it to OUT_PATH.
        Returns False and sends 400 if Content-Length is missing or zero."""
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
            self._error(500, f"Could not save PDF to {SAVE_DIRECTORY} — check permissions")
            return False

    # ── Route A: Express spool ────────────────────────────────────────────────

    def _handle_express(self):
        target_printer = self.headers.get("X-Target-Printer", "").strip()

        # Attempt order (most reliable → least):
        #   1. SumatraPDF -print-to  — silent, direct, no UI, no timing
        #   2. Brave + Ctrl+Shift+P + Enter — uses pywin32 SendKeys on open tab
        #   3. PowerShell fallback   — last resort, system default printer only

        if self._try_sumatra(target_printer):
            self._ok()
            return

        if self._try_brave_sendkeys(target_printer):
            self._ok()
            return

        self._try_powershell_fallback()
        self._ok()

    # ── Step 1: SumatraPDF silent print ──────────────────────────────────────

    def _try_sumatra(self, target_printer: str) -> bool:
        """Use SumatraPDF's -print-to command — completely silent, no UI,
        direct printer selection.  SumatraPDF does NOT need to be the default
        PDF viewer; it just needs to be installed anywhere on the system."""
        sumatra = _find_sumatra()
        if not sumatra:
            print("[Server] EXPRESS [1/3] SumatraPDF not found — skipping")
            return False
        try:
            if target_printer:
                cmd = [sumatra, "-print-to", target_printer, OUT_PATH]
                print(f"[Server] EXPRESS [1/3] SumatraPDF → printer {target_printer!r}")
            else:
                cmd = [sumatra, "-print-to-default", OUT_PATH]
                print("[Server] EXPRESS [1/3] SumatraPDF → system default printer")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                print(f"[Server] EXPRESS [1/3] SumatraPDF error: {result.stderr.strip()}")
                return False
            print("[Server] EXPRESS [1/3] SumatraPDF spool submitted ✓")
            return True
        except subprocess.TimeoutExpired:
            print("[Server] EXPRESS [1/3] SumatraPDF timed out")
            return False
        except Exception:
            print(f"[Server] EXPRESS [1/3] SumatraPDF failed:\n{traceback.format_exc()}")
            return False

    # ── Step 2: Brave + Ctrl+Shift+P + Enter ─────────────────────────────────

    def _try_brave_sendkeys(self, target_printer: str) -> bool:
        """Open the PDF in Brave (system default), then use WScript.Shell to:
          1. Send Ctrl+Shift+P  → opens the native Windows print dialog
          2. Wait for the dialog to appear
          3. Send Enter          → confirms print with whatever printer is shown

        If a target printer is specified, we temporarily set it as the Windows
        default before opening Brave so the dialog pre-selects the right printer.
        This mirrors the existing /print-manual route but adds the Enter key."""
        try:
            import win32com.client
        except ImportError:
            print("[Server] EXPRESS [2/3] pywin32 not installed — skipping SendKeys route")
            return False

        # ── Temporarily set target printer as Windows default ────────────────
        old_default = None
        if target_printer:
            try:
                import win32print
                old_default = win32print.GetDefaultPrinter()
                win32print.SetDefaultPrinter(target_printer)
                print(f"[Server] EXPRESS [2/3] Default printer → {target_printer!r} "
                      f"(was {old_default!r})")
            except Exception:
                print(f"[Server] EXPRESS [2/3] Could not set printer:\n"
                      f"{traceback.format_exc()}")

        try:
            # Open PDF in Brave (registered as default PDF viewer)
            print(f"[Server] EXPRESS [2/3] Opening {OUT_PATH} in Brave…")
            os.startfile(OUT_PATH, "open")

            # Wait for Brave to load and render the PDF
            time.sleep(3.0)

            shell = win32com.client.Dispatch("WScript.Shell")
            shell.AppActivate("Brave")
            time.sleep(0.5)

            # Ctrl+Shift+P = native Windows print dialog (same as manual route)
            print("[Server] EXPRESS [2/3] Sending Ctrl+Shift+P…")
            shell.SendKeys("^+p")

            # Wait for the Windows print dialog to fully appear
            time.sleep(2.0)

            # Enter = confirm/print with the currently selected printer
            print("[Server] EXPRESS [2/3] Sending Enter to confirm print…")
            shell.SendKeys("{ENTER}")

            # Brief pause to let the print job be submitted before we return
            time.sleep(1.5)
            print("[Server] EXPRESS [2/3] Brave Ctrl+Shift+P + Enter submitted ✓")
            return True

        except Exception:
            print(f"[Server] EXPRESS [2/3] Brave SendKeys failed:\n{traceback.format_exc()}")
            return False
        finally:
            if old_default:
                try:
                    import win32print
                    win32print.SetDefaultPrinter(old_default)
                    print(f"[Server] EXPRESS [2/3] Restored default → {old_default!r}")
                except Exception:
                    print(f"[Server] EXPRESS [2/3] Could not restore printer:\n"
                          f"{traceback.format_exc()}")

    # ── Step 3: PowerShell last resort ───────────────────────────────────────

    def _try_powershell_fallback(self):
        """Last-resort spool via PowerShell.  Uses the system default printer
        only — target printer argument is not forwarded."""
        print("[Server] EXPRESS [3/3] PowerShell fallback (system default printer)")
        try:
            result = subprocess.run(
                ["powershell", "-Command",
                 f'Start-Process -FilePath "{OUT_PATH}" -Verb Print'],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                print(f"[Server] EXPRESS [3/3] PowerShell error: {result.stderr.strip()}")
            else:
                print("[Server] EXPRESS [3/3] PowerShell spool submitted ✓")
        except subprocess.TimeoutExpired:
            print("[Server] EXPRESS [3/3] PowerShell timed out")
        except Exception:
            print(f"[Server] EXPRESS [3/3] PowerShell failed:\n{traceback.format_exc()}")

    # ── Route B: Brave Browser + Ctrl+Shift+P ────────────────────────────────

    def _handle_manual(self):
        print("[Server] MANUAL — opening PDF in Brave Browser …")

        try:
            os.startfile(OUT_PATH, "open")
        except Exception:
            print(f"[Server] MANUAL: os.startfile failed:\n{traceback.format_exc()}")
            self._error(500, "Could not open PDF — is Brave set as the default PDF viewer?")
            return

        time.sleep(2.5)

        try:
            import win32com.client
            shell = win32com.client.Dispatch("WScript.Shell")
            shell.AppActivate("Brave")
            time.sleep(0.5)
            print("[Server] MANUAL — injecting Ctrl+Shift+P …")
            shell.SendKeys("^+p")
        except ImportError:
            print("[Server] WARNING: pywin32 not installed — cannot send Ctrl+Shift+P. "
                  "Run: pip install pywin32")
        except Exception:
            print(f"[Server] MANUAL: SendKeys failed:\n{traceback.format_exc()}")

        self._ok()


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    try:
        server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), AdvancedPrintHandler)
    except OSError as exc:
        print(f"\n[ERROR] Cannot bind to port {BIND_PORT}: {exc}")
        print(f"  → Another program is already using port {BIND_PORT}.")
        print(f"  → Close it, or change BIND_PORT at the top of this script.")
        sys.exit(1)

    print("=" * 65)
    print("  rms_print_server.exe  —  RMS LAN Print Receiver  v3.0")
    print("=" * 65)
    print(f"  Listening on  : :{BIND_PORT}  (all interfaces)")
    print(f"  Save path     : {SAVE_DIRECTORY}")
    print()
    print("  !! THIS WINDOW IS NOT INTERACTIVE !!")
    print("  You cannot type commands here.")
    print()
    print("  To verify the server is working:")
    print(f"    • Open a browser on this PC → http://localhost:{BIND_PORT}/")
    print(f"    • Or in a 2nd Command Prompt → curl http://localhost:{BIND_PORT}/status")
    print()
    print("  Routes:")
    print(f"    GET  http://localhost:{BIND_PORT}/         — Status page (open in browser)")
    print(f"    GET  http://localhost:{BIND_PORT}/status   — Connectivity check")
    print(f"    GET  http://localhost:{BIND_PORT}/printers — List printer drivers")
    print(f"    POST /print-default  — Silent spool (X-Target-Printer header)")
    print(f"    POST /print-manual   — Brave Browser + Ctrl+Shift+P")
    print()

    try:
        import win32print
        print("  ✓ pywin32 is installed — all routes available")
    except ImportError:
        print("  ✗ pywin32 NOT installed — run: pip install pywin32")
        print("    (Express and Manual routes will use PowerShell fallback)")
    print()
    print("  Press Ctrl+C to stop.")
    print("=" * 65)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[Server] Stopped.")
