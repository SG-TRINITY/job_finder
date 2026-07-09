"""Local control server for the RLC Watch browser UI.

Serves ui/index.html and a small JSON API that shells out to
rlc_watch_control.ps1 for process status/start/stop (Windows process
matching is easiest via PowerShell's Win32_Process, so we reuse it
instead of reimplementing it in Python).

Binds to 127.0.0.1 only - this is a personal local tool, not a
network service.
"""

import json
import re
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = Path(__file__).resolve().parent
CONTROL_SCRIPT = ROOT / "rlc_watch_control.ps1"
LOG_FILE = ROOT / "logs" / "rlc-watch.log"
BOARDS_FILE = ROOT / "boards.json"
PORT = 8787

# Set by desktop_app.py so a second launch attempt (which finds the port
# already taken) can ask this already-running instance to show/focus its
# window instead of silently doing nothing or erroring.
show_callback = None

TAG_PATTERNS = [
    ("scan", re.compile(r"\[scan\]")),
    ("warn", re.compile(r"\[warn\]|\[error\]")),
    ("hit", re.compile(r"\[ok\].*(emailed|texted|sent)")),
    ("ok", re.compile(r"\[ok\]")),
    ("sys", re.compile(r"\[loop\]|\[watchdog\]")),
]


def tag_for_line(line: str) -> str:
    for tag, pattern in TAG_PATTERNS:
        if pattern.search(line):
            return tag
    return "default"


_NO_WINDOW = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0


def run_control(action: str) -> dict:
    result = subprocess.run(
        [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(CONTROL_SCRIPT), "-Action", action,
        ],
        capture_output=True, text=True, timeout=30,
        creationflags=_NO_WINDOW,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "control script failed")
    return json.loads(result.stdout.strip())


def get_board_count() -> int:
    try:
        boards = json.loads(BOARDS_FILE.read_text(encoding="utf-8"))
        return sum(1 for b in boards if b.get("enabled", True))
    except (OSError, json.JSONDecodeError):
        return 0


def get_log_lines(count: int) -> list:
    if not LOG_FILE.exists():
        return []
    lines = LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
    lines = [line for line in lines if line.strip()]
    return [{"text": line, "tag": tag_for_line(line)} for line in lines[-count:]]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, payload: dict, status: int = 200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._serve_file(UI_DIR / "index.html", "text/html")
        elif parsed.path == "/api/status":
            try:
                status = run_control("Status")
                status["boardCount"] = get_board_count()
                self._send_json(status)
            except Exception as exc:
                self._send_json({"error": str(exc)}, status=500)
        elif parsed.path == "/api/log":
            qs = parse_qs(parsed.query)
            count = int(qs.get("lines", ["40"])[0])
            self._send_json({"lines": get_log_lines(count)})
        elif parsed.path == "/log":
            self._serve_file(LOG_FILE, "text/plain")
        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/start":
            try:
                self._send_json(run_control("Start"))
            except Exception as exc:
                self._send_json({"error": str(exc)}, status=500)
        elif parsed.path == "/api/stop":
            try:
                self._send_json(run_control("Stop"))
            except Exception as exc:
                self._send_json({"error": str(exc)}, status=500)
        elif parsed.path == "/api/show":
            if show_callback is not None:
                show_callback()
            self._send_json({"ok": True})
        else:
            self.send_error(404)

    def _serve_file(self, path: Path, content_type: str):
        if not path.exists():
            self.send_error(404)
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def create_server() -> ThreadingHTTPServer:
    return ThreadingHTTPServer(("127.0.0.1", PORT), Handler)


def start_server_in_background() -> ThreadingHTTPServer:
    """Used by the desktop window host, which needs the HTTP server running
    on its own thread since pywebview's event loop owns the main thread."""
    server = create_server()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def main():
    server = create_server()
    url = f"http://127.0.0.1:{PORT}/"
    print(f"RLC Watch control UI running at {url}")
    print("Close this window (or Ctrl+C) to stop the control server.")
    print("(The scraper/watchdog processes keep running independently - use STOP in the UI to stop them.)")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
