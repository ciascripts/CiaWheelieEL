"""iPad control for Claude, as an MCP server.

Claude sees the iPad screen and taps, swipes and types through WebDriverAgent
running on the iPad. A Stop switch (the Claude Control app on the iPad, or the
web page at http://<this PC>:8765) blocks every action until you resume.

Settings (environment variables):
  WDA_URL              WebDriverAgent address (default http://127.0.0.1:8100)
  CONTROL_PORT         Port for the Stop/Resume page and app (default 8765)
  SCREENSHOT_MAX_SIDE  Longest screenshot side sent to Claude (default 1200)
"""

import base64
import io
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from mcp.server.fastmcp import FastMCP, Image
from PIL import Image as PILImage

WDA_URL = os.environ.get("WDA_URL", "http://127.0.0.1:8100").rstrip("/")
CONTROL_PORT = int(os.environ.get("CONTROL_PORT", "8765"))
MAX_SIDE = int(os.environ.get("SCREENSHOT_MAX_SIDE", "1200"))
SETTLE_SECONDS = 0.7  # wait after an action before the follow-up screenshot

COMMON_APPS = {
    "settings": "com.apple.Preferences",
    "safari": "com.apple.mobilesafari",
    "photos": "com.apple.mobileslideshow",
    "camera": "com.apple.camera",
    "app store": "com.apple.AppStore",
    "files": "com.apple.DocumentsApp",
    "notes": "com.apple.mobilenotes",
    "messages": "com.apple.MobileSMS",
    "mail": "com.apple.mobilemail",
    "music": "com.apple.Music",
    "maps": "com.apple.Maps",
    "calendar": "com.apple.mobilecal",
    "clock": "com.apple.mobiletimer",
    "reminders": "com.apple.reminders",
    "facetime": "com.apple.facetime",
    "youtube": "com.google.ios.youtube",
    "spotify": "com.spotify.client",
}


