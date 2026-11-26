"""
v9.0.1 Live Browser Web Remote JS Runtime & Full 10-Game CDP Verification

Exercises the live HostCompanionBridge Web Remote HTTP/WebSocket endpoints inside
real headless Microsoft Edge / Google Chrome over Chrome DevTools Protocol (CDP):
  - GET /, GET /arcade.js, GET /favicon.ico, GET /health (status & headers)
  - Live browser pairing with Session Code -> WebSocket /ws connect
  - UI scale toggle verification (including 1.25x scale)
  - About modal version check (matches Lib/GUI_Config.ahk APP_VERSION == 9.0.1)
  - Tap-to-mute round-trip (#micBtn -> AHK Host -> #micLbl updated)
  - Sector Z Vault unlock + launching, rendering & stepping ALL 10 Web games:
      snake, asteroids, brick_breaker, cyber_pong, flappy,
      tron, pac_grid, missile_defense, block_drop, pinball
    including Blaster mode switch (Asteroids <-> Alien Blaster) and
    Clicker Flappy / Gravity Wave title preservation across close & relaunch
  - Clean Disconnect (#discBtn) unregistering from host & resetting UI
  - Strict assertion: ZERO Runtime.exceptionThrown or console errors
"""

import json
import os
import re
import socket
import struct
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


ALL_GAME_IDS = [
    "snake",
    "asteroids",
    "brick_breaker",
    "cyber_pong",
    "flappy",
    "tron",
    "pac_grid",
    "missile_defense",
    "block_drop",
    "pinball",
]


def read_expected_version() -> str:
    cfg_path = os.path.join(ec.REPO_DIR, "Lib", "GUI_Config.ahk")
    with open(cfg_path, "r", encoding="utf-8", errors="replace") as f:
        m = re.search(r'APP_VERSION\s*:=\s*"([^"]+)"', f.read())
    assert m, "Could not parse APP_VERSION from Lib/GUI_Config.ahk"
    return m.group(1)


def find_chromium_binary() -> str:
    candidates = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    raise RuntimeError("Neither Microsoft Edge nor Google Chrome binary was found for CDP verification")


