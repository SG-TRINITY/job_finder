"""Desktop window host for the RLC Watch control UI.

Runs the same HTML/CSS/JS as the browser version (server.py serves it either
way), but shows it in a native window via pywebview instead of a browser tab.
On Windows, pywebview uses the WebView2 (Edge/Chromium) runtime that already
ships with Windows 11, so this renders identically to what you'd see in Edge
or Chrome.

Behaviour:
- Closing the window minimizes it to the system tray instead of quitting
  (matches the old tray-app behaviour). Use "Exit" from the tray menu, or
  the window's own STOP button first, to actually stop things.
- If an instance is already running (port already bound), a second launch
  just asks the existing instance to show/focus its window, then exits -
  this is what makes double-clicking the desktop shortcut safe to do more
  than once instead of piling up duplicate processes.
"""

import io
import socket
import sys
import threading

import pystray
import webview
from PIL import Image, ImageDraw

import server
from server import PORT, create_server


def _port_in_use() -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex(("127.0.0.1", PORT)) == 0


def _wake_existing_instance():
    import urllib.request
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{PORT}/api/show", timeout=3)
    except Exception:
        pass


def _make_tray_image() -> Image.Image:
    # Small lime-on-void square, matching the app's Y2K accent colour -
    # no external icon asset needed.
    img = Image.new("RGBA", (64, 64), (14, 5, 38, 255))
    draw = ImageDraw.Draw(img)
    draw.ellipse((10, 10, 54, 54), fill=(157, 255, 63, 255))
    return img


def main():
    if _port_in_use():
        _wake_existing_instance()
        return

    http_server = create_server()
    thread = threading.Thread(target=http_server.serve_forever, daemon=True)
    thread.start()

    window = webview.create_window(
        "Ladle Me Jobs",
        f"http://127.0.0.1:{PORT}/",
        width=820,
        height=920,
        min_size=(640, 700),
        background_color="#0e0526",
    )

    tray_icon = {}

    def show_window():
        window.show()
        window.restore()

    server.show_callback = show_window

    def on_closing():
        window.hide()
        return False  # cancel the real close; just hide instead

    window.events.closing += on_closing

    def on_tray_show(icon=None, item=None):
        show_window()

    def on_tray_exit(icon=None, item=None):
        if "icon" in tray_icon:
            tray_icon["icon"].stop()
        http_server.shutdown()
        window.destroy()

    def start_tray():
        menu = pystray.Menu(
            pystray.MenuItem("Show Ladle Me Jobs", on_tray_show, default=True),
            pystray.MenuItem("Exit", on_tray_exit),
        )
        icon = pystray.Icon("ladle_me_jobs", _make_tray_image(), "Ladle Me Jobs", menu)
        tray_icon["icon"] = icon
        icon.run()

    threading.Thread(target=start_tray, daemon=True).start()

    webview.start()


if __name__ == "__main__":
    main()
