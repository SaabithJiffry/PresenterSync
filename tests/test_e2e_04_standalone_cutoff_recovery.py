"""
E2E 04: Standalone Cutoff Mode (EnableRemoteConnections=false) & Live Bridge Recovery
"""

import json
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_cutoff_host_ahk(ahk_path: str, ready_path: str, cmd_path: str, port: int) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -35000)
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
cfg.SessionPairingCode := "CUT-404"
cfg.EnableRemoteConnections := true
cfg.AudioRoutingMode := 2
st := OverlayState(cfg)
st.suppressNudgeBanners := true

bridge := StartHostCompanionBridge(cfg, st, {port}, {port})
if (!IsObject(bridge) || !bridge.running) {{
    FileAppend('{{"ok":false}}', "{ready_path}", "UTF-8")
    ExitApp(2)
}}
FileAppend('{{"ok":true,"tcpPort":' bridge.boundTcpPort '}}', "{ready_path}", "UTF-8")

PollCmd() {{
    global cfg, st
    if (!FileExist("{cmd_path}"))
        return
    cmd := Trim(FileRead("{cmd_path}", "UTF-8"))
    try FileDelete("{cmd_path}")
    if (cmd = "CUTOFF") {{
        cfg.EnableRemoteConnections := false
        StopHostCompanionBridge()
        FileAppend("CUTOFF_DONE", "{ready_path}.ack", "UTF-8")
    }} else if (cmd = "RECOVER") {{
        cfg.EnableRemoteConnections := true
        StartHostCompanionBridge(cfg, st, {port}, {port})
        FileAppend("RECOVER_DONE", "{ready_path}.ack", "UTF-8")
    }}
}}
SetTimer(PollCmd, 50)
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("psync_e2e_04_") as tmp:
        port = ec.find_free_loopback_port()
        ahk_path = tmp.join("host_cutoff.ahk")
        ready_path = tmp.join("ready.json")
        cmd_path = tmp.join("cmd.txt")
        write_cutoff_host_ahk(ahk_path, ready_path, cmd_path, port)

        with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_path]):
            ec.wait_for_condition("Host ready", lambda: os.path.exists(ready_path), timeout=8.0)

            # 1. Pair & connect WS client
            st_code, p_json = ec.http_json(
                "POST",
                f"http://127.0.0.1:{port}/pair",
                {"code": "CUT-404", "deviceId": "cut-dev-1", "deviceName": "CutDev", "platform": "Web"},
            )
            assert st_code == 200 and p_json.get("sessionToken")
            tok = p_json["sessionToken"]
            ws, buf = ec.ws_connect("127.0.0.1", port, "/ws")
            wbuf = bytearray(buf)
            ec.ws_send_text(ws, json.dumps({"type": "auth", "token": tok, "deviceId": "cut-dev-1", "deviceName": "CutDev", "platform": "Web"}))
            ec.wait_ws_packet(ws, wbuf, lambda m: m.get("type") == "auth_ok", "auth_ok")
            print("[PASS] Client paired & authenticated on Host Bridge")

            # 2. Trigger standalone cutoff -> client evicted & TCP connect refused
            with open(cmd_path, "w", encoding="utf-8") as f:
                f.write("CUTOFF")
            ec.wait_for_condition("CUTOFF ack", lambda: os.path.exists(ready_path + ".ack"), timeout=5.0)
            os.remove(ready_path + ".ack")

            try:
                ws.settimeout(2.0)
                while True:
                    ec.ws_recv_json(ws, wbuf, timeout=2.0)
            except (EOFError, OSError):
                pass
            finally:
                ws.close()
            print("[PASS] Connected WS client evicted on EnableRemoteConnections=false")

            def tcp_refused() -> bool:
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=1.0):
                        return False
                except OSError:
                    return True

            ec.wait_for_condition("TCP connect refused", tcp_refused, timeout=5.0)
            print("[PASS] New TCP connections refused during standalone cutoff")

            # 3. Recover -> Bridge rebinds and accepts reconnection
            with open(cmd_path, "w", encoding="utf-8") as f:
                f.write("RECOVER")
            ec.wait_for_condition("RECOVER ack", lambda: os.path.exists(ready_path + ".ack"), timeout=5.0)

            ws2, buf2 = ec.ws_connect("127.0.0.1", port, "/ws")
            try:
                wbuf2 = bytearray(buf2)
                ec.ws_send_text(ws2, json.dumps({"type": "auth", "code": "CUT-404", "deviceId": "cut-dev-1", "deviceName": "CutDev", "platform": "Web"}))
                auth2 = ec.wait_ws_packet(ws2, wbuf2, lambda m: m.get("type") == "auth_ok", "auth_ok after recover")
                assert auth2.get("type") == "auth_ok"
                print("[PASS] Bridge rebound & accepted WS reconnection on EnableRemoteConnections=true")
            finally:
                ws2.close()

    print("=== E2E 04 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
