"""
E2E 01: Live Host Bridge + Browser Web Remote + Mock OBS v5 Server
Tests:
  - HTTP GET / and GET /remote (200 OK, text/html, X-Content-Type-Options: nosniff, X-Frame-Options: DENY, Web Remote controls)
  - HTTP GET /health and POST /pair
  - WebSocket /ws auth + transition_scene, slide_start, switch_scene, timer_start, toggle_standby, stage_nudge
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_host_runner(ahk_path: str, ready_path: str, obs_port: int) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -35000)
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
cfg.SessionPairingCode := "WEB-101"
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
st.obsWs := WebSocket("ws://127.0.0.1:{obs_port}")
Sleep(200)
st.obsWs.sendText('{{"op":1,"d":{{"rpcVersion":1}}}}')
Sleep(150)

st.pptNextFn := (*) => true
st.pptPrevFn := (*) => true
st.triggerTransitionFn := (*) => TriggerObsSceneTransition(cfg, st, true)

bridge := StartHostCompanionBridge(cfg, st, 0, 0)
if (!IsObject(bridge) || !bridge.running) {{
    FileAppend('{{"ok":false}}', "{ready_path}", "UTF-8")
    ExitApp(2)
}}
bridge.pairedDevices["web-e2e-01"] := {{
    deviceId: "web-e2e-01",
    deviceName: "WebE2E",
    platform: "Web",
    role: "Director",
    trustTier: "Pinned Room",
    allowDirectObsFallback: false,
    paused: false,
    expiresAt: 0,
    token: ""
}}
info := '{{"ok":true,"tcpPort":' bridge.boundTcpPort ',"sessionCode":"' cfg.SessionPairingCode '"}}'
FileAppend(info, "{ready_path}", "UTF-8")
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("psync_e2e_01_") as tmp, ec.MockObsWsServer(studio_mode=True) as mock_obs:
        ahk_script = tmp.join("host_web_runner.ahk")
        ready_file = tmp.join("ready.json")
        write_host_runner(ahk_script, ready_file, mock_obs.port)

        with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_script]):
            ec.wait_for_condition("host ready.json", lambda: os.path.exists(ready_file), timeout=8.0)
            with open(ready_file, "r", encoding="utf-8-sig") as f:
                info = json.load(f)
            assert info.get("ok") is True, f"Bridge failed to start: {info}"
            port = int(info["tcpPort"])
            code = info["sessionCode"]
            base_url = f"http://127.0.0.1:{port}"
            print(f"[PASS] Live Host Bridge started on 127.0.0.1:{port} (Mock OBS :{mock_obs.port})")

            # 1. GET / and GET /remote security headers & Web Remote HTML
            for path in ["/", "/remote"]:
                st_code, hdrs, body = ec.http_request("GET", f"{base_url}{path}")
                assert st_code == 200, f"GET {path} -> {st_code}"
                assert "text/html" in hdrs.get("content-type", "").lower(), f"Bad Content-Type: {hdrs}"
                assert hdrs.get("x-content-type-options", "").lower() == "nosniff", f"Missing nosniff: {hdrs}"
                assert hdrs.get("x-frame-options", "").upper() == "DENY", f"Missing X-Frame-Options DENY: {hdrs}"
                for ctrl in ["transition_scene", "slide_start", "toggle_mute", "stage_nudge", "timer_start"]:
                    assert ctrl in body, f"Missing '{ctrl}' in Web Remote HTML"
                print(f"[PASS] GET {path} -> 200 text/html + nosniff + X-Frame-Options: DENY + Web Remote controls")

            # 2. GET /health & POST /pair
            h_status, h_json = ec.http_json("GET", f"{base_url}/health")
            assert h_status == 200 and h_json.get("ok") is True and int(h_json.get("bridgePort", 0)) == port
            print("[PASS] GET /health returns 200 ok=true")

            p_status, p_json = ec.http_json(
                "POST",
                f"{base_url}/pair",
                {"code": code, "deviceId": "web-e2e-01", "deviceName": "WebE2E", "platform": "Web"},
            )
            assert p_status == 200 and p_json.get("ok") is True and p_json.get("sessionToken")
            tok = p_json["sessionToken"]
            print("[PASS] POST /pair issued sessionToken")

            # 3. WS /ws Web Remote flow
            ws, buf = ec.ws_connect("127.0.0.1", port, "/ws")
            try:
                wbuf = bytearray(buf)
                ec.ws_send_text(
                    ws,
                    json.dumps(
                        {"type": "auth", "token": tok, "deviceId": "web-e2e-01", "deviceName": "WebE2E", "platform": "Web"}
                    ),
                )
                auth_ok = ec.wait_ws_packet(ws, wbuf, lambda m: m.get("type") == "auth_ok", "auth_ok")
                assert auth_ok.get("type") == "auth_ok"
                ec.wait_ws_packet(ws, wbuf, lambda m: m.get("type") == "mute_state", "initial mute_state")
                print("[PASS] WS /ws authenticated & received initial mute_state")

                # transition_scene -> Mock OBS TriggerStudioModeTransition
                ec.ws_send_text(ws, json.dumps({"type": "transition_scene", "deviceId": "web-e2e-01", "source": "web"}))
                ack_tr = ec.wait_ws_packet(ws, wbuf, lambda m: m.get("type") == "ack" and m.get("action") == "transition_scene", "transition ack")
                assert ack_tr.get("ok") is True
                ec.wait_for_condition("Mock OBS TriggerStudioModeTransition", lambda: mock_obs.count_requests("TriggerStudioModeTransition") >= 1)
                print("[PASS] Web Remote transition_scene -> Mock OBS TriggerStudioModeTransition")

                # switch_scene
                ec.ws_send_text(ws, json.dumps({"type": "switch_scene", "sceneName": "Slides", "deviceId": "web-e2e-01"}))
                ack_sc = ec.wait_ws_packet(ws, wbuf, lambda m: m.get("type") == "ack" and m.get("action") == "switch_scene", "switch_scene ack")
                assert ack_sc.get("ok") is True
                ec.wait_for_condition("Mock OBS SetCurrentProgramScene", lambda: mock_obs.count_requests("SetCurrentProgramScene") >= 1)
                print("[PASS] Web Remote switch_scene -> Mock OBS SetCurrentProgramScene")

                # slide_start, timer_start, toggle_standby, stage_nudge
                for action, payload in [
                    ("slide_start", {"type": "slide_start", "deviceId": "web-e2e-01"}),
                    ("timer_start", {"type": "timer_start", "durationSec": 300, "deviceId": "web-e2e-01"}),
                    ("toggle_standby", {"type": "toggle_standby", "deviceId": "web-e2e-01"}),
                    ("stage_nudge", {"type": "stage_nudge", "message": "2 min left", "deviceId": "web-e2e-01"}),
                ]:
                    ec.ws_send_text(ws, json.dumps(payload))
                    want_types = ("ack", "nack") if action == "slide_start" else ("ack",)
                    ack = ec.wait_ws_packet(ws, wbuf, lambda m, a=action, wt=want_types: m.get("type") in wt and m.get("action") == a, f"{action} ack")
                    assert ack.get("type") in want_types, f"Bad ack for {action}: {ack}"
                print("[PASS] Web Remote slide_start, timer_start, toggle_standby, stage_nudge all acknowledged")
            finally:
                ws.close()

    print("=== E2E 01 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
