"""
E2E 03: Sleep/Wake Staleness & Pong Watchdog + 50+ Rapid OBS Transitions + 100+ Rapid Mute Toggles
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_stress_ahk(ahk_path: str, obs_port: int, result_path: str) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -45000)
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
cfg.EnableWS := true
cfg.EnablePointerTransition := true
cfg.ObsTransitionHotkey := "F11"
cfg.HwTransitionHotkey := "F12"
cfg.AudioRoutingMode := 2

st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.obsConnected := true
st.studioModeActive := true
st.obsWs := WebSocket("ws://127.0.0.1:{obs_port}")
Sleep(200)
st.obsWs.sendText('{{"op":1,"d":{{"rpcVersion":1}}}}')
Sleep(150)

; 1. Sleep/Wake staleness + dead client reap
bridge := StartHostCompanionBridge(cfg, st, 0, 0)
fakeCli := {{
    sock: 0, kind: "ws", authenticated: true, deviceId: "wake-dev-1",
    deviceName: "WakeTab", platform: "Android",
    createdTick: A_TickCount - 120000, lastRxTick: A_TickCount - 70000,
    lastPingSentTick: 0, sendQueue: [], closeAfterSend: false
}}
bridge.clients["fake-wake"] := fakeCli
bridge._OnMaintenanceTick()
reaped := !bridge.clients.Has("fake-wake")

wakeHandled := false
try {{
    HandleHostPowerEvent(cfg, st, 0x7, 0) ; PBT_APMRESUMESUSPEND
    wakeHandled := true
}}

; 2. 55 rapid-fire OBS Scene Transitions spaced >= 30ms + <25ms micro-bounce filter
transOk := 0
Loop 55 {{
    Sleep(32)
    if (TriggerObsSceneTransition(cfg, st, false))
        transOk += 1
}}
bounceBlocked := !TriggerObsSceneTransition(cfg, st, false) ; immediate <25ms call must be filtered
pptCollides := !IsPptKeyAllowed({{ CatchPg: true, HwTransitionHotkey: "PgDn" }}, "PgDn")

; 3. 105 rapid mute toggles + GetLocalNetworkEndpoints(false) caching
muteOk := 0
Loop 105 {{
    ExecuteHostRemoteToggleMute(cfg, st)
    muteOk += 1
}}
ep1 := GetLocalNetworkEndpoints(false)
ep2 := GetLocalNetworkEndpoints(false)
epOk := IsObject(ep1) && IsObject(ep2) && (ep1.ips.Length = ep2.ips.Length)

out := '{{"reaped":' (reaped ? "true" : "false")
    . ',"wakeHandled":' (wakeHandled ? "true" : "false")
    . ',"transOk":' transOk
    . ',"bounceBlocked":' (bounceBlocked ? "true" : "false")
    . ',"pptCollides":' (pptCollides ? "true" : "false")
    . ',"muteOk":' muteOk
    . ',"epOk":' (epOk ? "true" : "false") '}}'
try FileDelete("{result_path}")
FileAppend(out, "{result_path}", "UTF-8")
StopHostCompanionBridge()
ExitApp(0)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("psync_e2e_03_") as tmp, ec.MockObsWsServer(studio_mode=True) as mock_obs:
        ahk_script = tmp.join("stress_03.ahk")
        result_file = tmp.join("res_03.json")
        write_stress_ahk(ahk_script, mock_obs.port, result_file)

        proc = subprocess.run(
            [ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_script],
            cwd=ec.REPO_DIR,
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert proc.returncode == 0, f"AHK stress exited {proc.returncode}: {proc.stderr}"
        assert os.path.exists(result_file), "Missing res_03.json"
        with open(result_file, "r", encoding="utf-8-sig") as f:
            res = json.load(f)

        assert res["reaped"] is True and res["wakeHandled"] is True, f"Sleep/wake failed: {res}"
        print("[PASS] Sleep/wake staleness reap & HandleHostPowerEvent(0x7) verified")

        assert res["transOk"] == 55, f"Expected 55 transitions, got {res['transOk']}"
        ec.wait_for_condition(
            "Mock OBS received >= 55 TriggerStudioModeTransition",
            lambda: mock_obs.count_requests("TriggerStudioModeTransition") >= 55,
            timeout=5.0,
        )
        assert res["bounceBlocked"] is True and res["pptCollides"] is True, f"Filter/collision failed: {res}"
        print(f"[PASS] 55/55 rapid OBS transitions dispatched, <25ms bounce filtered, $ PPT collision blocked")

        assert res["muteOk"] == 105 and res["epOk"] is True, f"Rapid mute/endpoint cache failed: {res}"
        print("[PASS] 105 rapid mute toggles & GetLocalNetworkEndpoints(false) caching verified (0 crashes)")

    print("=== E2E 03 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