def write_host_runner(ahk_path: str, ready_path: str, obs_port: int) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -75000)
OnError((err, mode) => (FileAppend("ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
cfg.SessionPairingCode := "WEB-901"
cfg.ObsPassword := ""
cfg.EnableWS := true
cfg.EnableRemoteConnections := true
cfg.StandbySceneName := "BRB"
cfg.AudioRoutingMode := 2

st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.currentSceneName := "Main"
st.sceneList := ["Main", "Slides", "BRB"]
st.obsConnected := true
st.studioModeActive := true
st.isMuted := false
st.obsWs := WebSocket("ws://127.0.0.1:{obs_port}")
Sleep(200)
st.obsWs.sendText('{{"op":1,"d":{{"rpcVersion":1}}}}')
Sleep(150)

st.pptNextFn := (*) => true
st.pptPrevFn := (*) => true
st.triggerMuteFn := (*) => SyncUIState(cfg, st, !st.isMuted)
st.triggerTransitionFn := (*) => TriggerObsSceneTransition(cfg, st, true)

bridge := StartHostCompanionBridge(cfg, st, 0, 0)
if (!IsObject(bridge) || !bridge.running) {{
    FileAppend('{{"ok":false}}', "{ready_path}", "UTF-8")
    ExitApp(2)
}}
info := '{{"ok":true,"tcpPort":' bridge.boundTcpPort ',"sessionCode":"' cfg.SessionPairingCode '"}}'
FileAppend(info, "{ready_path}", "UTF-8")
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


class CdpClient:
    """Minimal pure-Python RFC-6455 CDP WebSocket client with frame reassembly."""

    def __init__(self, ws_url: str):
        parsed = urllib.parse.urlparse(ws_url)
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        self.sock, init_rest = ec.ws_connect(host, port, path, timeout=10.0)
        self.buf = bytearray(init_rest)
        self.next_id = 1
        self.exceptions: list[str] = []
        self.console_errors: list[str] = []

    def close(self) -> None:
        try:
            self.sock.close()
        except Exception:
            pass

    def _recv_frame(self, timeout: float = 10.0) -> tuple[bool, int, bytes]:
        self.sock.settimeout(timeout)
        while len(self.buf) < 2:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("CDP socket closed")
            self.buf.extend(chunk)
        b0, b1 = self.buf[0], self.buf[1]
        fin = (b0 & 0x80) != 0
        op = b0 & 0x0F
        plen = b1 & 0x7F
        off = 2
        if plen == 126:
            while len(self.buf) < 4:
                self.buf.extend(self.sock.recv(65536))
            plen = struct.unpack("!H", self.buf[2:4])[0]
            off = 4
        elif plen == 127:
            while len(self.buf) < 10:
                self.buf.extend(self.sock.recv(65536))
            plen = struct.unpack("!Q", self.buf[2:10])[0]
            off = 10
        while len(self.buf) < off + plen:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("CDP socket closed mid-frame")
            self.buf.extend(chunk)
        payload = bytes(self.buf[off : off + plen])
        del self.buf[: off + plen]
        return fin, op, payload

    def _recv_message(self, timeout: float = 10.0) -> dict:
        chunks = []
        while True:
            fin, op, payload = self._recv_frame(timeout=timeout)
            if op == 0x9:  # ping -> pong
                import os as _os
                mask = _os.urandom(4)
                hdr = bytes([0x8A, 0x80 | len(payload)]) + mask
                self.sock.sendall(hdr + bytes(payload[i] ^ mask[i % 4] for i in range(len(payload))))
                continue
            if op == 0xA:
                continue
            if op == 0x8:
                raise EOFError("CDP Close received")
            chunks.append(payload)
            if fin:
                raw = b"".join(chunks).decode("utf-8", errors="replace")
                return json.loads(raw)

    def _record_event(self, msg: dict) -> None:
        method = msg.get("method")
        params = msg.get("params", {})
        if method == "Runtime.exceptionThrown":
            details = params.get("exceptionDetails", {})
            desc = (
                details.get("exception", {}).get("description")
                or details.get("text")
                or str(details)
            )
            self.exceptions.append(desc)
        elif method == "Runtime.consoleAPICalled" and params.get("type") == "error":
            args = [str(a.get("value") or a.get("description") or "") for a in params.get("args", [])]
            self.console_errors.append(" ".join(args))
        elif method == "Log.entryAdded":
            entry = params.get("entry", {})
            if entry.get("level") == "error":
                self.console_errors.append(f"{entry.get('text', '')} ({entry.get('url', '')})")

    def call(self, method: str, params: dict | None = None, timeout: float = 10.0) -> dict:
        cid = self.next_id
        self.next_id += 1
        req = {"id": cid, "method": method, "params": params or {}}
        ec.ws_send_text(self.sock, json.dumps(req))
        deadline = time.time() + timeout
        while time.time() < deadline:
            rem = max(0.2, deadline - time.time())
            msg = self._recv_message(timeout=rem)
            if msg.get("id") == cid:
                if "error" in msg:
                    raise RuntimeError(f"CDP {method} failed: {msg['error']}")
                return msg.get("result", {})
            self._record_event(msg)
        raise TimeoutError(f"CDP {method} timed out after {timeout}s")

    def drain_events(self, wait_sec: float = 0.08) -> None:
        deadline = time.time() + wait_sec
        while time.time() < deadline:
            try:
                msg = self._recv_message(timeout=max(0.02, deadline - time.time()))
                self._record_event(msg)
            except (socket.timeout, TimeoutError):
                break

    def eval_js(self, expr: str, timeout: float = 10.0):
        res = self.call(
            "Runtime.evaluate",
            {
                "expression": expr,
                "awaitPromise": True,
                "returnByValue": True,
            },
            timeout=timeout,
        )
        if "exceptionDetails" in res:
            details = res["exceptionDetails"]
            raise AssertionError(f"JS evaluation exception: {details}")
        return res.get("result", {}).get("value")


def http_get_bytes(url: str) -> tuple[int, dict[str, str], bytes]:
    with urllib.request.urlopen(url, timeout=5.0) as resp:
        hdrs = {k.lower(): v for k, v in resp.headers.items()}
        return resp.status, hdrs, resp.read()


def main() -> int:
    expected_ver = read_expected_version()
    browser_bin = find_chromium_binary()
    print(f"[INFO] Browser binary: {browser_bin} | Expected APP_VERSION: {expected_ver}")

    with ec.TempWorkspace("psync_v901_webjs_") as tmp, ec.MockObsWsServer(studio_mode=True) as mock_obs:
        ahk_script = tmp.join("host_web_js_runner.ahk")
        ready_file = tmp.join("ready.json")
        write_host_runner(ahk_script, ready_file, mock_obs.port)

        with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_script]):
            ec.wait_for_condition("host ready.json", lambda: os.path.exists(ready_file), timeout=10.0)
            with open(ready_file, "r", encoding="utf-8-sig") as f:
                info = json.load(f)
            assert info.get("ok") is True, f"Host Bridge failed: {info}"
            port = int(info["tcpPort"])
            code = info["sessionCode"]
            base_url = f"http://127.0.0.1:{port}"

            # 1. Verify HTTP endpoints
            st_root, _, html_body = ec.http_request("GET", f"{base_url}/")
            assert st_root == 200 and expected_ver in html_body, f"GET / bad ({st_root})"

            st_js, hdr_js, js_body = ec.http_request("GET", f"{base_url}/arcade.js")
            assert st_js == 200 and "javascript" in hdr_js.get("content-type", "").lower()
            assert "PSArcadeVault" in js_body and "Mode: Asteroids" in js_body
            assert "\\x27" not in js_body

            st_fav, hdr_fav, fav_bytes = http_get_bytes(f"{base_url}/favicon.ico")
            assert st_fav == 200 and len(fav_bytes) > 64 and fav_bytes[:4] == b"\x00\x00\x01\x00", (
                f"GET /favicon.ico unexpected: status={st_fav}, len={len(fav_bytes)}"
            )

            st_h, health = ec.http_json("GET", f"{base_url}/health")
            assert st_h == 200 and health.get("ok") is True and int(health.get("bridgePort", 0)) == port
            print(f"[PASS] HTTP /, /arcade.js ({len(js_body)}B), /favicon.ico ({len(fav_bytes)}B), /health OK")

            # 2. Launch headless Chromium/Edge via CDP
            cdp_port = ec.find_free_loopback_port()
            user_data_dir = tmp.join("browser_profile")
            os.makedirs(user_data_dir, exist_ok=True)
            browser_cmd = [
                browser_bin,
                "--headless=new",
                "--disable-gpu",
                "--no-first-run",
                "--no-default-browser-check",
                f"--remote-debugging-port={cdp_port}",
                "--remote-allow-origins=*",
                f"--user-data-dir={user_data_dir}",
                "--window-size=1280,900",
                "about:blank",
            ]
            with ec.ManagedSubprocess(browser_cmd):
                targets = ec.wait_for_condition(
                    "CDP /json/list page target",
                    lambda: [
                        t
                        for t in ec.http_json("GET", f"http://127.0.0.1:{cdp_port}/json/list")[1]
                        if t.get("type") == "page" and t.get("webSocketDebuggerUrl")
                    ],
                    timeout=12.0,
                )
                ws_url = targets[0]["webSocketDebuggerUrl"]
                cdp = CdpClient(ws_url)
                try:
                    cdp.call("Page.enable")
                    cdp.call("Runtime.enable")
                    cdp.call("Log.enable")

                    cdp.call("Page.navigate", {"url": f"{base_url}/"})
                    ec.wait_for_condition(
                        "Web Remote globals ready",
                        lambda: cdp.eval_js(
                            "Boolean(document.getElementById('connBtn') && window.PSArcadeVault && window.PSWebPinball)"
                        )
                        is True,
                        timeout=10.0,
                    )
                    print("[PASS] Headless browser loaded / and /arcade.js cleanly")

                    # Pair via UI inputs (#codeIn + #connBtn)
                    cdp.eval_js(
                        f"(() => {{ document.getElementById('codeIn').value = {json.dumps(code)}; document.getElementById('connBtn').click(); }})()"
                    )
                    ec.wait_for_condition(
                        "Web Remote connected deck visible",
                        lambda: cdp.eval_js(
                            "!document.getElementById('deck').classList.contains('hide') && "
                            "(document.getElementById('st').textContent || '').toLowerCase().includes('connected')"
                        )
                        is True,
                        timeout=8.0,
                    )
                    print("[PASS] Browser Web Remote paired and entered Connected state")

                    # V2-M5 Parity Checks: Scene pill, Reconnect, Guarded Reset Scene & RBAC .role-dir gating
                    v2_m5_dom = cdp.eval_js(
                        "({"
                        "roleBadge: document.getElementById('roleBadge').textContent,"
                        "scPillTxt: document.getElementById('scPillTxt').textContent,"
                        "reconnVisible: !document.getElementById('reconnBtn').classList.contains('hide'),"
                        "recHiddenForPresenter: document.getElementById('recBtn').classList.contains('hide'),"
                        "panicHiddenForPresenter: document.getElementById('panicBtn').classList.contains('hide'),"
                        "previewHiddenForPresenter: document.getElementById('previewScBtn').classList.contains('hide'),"
                        "hasResetBtn: Boolean(document.getElementById('resetSceneBtn'))"
                        "})"
                    )
                    assert v2_m5_dom["roleBadge"] == "Presenter", f"Expected Presenter roleBadge: {v2_m5_dom}"
                    assert v2_m5_dom["scPillTxt"] == "Main", f"Expected Main in scenePill: {v2_m5_dom}"
                    assert v2_m5_dom["reconnVisible"] is True and v2_m5_dom["hasResetBtn"] is True, f"Missing Reconnect/Reset buttons: {v2_m5_dom}"
                    assert v2_m5_dom["recHiddenForPresenter"] and v2_m5_dom["panicHiddenForPresenter"] and v2_m5_dom["previewHiddenForPresenter"], (
                        f".role-dir controls were not hidden for Presenter role: {v2_m5_dom}"
                    )
                    # Guarded 2-tap Reset Scene first tap arms confirmation
                    cdp.eval_js("document.getElementById('resetSceneBtn').click()")
                    assert cdp.eval_js("document.getElementById('resetSceneBtn').textContent") == "Confirm Reset?"
                    # Wait briefly or test 2nd tap completes reset flow cleanly
                    cdp.eval_js("document.getElementById('resetSceneBtn').click()")
                    assert "Resetting" in (cdp.eval_js("document.getElementById('toastBanner').textContent") or "")
                    print("[PASS] V2-M5 Scene pill, Reconnect, 2-tap Reset Scene, and Presenter RBAC gating verified")

                    # Tap-to-mute round-trip + keyed scene DOM identity check
                    cdp.eval_js("window.__refSceneBtn = document.querySelector('#scenes button');")
                    before_lbl = cdp.eval_js("document.getElementById('micLbl').textContent")
                    cdp.eval_js("document.getElementById('micBtn').click()")
                    ec.wait_for_condition(
                        "Tap-to-mute round-trip updates #micLbl",
                        lambda: cdp.eval_js("document.getElementById('micLbl').textContent") != before_lbl,
                        timeout=5.0,
                    )
                    after_lbl = cdp.eval_js("document.getElementById('micLbl').textContent")
                    assert after_lbl == "MIC MUTED", f"Expected MIC MUTED after tap, got {after_lbl}"
                    dom_ok = cdp.eval_js(
                        "Boolean(window.__refSceneBtn && document.querySelector('#scenes button') === window.__refSceneBtn "
                        "&& parseFloat(getComputedStyle(document.getElementById('scaleBtn')).minHeight) >= 44)"
                    )
                    assert dom_ok is True, "Scene DOM node was replaced across mute update or button.sm min-height < 44px"
                    # Toggle back live
                    cdp.eval_js("document.getElementById('micBtn').click()")
                    ec.wait_for_condition(
                        "Second tap-to-mute returns MIC LIVE",
                        lambda: cdp.eval_js("document.getElementById('micLbl').textContent") == "MIC LIVE",
                        timeout=5.0,
                    )
                    print("[PASS] Live tap-to-mute WebSocket round-trip, keyed scene DOM identity & >=44px touch targets verified")

                    # Cycle scale to 1.25x & verify CSS var
                    cdp.eval_js(
                        """(() => {
                            const b = document.getElementById('scaleBtn');
                            for (let i = 0; i < 4 && b.textContent !== '1.25x'; i++) b.click();
                            return { text: b.textContent, cssVar: getComputedStyle(document.documentElement).getPropertyValue('--ui-scale').trim() };
                        })()"""
                    )
                    scale_state = cdp.eval_js(
                        "({text: document.getElementById('scaleBtn').textContent, cssVar: document.documentElement.style.getPropertyValue('--ui-scale')})"
                    )
                    assert scale_state["text"] == "1.25x" and scale_state["cssVar"] == "1.25", (
                        f"Scale 1.25x mismatch: {scale_state}"
                    )

                    # Open About modal and verify version
                    cdp.eval_js("document.getElementById('aboutBtn').click()")
                    about_info = cdp.eval_js(
                        "({hidden: document.getElementById('aboutModal').classList.contains('hide'), ver: document.getElementById('aboutVer').textContent})"
                    )
                    assert not about_info["hidden"] and expected_ver in about_info["ver"], (
                        f"About modal check failed: {about_info}"
                    )
                    cdp.eval_js("document.getElementById('aboutCloseBtn').click()")
                    print(f"[PASS] 1.25x scale & About modal (Version {expected_ver}) verified")

                    # Unlock Sector Z Vault & test all 10 Web games + frame execution
                    unlocked = cdp.eval_js("window.PSArcadeVault.tryUnlock('INSERT COIN')")
                    assert unlocked is True, "Failed to unlock PSArcadeVault"

                    for gid in ALL_GAME_IDS:
                        ok_start = cdp.eval_js(
                            f"""(() => {{
                                const entry = window.PSArcadeVault.games.find(g => g.id === {json.dumps(gid)});
                                if (!entry) return {{ok: false, reason: 'missing catalog entry'}};
                                const launched = entry.game.start();
                                const open = !document.getElementById('arcWrap').classList.contains('hide');
                                const cvs = document.getElementById('arcCanvas');
                                return {{
                                    ok: Boolean(launched && open && cvs.width > 0 && cvs.height > 0),
                                    title: document.getElementById('arcGameTitle').textContent,
                                    mode: document.getElementById('arcModeBtn').textContent,
                                    w: cvs.width,
                                    h: cvs.height
                                }};
                            }})()"""
                        )
                        assert ok_start["ok"], f"Failed launching web game '{gid}': {ok_start}"
                        # Let requestAnimationFrame step multiple frames (incl. PSWebSnake buildPieces & physics)
                        time.sleep(0.18)
                        cdp.drain_events(0.05)

                        if gid == "asteroids":
                            assert ok_start["title"] == "ASTEROID BLASTER" and "M→Alien" in ok_start["mode"], (
                                f"Asteroids initial hints bad: {ok_start}"
                            )
                            sw = cdp.eval_js(
                                """(() => {
                                    document.getElementById('arcModeBtn').click();
                                    return {
                                        title: document.getElementById('arcGameTitle').textContent,
                                        mode: document.getElementById('arcModeBtn').textContent
                                    };
                                })()"""
                            )
                            assert sw["title"] == "ALIEN BLASTER" and "M→Asteroids" in sw["mode"], (
                                f"Asteroids->Alien switch bad: {sw}"
                            )
                            time.sleep(0.12)
                            cdp.eval_js("document.getElementById('arcModeBtn').click()")
                        elif gid == "flappy":
                            sw_f = cdp.eval_js(
                                """(() => {
                                    document.getElementById('arcModeBtn').click();
                                    return {
                                        title: document.getElementById('arcGameTitle').textContent,
                                        mode: document.getElementById('arcModeBtn').textContent
                                    };
                                })()"""
                            )
                            assert sw_f["title"] == "GRAVITY WAVE" and "M→Flap" in sw_f["mode"], (
                                f"Flappy->Gravity Wave switch bad: {sw_f}"
                            )
                            # Close & relaunch Flappy -> must preserve GRAVITY WAVE title (syncHud fix)
                            relaunch = cdp.eval_js(
                                """(() => {
                                    document.getElementById('arcExitBtn').click();
                                    window.PSWebFlappy.start();
                                    return document.getElementById('arcGameTitle').textContent;
                                })()"""
                            )
                            assert relaunch == "GRAVITY WAVE", f"Flappy relaunch title stale: {relaunch}"

                        cdp.eval_js("document.getElementById('arcExitBtn').click()")
                        cdp.drain_events(0.04)

                    print("[PASS] All 10 Web Arcade games launched, animated frames, switched modes & exited cleanly")

                    # Clean Disconnect check
                    cdp.eval_js("document.getElementById('discBtn').click()")
                    ec.wait_for_condition(
                        "Clean Disconnect returns to authCard",
                        lambda: cdp.eval_js(
                            "!document.getElementById('authCard').classList.contains('hide') && "
                            "document.getElementById('deck').classList.contains('hide')"
                        )
                        is True,
                        timeout=5.0,
                    )
                    reset_dom = cdp.eval_js(
                        "({sc: document.getElementById('scName').textContent, "
                        "title: document.getElementById('slTitle').textContent, "
                        "notes: document.getElementById('slNotes').textContent})"
                    )
                    assert (
                        reset_dom["sc"] == "Scene"
                        and reset_dom["title"] == ""
                        and reset_dom["notes"] == "No speaker notes."
                    ), f"Clean disconnect left stale DOM telemetry: {reset_dom}"
                    cdp.drain_events(0.15)

                    # Notice any non-favicon 0 JS exception / console error requirement
                    assert not cdp.exceptions, f"Unhandled JS runtime exceptions detected: {cdp.exceptions}"
                    assert not cdp.console_errors, f"Browser console errors detected: {cdp.console_errors}"
                    print("[PASS] Clean Disconnect verified with 0 JS exceptions and 0 console errors")
                finally:
                    cdp.close()

    print("=== v9.0.1 WEB REMOTE JS & 10-GAME CDP E2E PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
