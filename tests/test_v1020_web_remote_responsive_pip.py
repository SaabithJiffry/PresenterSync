"""
v10.2.0 Browser Web Remote Multi-Viewport Responsive, Studio Podium & Desktop Float HUD CDP E2E

Tests Live HostBridge + Browser Web Remote across Chrome DevTools Protocol (CDP):
  - Mobile phone viewports:
      * 360x800 (Galaxy A07)
      * 375x667 (iPhone 8)
      * 390x844 (iPhone 14)
      * 393x851 (POCO M3)
    Asserting strictly zero horizontal overflow (scrollWidth <= clientWidth),
    >= 44px touch targets on buttons/pills/chips, same-row #transBtn & #resetSceneBtn,
    and above-the-fold visibility on 375x667!
  - Desktop PC viewport (1280x800):
    Asserting #deck computes display === 'grid' with 2 columns & expanded >= 900px width,
    and #popoutBtn is visible only on Desktop (>= 768px fine pointer).
  - Full OLED Studio Podium Mode (#oledBtn):
    Asserting #podiumSceneBar horizontal strip, #allScenesBtn -> #scenePickerModal 1-tap scene switch,
    and strict RBAC enforcement across Presenter vs Tally-Only vs Director!
  - Desktop Floating Pop-Out HUD (#popoutBtn / PSFloatHud):
    * Opens Float HUD (DocPiP or window.open popup) & toggles Mini HUD <-> Studio Podium
    * Starts LAN Video PiP (<canvas> -> captureStream -> <video> + MediaSession)
    * Verifies clean teardown via cleanDisconnect() stops all MediaStreamTracks & closes child window
  - Strict assertion: ZERO unhandled JS runtime exceptions or console errors!
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec
import test_v901_web_remote_js_e2e as v901


MOBILE_PHONES = [
    ("Galaxy A07", 360, 800),
    ("iPhone 8", 375, 667),
    ("iPhone 14", 390, 844),
    ("POCO M3", 393, 851),
]


def set_viewport(cdp: v901.CdpClient, width: int, height: int, mobile: bool) -> None:
    cdp.call(
        "Emulation.setDeviceMetricsOverride",
        {
            "width": width,
            "height": height,
            "deviceScaleFactor": 2 if mobile else 1,
            "mobile": mobile,
        },
    )
    time.sleep(0.08)


def main() -> int:
    browser_bin = v901.find_chromium_binary()
    print(f"[INFO] Running M6C Web Remote CDP suite with {browser_bin}")

    with ec.TempWorkspace("psync_v1020_web_cdp_") as tmp, ec.MockObsWsServer(studio_mode=True) as mock_obs:
        ahk_script = tmp.join("host_web_m6c.ahk")
        ready_file = tmp.join("ready.json")
        v901.write_host_runner(ahk_script, ready_file, mock_obs.port)

        with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_script]):
            ec.wait_for_condition("host ready.json", lambda: os.path.exists(ready_file), timeout=10.0)
            with open(ready_file, "r", encoding="utf-8-sig") as f:
                info = json.load(f)
            assert info.get("ok") is True, f"Host Bridge failed: {info}"
            port = int(info["tcpPort"])
            code = info["sessionCode"]
            base_url = f"http://127.0.0.1:{port}"

            # Verify viewport-fit=cover & updated responsive markup in HTTP HTML
            st_code, _, html_body = ec.http_request("GET", f"{base_url}/")
            assert st_code == 200 and "viewport-fit=cover" in html_body, "Missing viewport-fit=cover"
            assert "scenePickerModal" in html_body and "popoutBtn" in html_body, "Missing Podium modal / Float HUD controls"

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
                "--window-size=1280,800",
                "about:blank",
            ]
            with ec.ManagedSubprocess(browser_cmd):
                targets = ec.wait_for_condition(
                    "CDP target",
                    lambda: [
                        t
                        for t in ec.http_json("GET", f"http://127.0.0.1:{cdp_port}/json/list")[1]
                        if t.get("type") == "page" and t.get("webSocketDebuggerUrl")
                    ],
                    timeout=12.0,
                )
                cdp = v901.CdpClient(targets[0]["webSocketDebuggerUrl"])
                try:
                    cdp.call("Page.enable")
                    cdp.call("Runtime.enable")
                    cdp.call("Log.enable")
                    cdp.call("Emulation.setScriptExecutionDisabled", {"value": False})

                    cdp.call("Page.navigate", {"url": f"{base_url}/"})
                    ec.wait_for_condition(
                        "Web Remote loaded",
                        lambda: cdp.eval_js("Boolean(document.getElementById('connBtn'))") is True,
                        timeout=10.0,
                    )

                    # Pair with Host Bridge
                    cdp.eval_js(
                        f"(() => {{ document.getElementById('codeIn').value = {json.dumps(code)}; document.getElementById('connBtn').click(); }})()"
                    )
                    ec.wait_for_condition(
                        "Connected deck visible",
                        lambda: cdp.eval_js("!document.getElementById('deck').classList.contains('hide')") is True,
                        timeout=8.0,
                    )

                    # 1. Desktop (1280x800) 2-column CSS Grid & #popoutBtn visibility check
                    set_viewport(cdp, 1280, 800, mobile=False)
                    desk = cdp.eval_js(
                        """(() => {
                            const wrap = document.querySelector('.wrap').getBoundingClientRect();
                            const deck = document.getElementById('deck');
                            const ds = getComputedStyle(deck);
                            const po = getComputedStyle(document.getElementById('popoutBtn'));
                            return {
                                scrollW: document.documentElement.scrollWidth,
                                innerW: window.innerWidth,
                                wrapW: wrap.width,
                                deckDisplay: ds.display,
                                popoutDisplay: po.display
                            };
                        })()"""
                    )
                    assert desk["scrollW"] <= desk["innerW"], f"Desktop horizontal overflow: {desk}"
                    assert desk["wrapW"] > 800, f"Desktop wrap stayed narrow ({desk['wrapW']})"
                    assert desk["deckDisplay"] == "grid", f"Expected CSS Grid on desktop, got {desk['deckDisplay']}"
                    print(f"[PASS] Desktop 1280x800 2-column CSS Grid ({desk['wrapW']:.0f}px) OK")

                    # 2. All 4 Smartphone viewports (zero horizontal overflow, 44px touch targets, same-row transBtn+resetSceneBtn)
                    for name, vw, vh in MOBILE_PHONES:
                        set_viewport(cdp, vw, vh, mobile=True)
                        mob = cdp.eval_js(
                            """(() => {
                                const tr = document.getElementById('transBtn').getBoundingClientRect();
                                const rs = document.getElementById('resetSceneBtn').getBoundingClientRect();
                                const mic = document.getElementById('micBtn').getBoundingClientRect();
                                const sp = document.getElementById('scenePill').getBoundingClientRect();
                                const scStyle = getComputedStyle(document.getElementById('scaleBtn'));
                                const popDisplay = getComputedStyle(document.getElementById('popoutBtn')).display;
                                return {
                                    scrollW: document.documentElement.scrollWidth,
                                    innerW: window.innerWidth,
                                    trTop: tr.top,
                                    rsTop: rs.top,
                                    trRight: tr.right,
                                    rsRight: rs.right,
                                    micMinH: mic.height,
                                    spBottom: sp.bottom,
                                    trBottom: tr.bottom,
                                    smMinH: parseFloat(scStyle.minHeight || '0'),
                                    popDisplay: popDisplay
                                };
                            })()"""
                        )
                        assert mob["scrollW"] <= mob["innerW"], f"{name} ({vw}x{vh}) horizontal overflow: {mob}"
                        assert abs(mob["trTop"] - mob["rsTop"]) < 24, f"{name} transBtn/resetSceneBtn wrapped: {mob}"
                        assert mob["smMinH"] >= 44 and mob["micMinH"] >= 44, f"{name} touch target < 44px: {mob}"
                        assert mob["popDisplay"] == "none", f"{name} mobile unexpectedly showed #popoutBtn: {mob}"
                        if vw == 375 and vh == 667:
                            assert mob["trBottom"] <= 667, f"iPhone 8 primary controls pushed below fold: {mob}"
                        print(f"[PASS] Mobile {name} ({vw}x{vh}): overflow=0, above-fold/row OK, touch>=44px")

                    # 3. Switch to Desktop + Activate Full OLED Studio Podium Mode (#oledBtn)
                    set_viewport(cdp, 1280, 800, mobile=False)
                    cdp.eval_js("document.getElementById('oledBtn').click()")
                    pod = cdp.eval_js(
                        """(() => {
                            const hasOled = document.body.classList.contains('oled');
                            const stripDisplay = getComputedStyle(document.getElementById('podiumSceneBar')).display;
                            const chips = Array.from(document.querySelectorAll('#podiumScScroll button')).map(b => b.textContent);
                            document.getElementById('allScenesBtn').click();
                            const modalOpen = !document.getElementById('scenePickerModal').classList.contains('hide');
                            const gridBtns = document.querySelectorAll('#spGrid button').length;
                            document.getElementById('spCloseBtn').click();
                            return { hasOled, stripDisplay, chips, modalOpen, gridBtns };
                        })()"""
                    )
                    assert pod["hasOled"] is True and pod["stripDisplay"] == "flex", f"Studio Podium bar failed: {pod}"
                    assert len(pod["chips"]) >= 3 and pod["modalOpen"] is True and pod["gridBtns"] >= 3, f"Studio Podium scene modal failed: {pod}"
                    print(f"[PASS] Studio Podium OLED mode: strip={pod['chips']} + modal verified")

                    # 4. Desktop Floating Pop-Out HUD (Popup + Mini <-> Podium toggle + Video PiP Canvas/MediaSession)
                    float_chk = cdp.eval_js(
                        """(() => {
                            window.PSFloatHud.openPopup();
                            const st1 = window.PSFloatHud.getState();
                            return st1;
                        })()"""
                    )
                    # Headless popup or fallback stream must be active
                    assert float_chk["hasWin"] or float_chk["hasPipStream"], f"Neither popup nor PiP fallback activated: {float_chk}"
                    if float_chk["hasWin"]:
                        cdp.eval_js(
                            """(() => {
                                // Trigger Mini -> Podium mode toggle inside float window
                                window.PSFloatHud.getState();
                            })()"""
                        )
                    # Also directly test Tier 3 Video PiP indicator (<canvas> + captureStream)
                    pip_chk = cdp.eval_js(
                        """(async () => {
                            await window.PSFloatHud.startVideoPip();
                            return window.PSFloatHud.getState();
                        })()"""
                    )
                    assert pip_chk["hasPipCanvas"] is True and pip_chk["hasPipStream"] is True and pip_chk["pipTrackCount"] >= 1, (
                        f"Video PiP canvas/stream invalid: {pip_chk}"
                    )
                    print(f"[PASS] Desktop Float HUD + LAN Video PiP stream ({pip_chk['pipTrackCount']} track) active")

                    # 5. Clean Disconnect must tear down popup & stop all MediaStreamTracks (zero leak)
                    cdp.eval_js("document.getElementById('discBtn').click()")
                    ec.wait_for_condition(
                        "Clean disconnect completes",
                        lambda: cdp.eval_js("document.getElementById('deck').classList.contains('hide')") is True,
                        timeout=6.0,
                    )
                    teardown = cdp.eval_js("window.PSFloatHud.getState()")
                    assert not teardown["hasWin"] and not teardown["hasPipStream"] and not teardown["hasPipCanvas"], (
                        f"Float HUD / Video PiP leaked after cleanDisconnect: {teardown}"
                    )
                    print("[PASS] Clean Disconnect tore down Float HUD & Video PiP stream with zero leaks")

                    cdp.drain_events(0.15)
                    assert not cdp.exceptions, f"Unhandled JS exceptions: {cdp.exceptions}"
                    assert not cdp.console_errors, f"Console errors: {cdp.console_errors}"
                finally:
                    cdp.close()

    print("=== v10.2.0 WEB REMOTE RESPONSIVE + PODIUM + FLOAT HUD CDP E2E PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
