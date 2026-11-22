"""
E2E 02: Host Bridge Crash -> Direct OBS v5 Fallback (< 3.5s) -> Bridge Restart Auto-Repromotion
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_fixed_port_host_runner(ahk_path: str, ini_path: str, ready_path: str, bridge_port: int) -> None:
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

cfg := Config("{ini_path}")
cfg.SessionPairingCode := "FAIL-202"
cfg.ObsPassword := ""
cfg.EnableRemoteConnections := true
cfg.AudioRoutingMode := 2
cfg.Write("Bridge", "HostUuid", EnsureHostUuid(cfg))

st := OverlayState(cfg)
st.suppressNudgeBanners := true
bridge := StartHostCompanionBridge(cfg, st, {bridge_port}, {bridge_port})
if (!IsObject(bridge) || !bridge.running) {{
    FileAppend('{{"ok":false}}', "{ready_path}", "UTF-8")
    ExitApp(2)
}}
FileAppend('{{"ok":true,"tcpPort":' bridge.boundTcpPort '}}', "{ready_path}", "UTF-8")
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    remote_ahk = os.path.join(ec.REPO_DIR, "PresenterSync_Remote.ahk")
    with ec.TempWorkspace("psync_e2e_02_") as tmp, ec.MockObsWsServer(studio_mode=True) as mock_obs:
        bridge_port = ec.find_free_loopback_port()
        host_ini = tmp.join("host_shared.ini")
        host_ahk_1 = tmp.join("host1.ahk")
        ready_1 = tmp.join("ready1.json")
        write_fixed_port_host_runner(host_ahk_1, host_ini, ready_1, bridge_port)

        remote_ini = tmp.join("remote_e2e2.ini")
        ec.write_remote_ini(remote_ini, bridge_port, mock_obs.port, "FAIL-202", "e2e2_rem")

        host1 = ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", host_ahk_1])
        try:
            ec.wait_for_condition("Host Bridge #1 ready", lambda: os.path.exists(ready_1), timeout=8.0)
            print(f"[PASS] Host Bridge #1 listening on 127.0.0.1:{bridge_port}")

            with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", remote_ahk, "-Config", remote_ini, "-Instance", "e2e2_rem"]):
                # 1. Remote connects to Host Bridge #1
                ec.wait_for_condition(
                    "Remote paired on Host Bridge #1",
                    lambda: ec.read_ini_val(remote_ini, "Connection", "SessionToken") != "",
                    timeout=8.0,
                )
                print("[PASS] Remote connected & paired with Host Bridge #1")

                # 2. Crash/kill Host Bridge #1 -> verify fallback to Direct OBS v5 within < 3.5s
                host1.terminate()
                ec.wait_for_condition(
                    "Remote falls back to Mock OBS v5",
                    lambda: mock_obs.client_count() >= 1,
                    timeout=3.5,
                )
                print("[PASS] Remote fell back to Direct OBS v5 within < 3.5s after Bridge crash")

                # 3. Verify live mute update from Mock OBS reaches Remote
                mock_obs.broadcast_mute(True)
                ec.wait_for_condition(
                    "Remote INI IsMuted=1 via Direct OBS",
                    lambda: ec.read_ini_val(remote_ini, "Settings", "IsMuted") == "1",
                    timeout=5.0,
                )
                print("[PASS] Direct OBS v5 InputMuteStateChanged propagated to Remote (IsMuted=1)")

                # 4. Restart Host Bridge #2 on same bridge_port + shared HostUuid -> verify auto-repromotion
                host_ahk_2 = tmp.join("host2.ahk")
                ready_2 = tmp.join("ready2.json")
                write_fixed_port_host_runner(host_ahk_2, host_ini, ready_2, bridge_port)
                with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", host_ahk_2]):
                    ec.wait_for_condition("Host Bridge #2 ready", lambda: os.path.exists(ready_2), timeout=8.0)
                    ec.wait_for_condition(
                        "Remote auto-repromoted back to Host Bridge #2 (left Direct OBS)",
                        lambda: mock_obs.client_count() == 0
                        and ec.http_json("GET", f"http://127.0.0.1:{bridge_port}/health")[0] == 200,
                        timeout=14.0,
                    )
                    print("[PASS] Host Bridge #2 restarted & Remote auto-repromoted (left Direct OBS)")
        finally:
            host1.terminate()

    print("=== E2E 02 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
