"""
E2E Verification for v10.2.0 M4 (#4): True Recursive Source-Level OBS Scene Reset
Exercises live AutoHotkey Host + HostCompanionBridge + WebSocket /ws client
against a Mock OBS WebSocket v5 server containing:
  - Active OBS Group (with active dshow_input camera)
  - Active Nested Scene (with active window_capture + cycle back to root)
  - Disabled item (sceneItemEnabled: false) -> MUST remain untouched
  - browser_source -> PressInputPropertiesButton("refreshnocache")
  - ffmpeg_source -> TriggerMediaInputAction("OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART")
  - wasapi_input_capture ("Studio Mic") -> MUST remain untouched
  - +1500ms GetInputSettings verify returning active=false triggers self-heal "activate"
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


class SceneResetMockObsServer(ec.MockObsWsServer):
    def __init__(self):
        super().__init__(studio_mode=True)
        self.dshow_get_count = 0

    def _dispatch_request(self, rtype: str, rdata: dict) -> dict:
        if rtype == "GetSceneItemList":
            sc = rdata.get("sceneName", "")
            if sc == "Main":
                return {
                    "sceneItems": [
                        {"sceneItemId": 10, "sourceName": "CamGroup", "isGroup": True, "sceneItemEnabled": True},
                        {"sceneItemId": 11, "sourceName": "NestedPiP", "sourceType": "OBS_SOURCE_TYPE_SCENE", "sceneItemEnabled": True},
                        {"sceneItemId": 12, "sourceName": "HiddenCam", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "dshow_input", "sceneItemEnabled": False},
                        {"sceneItemId": 13, "sourceName": "SlideWeb", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "browser_source", "sceneItemEnabled": True},
                        {"sceneItemId": 14, "sourceName": "BumperVid", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "ffmpeg_source", "sceneItemEnabled": True},
                        {"sceneItemId": 15, "sourceName": "Studio Mic", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "wasapi_input_capture", "sceneItemEnabled": True},
                    ]
                }
            if sc == "NestedPiP":
                return {
                    "sceneItems": [
                        {"sceneItemId": 30, "sourceName": "ScreenWin", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "window_capture", "sceneItemEnabled": True},
                        {"sceneItemId": 31, "sourceName": "Main", "sourceType": "OBS_SOURCE_TYPE_SCENE", "sceneItemEnabled": True},
                    ]
                }
            return {"sceneItems": []}
        if rtype == "GetGroupSceneItemList":
            return {
                "sceneItems": [
                    {"sceneItemId": 20, "sourceName": "SonyCam", "sourceType": "OBS_SOURCE_TYPE_INPUT", "inputKind": "dshow_input", "sceneItemEnabled": True}
                ]
            }
        if rtype == "GetInputSettings":
            self.dshow_get_count += 1
            # 1st call: pre-check (active=True); 2nd call: +1500ms verify (simulate stuck False to trigger self-heal)
            return {"inputSettings": {"active": self.dshow_get_count == 1}}
        return super()._dispatch_request(rtype, rdata)


def write_host_runner(ahk_path: str, ready_path: str, obs_port: int) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -35000)
OnError((err, mode) => (FileAppend("ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\JsonCodec.ahk"
#Include "{lib}\\RemoteBridgeClient.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\QrCode.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"
#Include "{lib}\\HostBridge.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
cfg.SessionPairingCode := "RST-404"
cfg.ObsPassword := ""
cfg.EnableWS := true
cfg.EnableRemoteConnections := true
cfg.AudioRoutingMode := 2
cfg.ObsTargetMicName := "Studio Mic"

st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.currentSceneName := "Main"
st.sceneList := ["Main", "Slides", "BRB"]

obsUrl := "ws://127.0.0.1:{obs_port}"
ws := ""
ws := WebSocket(obsUrl, {{
    open: (*) => 0,
    message: (sock, msg) => HandleObsMessage(cfg, st, sock, msg),
    close: (*) => 0,
    error: (*) => 0
}})
st.obsWs := ws

t0 := A_TickCount
while (!st.obsConnected && (A_TickCount - t0) < 5000)
    Sleep(30)
if (!st.obsConnected)
    ExitApp(2)

hb := StartHostCompanionBridge(cfg, st, 0, 0)
if (!IsObject(hb) || !hb.running)
    ExitApp(3)

FileAppend('{{"port":' hb.boundTcpPort ',"code":"RST-404"}}', "{ready_path}", "UTF-8")
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("ps_m4_reset_") as tmp:
        ahk_path = tmp.join("host_reset.ahk")
        ready_path = tmp.join("ready.json")
        with SceneResetMockObsServer() as mock_obs:
            write_host_runner(ahk_path, ready_path, mock_obs.port)
            with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_path]):
                ec.wait_for_condition("Host ready", lambda: os.path.exists(ready_path), timeout=8.0)
                with open(ready_path, "r", encoding="utf-8-sig") as f:
                    ready = json.load(f)
                port = ready["port"]
                status, pair_data = ec.http_json(
                    "POST",
                    f"http://127.0.0.1:{port}/pair",
                    {"code": "RST-404", "deviceId": "py-rst-1", "deviceName": "ResetE2E", "platform": "Python"},
                )
                assert status == 200 and pair_data.get("ok"), f"Pair failed: {status} {pair_data}"
                tok = pair_data["sessionToken"]

                ws, raw_buf = ec.ws_connect("127.0.0.1", port, "/ws")
                buf = bytearray(raw_buf)
                try:
                    ec.ws_send_text(ws, json.dumps({"type": "auth", "protocolVersion": 2, "token": tok, "deviceId": "py-rst-1", "deviceName": "ResetE2E", "platform": "Python"}))
                    ec.wait_ws_packet(ws, buf, lambda m: m.get("type") == "auth_ok", "auth_ok")
                    ec.ws_send_text(ws, json.dumps({"type": "reset_active_scene", "cmdId": "rst-cmd-1"}))
                    ec.wait_ws_packet(ws, buf, lambda m: m.get("type") == "ack" and m.get("action") == "reset_active_scene", "reset ack")

                    # Wait through 600ms restore + 1500ms self-heal verify (~2.4s max)
                    def all_phases_complete() -> bool:
                        with mock_obs._lock:
                            reqs = list(mock_obs.requests)
                        act_presses = [
                            r for r in reqs
                            if r["requestType"] == "PressInputPropertiesButton"
                            and (r.get("requestData") or {}).get("propertyName") == "activate"
                        ]
                        re_enables = [
                            r for r in reqs
                            if r["requestType"] == "SetSceneItemEnabled"
                            and (r.get("requestData") or {}).get("sceneItemEnabled") is True
                        ]
                        return len(act_presses) >= 3 and len(re_enables) >= 2

                    ec.wait_for_condition("Full recursive source reset + 600ms restore + 1500ms self-heal", all_phases_complete, timeout=5.0)
                    with mock_obs._lock:
                        reqs = list(mock_obs.requests)
                finally:
                    ws.close()

                assert any(r["requestType"] == "GetGroupSceneItemList" and r["requestData"].get("sceneName") == "CamGroup" for r in reqs), "Missing group crawl"
                assert any(r["requestType"] == "GetSceneItemList" and r["requestData"].get("sceneName") == "NestedPiP" for r in reqs), "Missing nested scene crawl"
                assert any(r["requestType"] == "PressInputPropertiesButton" and r["requestData"].get("inputName") == "SlideWeb" and r["requestData"].get("propertyName") == "refreshnocache" for r in reqs), "Missing browser refreshnocache"
                assert any(r["requestType"] == "TriggerMediaInputAction" and r["requestData"].get("inputName") == "BumperVid" and r["requestData"].get("mediaAction") == "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART" for r in reqs), "Missing ffmpeg_source restart"
                assert any(r["requestType"] == "SetSceneItemEnabled" and r["requestData"].get("sceneName") == "CamGroup" and r["requestData"].get("sceneItemId") == 20 and r["requestData"].get("sceneItemEnabled") is True for r in reqs), "Missing group dshow re-enable"
                assert any(r["requestType"] == "SetSceneItemEnabled" and r["requestData"].get("sceneName") == "NestedPiP" and r["requestData"].get("sceneItemId") == 30 and r["requestData"].get("sceneItemEnabled") is True for r in reqs), "Missing nested scene item re-enable"
                assert not any((r.get("requestData") or {}).get("sceneItemId") == 12 for r in reqs), "Disabled item id=12 MUST stay untouched"
                assert not any((r.get("requestData") or {}).get("inputName") == "Studio Mic" for r in reqs), "Audio mic MUST stay untouched"

    print("=== v10.2.0 SOURCE SCENE RESET E2E PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