def log(*args):
    # stdout carries the MCP protocol, so logs must go to stderr.
    print(*args, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Stop switch
# --------------------------------------------------------------------------

class Control:
    def __init__(self):
        self.lock = threading.Lock()
        self.stopped = False
        self.last_action = "Waiting for Claude"
        self.updated = time.time()

    def set_stopped(self, value, reason):
        with self.lock:
            self.stopped = value
            self.last_action = reason
            self.updated = time.time()
        log(f"[control] {'STOPPED' if value else 'RESUMED'}: {reason}")

    def note(self, action):
        with self.lock:
            self.last_action = action
            self.updated = time.time()

    def snapshot(self):
        with self.lock:
            return {"stopped": self.stopped, "last_action": self.last_action, "updated": self.updated}


CONTROL = Control()


class StoppedError(Exception):
    pass


def ensure_running():
    if CONTROL.snapshot()["stopped"]:
        raise StoppedError(
            "STOPPED: the user pressed Stop. Do not try again and do not look for another way to "
            "act on the iPad. Tell the user you have stopped and wait for them to resume."
        )


PAGE = """<!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
<title>Claude iPad Control</title><style>
body{font-family:-apple-system,Segoe UI,sans-serif;text-align:center;padding:24px;background:#111;color:#eee}
button{font-size:28px;padding:22px 40px;border:0;border-radius:18px;margin:10px;width:80%;max-width:420px}
#stop{background:#e5483b;color:#fff}#resume{background:#2e7d32;color:#fff}p{color:#aaa}
</style></head><body><h1 id=state>…</h1><p id=last></p>
<button id=stop onclick="send('stop')">■ STOP</button><br>
<button id=resume onclick="send('resume')">▶ Resume</button>
<script>
async function send(a){await fetch('/'+a,{method:'POST'});load()}
async function load(){const s=await (await fetch('/status')).json();
document.getElementById('state').textContent=s.stopped?'⛔ Stopped':'🟢 Claude may control the iPad';
document.getElementById('last').textContent='Last: '+s.last_action}
load();setInterval(load,1500)
</script></body></html>"""


class ControlHandler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _route(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path == "/stop":
            CONTROL.set_stopped(True, "Stopped by you")
        elif path == "/resume":
            CONTROL.set_stopped(False, "Resumed by you")
        elif path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        elif path != "/status":
            return self._send(404, json.dumps({"error": "not found"}))
        self._send(200, json.dumps(CONTROL.snapshot()))

    def do_GET(self):
        self._route()

    def do_POST(self):
        self._route()

    def log_message(self, *args):
        pass  # keep quiet; stdout is reserved for MCP


def start_control_server():
    try:
        server = ThreadingHTTPServer(("0.0.0.0", CONTROL_PORT), ControlHandler)
    except OSError as e:
        log(f"[control] could not open port {CONTROL_PORT}: {e}")
        return
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log(f"[control] Stop/Resume page on http://<this-pc-ip>:{CONTROL_PORT}")


# --------------------------------------------------------------------------
# WebDriverAgent
# --------------------------------------------------------------------------

class WDA:
    def __init__(self, base):
        self.base = base
        self.session_id = None
        self.lock = threading.Lock()

    def request(self, method, path, body=None, timeout=30):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read()[:400].decode("utf-8", "replace")
            raise RuntimeError(f"WebDriverAgent error {e.code} on {path}: {detail}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            reason = getattr(e, "reason", e)
            raise RuntimeError(
                f"Can't reach WebDriverAgent at {self.base} ({reason}). On the PC, check that "
                "`ios runwda` is still running and `ios forward 8100 8100` is open, and that the iPad is unlocked."
            )

    def session(self):
        with self.lock:
            if self.session_id:
                return self.session_id
            resp = self.request("POST", "/session", {"capabilities": {"alwaysMatch": {}, "firstMatch": [{}]}})
            sid = resp.get("sessionId") or (resp.get("value") or {}).get("sessionId")
            if not sid:
                raise RuntimeError(f"WebDriverAgent didn't return a session: {str(resp)[:300]}")
            self.session_id = sid
            return sid

    def call(self, method, path, body=None, timeout=30):
        """Call a session endpoint ("/window/size" -> /session/<id>/window/size), retrying once on a stale session."""
        for attempt in range(2):
            sid = self.session()
            try:
                return self.request(method, f"/session/{sid}{path}", body, timeout)
            except RuntimeError as e:
                if attempt == 0 and ("session" in str(e).lower() and ("invalid" in str(e).lower() or "404" in str(e))):
                    with self.lock:
                        self.session_id = None
                    continue
                raise

    def window_size(self):
        value = self.call("GET", "/window/size").get("value") or {}
        return float(value.get("width", 0)), float(value.get("height", 0))

    def screenshot_png(self):
        value = self.request("GET", "/screenshot", timeout=40).get("value")
        if not value:
            raise RuntimeError("WebDriverAgent returned an empty screenshot.")
        return base64.b64decode(value)

    def pointer(self, actions):
        body = {"actions": [{
            "type": "pointer", "id": "finger1",
            "parameters": {"pointerType": "touch"},
            "actions": actions,
        }]}
        self.call("POST", "/actions", body)


WD = WDA(WDA_URL)


class Screen:
    """Maps screenshot pixels (what Claude sees) to iPad points (what WDA taps)."""
    def __init__(self):
        self.scale_x = 1.0
        self.scale_y = 1.0
        self.size = (0, 0)

    def to_points(self, x, y):
        return round(x * self.scale_x, 1), round(y * self.scale_y, 1)


SCREEN = Screen()


def capture():
    png = WD.screenshot_png()
    pt_w, pt_h = WD.window_size()
    img = PILImage.open(io.BytesIO(png)).convert("RGB")
    # Use the iPad's point grid so coordinates map 1:1, then shrink if still too big.
    if pt_w and pt_h:
        target_w, target_h = pt_w, pt_h
        if (img.width > img.height) != (pt_w > pt_h):
            target_w, target_h = pt_h, pt_w
    else:
        target_w, target_h = img.width, img.height
    factor = min(1.0, MAX_SIDE / max(target_w, target_h))
    out_w, out_h = max(1, int(target_w * factor)), max(1, int(target_h * factor))
    img = img.resize((out_w, out_h), PILImage.LANCZOS)
    SCREEN.size = (out_w, out_h)
    SCREEN.scale_x = (pt_w or out_w) / out_w
    SCREEN.scale_y = (pt_h or out_h) / out_h
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=80)
    return Image(data=buf.getvalue(), format="jpeg")


def check_point(x, y):
    w, h = SCREEN.size
    if not w:
        raise ValueError("Take a screenshot first (ipad_screenshot) so coordinates are known.")
    if not (0 <= x <= w and 0 <= y <= h):
        raise ValueError(f"({x}, {y}) is off the screen. The screenshot is {w}x{h}.")


def after(action):
    CONTROL.note(action)
    time.sleep(SETTLE_SECONDS)
    ensure_running()
    shot = capture()
    w, h = SCREEN.size
    return [f"Done: {action}. New screenshot ({w}x{h}):", shot]


# --------------------------------------------------------------------------
# MCP tools
# --------------------------------------------------------------------------

mcp = FastMCP(
    "ipad",
    instructions=(
        "Control the user's iPad. Start with ipad_screenshot. Coordinates are pixels in the most recent "
        "screenshot (top-left is 0,0). After each action you get a fresh screenshot; check it before the "
        "next step. Prefer ipad_tap_text when the target has a visible label. Never tap the small floating "
        "'Claude Control' picture-in-picture window: it is the user's Stop button. If a tool says STOPPED, "
        "stop completely and tell the user. Ask the user before purchases, deleting data, sending messages "
        "or changing passwords and security settings."
    ),
)


@mcp.tool()
def ipad_screenshot():
    """See the iPad screen now. Returns an image; tap coordinates use its pixel grid."""
    ensure_running()
    shot = capture()
    w, h = SCREEN.size
    CONTROL.note("Looked at the screen")
    return [f"iPad screen ({w}x{h}):", shot]


@mcp.tool()
def ipad_tap(x: float, y: float):
    """Tap at (x, y) in the latest screenshot's pixels."""
    ensure_running()
    check_point(x, y)
    px, py = SCREEN.to_points(x, y)
    WD.pointer([
        {"type": "pointerMove", "duration": 0, "x": px, "y": py, "origin": "viewport"},
        {"type": "pointerDown", "button": 0},
        {"type": "pause", "duration": 60},
        {"type": "pointerUp", "button": 0},
    ])
    return after(f"tap ({x:.0f}, {y:.0f})")


@mcp.tool()
def ipad_long_press(x: float, y: float, seconds: float = 1.0):
    """Press and hold at (x, y) for `seconds` (e.g. to open a context menu)."""
    ensure_running()
    check_point(x, y)
    px, py = SCREEN.to_points(x, y)
    WD.pointer([
        {"type": "pointerMove", "duration": 0, "x": px, "y": py, "origin": "viewport"},
        {"type": "pointerDown", "button": 0},
        {"type": "pause", "duration": int(max(0.3, min(seconds, 10)) * 1000)},
        {"type": "pointerUp", "button": 0},
    ])
    return after(f"long press ({x:.0f}, {y:.0f})")


@mcp.tool()
def ipad_swipe(start_x: float, start_y: float, end_x: float, end_y: float, seconds: float = 0.35):
    """Swipe from start to end. To scroll down, swipe upward (start_y > end_y).
    From the very bottom edge upward goes Home; from the top-right corner downward opens Control Center."""
    ensure_running()
    check_point(start_x, start_y)
    check_point(end_x, end_y)
    sx, sy = SCREEN.to_points(start_x, start_y)
    ex, ey = SCREEN.to_points(end_x, end_y)
    WD.pointer([
        {"type": "pointerMove", "duration": 0, "x": sx, "y": sy, "origin": "viewport"},
        {"type": "pointerDown", "button": 0},
        {"type": "pause", "duration": 40},
        {"type": "pointerMove", "duration": int(max(0.05, min(seconds, 5)) * 1000), "x": ex, "y": ey, "origin": "viewport"},
        {"type": "pointerUp", "button": 0},
    ])
    return after(f"swipe ({start_x:.0f},{start_y:.0f}) → ({end_x:.0f},{end_y:.0f})")


@mcp.tool()
def ipad_type(text: str):
    """Type text into the focused field (tap the field first). Use "\\n" for Return."""
    ensure_running()
    WD.call("POST", "/wda/keys", {"value": list(text)})
    preview = text if len(text) <= 40 else text[:37] + "…"
    return after(f"type “{preview}”")


@mcp.tool()
def ipad_tap_text(text: str):
    """Tap the first visible button, link, cell or label whose text contains `text` (case-insensitive).
    More reliable than coordinates when the target has a label."""
    ensure_running()
    safe = text.replace("\\", "\\\\").replace("'", "\\'")
    predicate = (f"(label CONTAINS[c] '{safe}' OR name CONTAINS[c] '{safe}' OR value CONTAINS[c] '{safe}')"
                 " AND visible == 1")
    found = WD.call("POST", "/elements", {"using": "predicate string", "value": predicate}).get("value") or []
    if not found:
        return [f"No visible element contains “{text}”. Take a screenshot and tap by coordinates instead."]
    element = found[0]
    element_id = element.get("ELEMENT") or element.get("element-6066-11e4-a52e-4f735466cecf")
    WD.call("POST", f"/element/{element_id}/click", {})
    return after(f"tap “{text}”")


@mcp.tool()
def ipad_home():
    """Go to the Home Screen."""
    ensure_running()
    WD.request("POST", "/wda/homescreen", {})
    return after("go Home")


@mcp.tool()
def ipad_press_button(button: str):
    """Press a hardware button: "home", "volumeUp" or "volumeDown"."""
    ensure_running()
    if button not in ("home", "volumeUp", "volumeDown"):
        raise ValueError('button must be "home", "volumeUp" or "volumeDown"')
    WD.call("POST", "/wda/pressButton", {"name": button})
    return after(f"press {button}")


@mcp.tool()
def ipad_open_app(app: str):
    """Open an app by name (Settings, Safari, Photos, App Store, Files, Notes, Messages, Mail, Music,
    Maps, Calendar, Clock, Reminders, Camera, FaceTime, YouTube, Spotify) or by bundle ID (com.apple.Preferences).
    For other apps, go Home and use Spotlight (swipe down on the Home Screen) instead."""
    ensure_running()
    bundle_id = COMMON_APPS.get(app.strip().lower(), app.strip())
    if "." not in bundle_id:
        return [f"I don't know the bundle ID for “{app}”. Use Spotlight: ipad_home, swipe down from the "
                "middle of the screen, then ipad_type the app name."]
    WD.call("POST", "/wda/apps/launch", {"bundleId": bundle_id})
    return after(f"open {app}")


@mcp.tool()
def ipad_status():
    """Check the connection to the iPad and whether the user has pressed Stop."""
    state = CONTROL.snapshot()
    try:
        status = WD.request("GET", "/status", timeout=8).get("value") or {}
        ios = (status.get("os") or {}).get("version", "?")
        connection = f"WebDriverAgent is running (iPadOS {ios}) at {WD_URL_DISPLAY}."
    except RuntimeError as e:
        connection = str(e)
    stop = "STOPPED by the user." if state["stopped"] else "Not stopped."
    return f"{connection} {stop} Last action: {state['last_action']}."


WD_URL_DISPLAY = WDA_URL


def main():
    start_control_server()
    log(f"[ipad-mcp] using WebDriverAgent at {WDA_URL}")
    mcp.run()


if __name__ == "__main__":
    main()
