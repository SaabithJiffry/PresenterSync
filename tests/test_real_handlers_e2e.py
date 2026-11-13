"""
End-to-End Live WebSocket Integration Test for PresenterSync v2.2.3
Tests the real production handlers from Lib/OBS_Network.ahk, PresenterSync.ahk,
and PresenterSync_Remote.ahk over live localhost RFC 6455 WebSocket v5 servers.
"""

import base64
import hashlib
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")


def encode_frame(payload, opcode=1):
    data = payload.encode("utf-8") if isinstance(payload, str) else payload
    length = len(data)
    frame = bytearray([0x80 | opcode])
    if length <= 125:
        frame.append(length)
    elif length <= 65535:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))
    frame.extend(data)
    return bytes(frame)


def decode_frame(conn):
    try:
        header = conn.recv(2)
        if not header or len(header) < 2:
            return None, None
        b1, b2 = header[0], header[1]
        opcode = b1 & 0x0F
        is_masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            raw_len = conn.recv(2)
            if len(raw_len) < 2:
                return None, None
            length = struct.unpack("!H", raw_len)[0]
        elif length == 127:
            raw_len = conn.recv(8)
            if len(raw_len) < 8:
                return None, None
            length = struct.unpack("!Q", raw_len)[0]
        mask = conn.recv(4) if is_masked else None
        data = bytearray()
        while len(data) < length:
            chunk = conn.recv(length - len(data))
            if not chunk:
                break
            data.extend(chunk)
        if is_masked and mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return opcode, data
    except Exception:
        return None, None


class MockObsServer:
    def __init__(self, password="", initial_muted=False, mic_name='Mic "1"'):
        self.password = password
        self.salt = "saltE2E789"
        self.challenge = "chalE2E123"
        self.mic_muted = initial_muted
        self.mic_name = mic_name
        self.events = []
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(5)
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def expected_auth(self):
        h1 = hashlib.sha256((self.password + self.salt).encode("utf-8")).digest()
        secret = base64.b64encode(h1).decode("utf-8")
        h2 = hashlib.sha256((secret + self.challenge).encode("utf-8")).digest()
        return base64.b64encode(h2).decode("utf-8")

    def _serve(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.sock.accept()
                threading.Thread(target=self._handle_conn, args=(conn,), daemon=True).start()
            except socket.timeout:
                continue
            except OSError:
                break

    def _handle_conn(self, conn):
        try:
            req_raw = conn.recv(4096).decode("utf-8", errors="ignore")
            key = None
            for line in req_raw.splitlines():
                if line.lower().startswith("sec-websocket-key:"):
                    key = line.split(":", 1)[1].strip()
                    break
            if not key:
                conn.close()
                return

            accept = base64.b64encode(
                hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("utf-8")).digest()
            ).decode("utf-8")
            conn.sendall((
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode("utf-8"))

            hello = {"op": 0, "d": {"obsWebSocketVersion": "5.4.0", "rpcVersion": 1}}
            if self.password:
                hello["d"]["authentication"] = {"challenge": self.challenge, "salt": self.salt}
            conn.sendall(encode_frame(json.dumps(hello)))

            while not self.stop_event.is_set():
                opcode, raw = decode_frame(conn)
                if opcode is None or opcode == 8:
                    break
                if opcode == 9:
                    conn.sendall(encode_frame(raw, opcode=10))
                    continue
                if opcode != 1:
                    continue

                payload = json.loads(raw.decode("utf-8", errors="replace"))
                op = payload.get("op")
                d = payload.get("d", {})

                if op == 1:
                    if self.password and d.get("authentication") != self.expected_auth():
                        self.events.append(("auth_rejected", d.get("authentication", "")))
                        conn.sendall(encode_frame(struct.pack("!H", 4009) + b"Authentication failed", opcode=8))
                        break
                    self.events.append(("identified", bool(self.password)))
                    conn.sendall(encode_frame(json.dumps({"op": 2, "d": {"negotiatedRpcVersion": 1}})))
                elif op == 6:
                    req_type = d.get("requestType")
                    req_id = d.get("requestId")
                    req_data = d.get("requestData", {})
                    self.events.append((req_type, req_id, req_data))

                    if req_type == "GetVersion":
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"obsVersion": "30.0"}}
                        })))
                    elif req_type == "GetInputMute":
                        input_name = req_data.get("inputName")
                        if input_name == self.mic_name:
                            conn.sendall(encode_frame(json.dumps({
                                "op": 7,
                                "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"inputMuted": self.mic_muted}}
                            })))
                        else:
                            conn.sendall(encode_frame(json.dumps({
                                "op": 7,
                                "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": False, "code": 600, "comment": "Not found"}}
                            })))
                    elif req_type == "GetRecordStatus":
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"outputActive": False, "outputPaused": False}}
                        })))
                    elif req_type == "GetStudioModeEnabled":
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"studioModeEnabled": True}}
                        })))
                    elif req_type == "GetCurrentProgramScene":
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"currentProgramSceneName": 'Scene "Main" \\ 1'}}
                        })))
                    elif req_type == "ToggleInputMute":
                        self.mic_muted = not self.mic_muted
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}, "responseData": {"inputMuted": self.mic_muted}}
                        })))
                        conn.sendall(encode_frame(json.dumps({
                            "op": 5,
                            "d": {"eventType": "InputMuteStateChanged", "eventData": {"inputName": req_data.get("inputName"), "inputMuted": self.mic_muted}}
                        })))
                        # Also exercise CurrentProgramSceneChanged escaped JSON parsing on host TriggerMute #2
                        if req_id == "HostClickerMute" and not self.mic_muted:
                            conn.sendall(encode_frame(json.dumps({
                                "op": 5,
                                "d": {"eventType": "CurrentProgramSceneChanged", "eventData": {"sceneName": 'Cam / "2" \\ Live'}}
                            })))
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def close(self):
        self.stop_event.set()
        try:
            self.sock.close()
        except Exception:
            pass


def extract_ahk_block(source_text, header_prefix):
    """Extract a balanced-brace top-level class or function from an AHK v2 file."""
    pattern = re.compile(rf"^{re.escape(header_prefix)}[^\n]*\{{", re.MULTILINE)
    m = pattern.search(source_text)
    if not m:
        raise ValueError(f"Could not find block starting with: {header_prefix}")
    start = m.start()
    depth = 0
    in_str = False
    str_char = ""
    i = m.end() - 1
    while i < len(source_text):
        ch = source_text[i]
        if in_str:
            if ch == "`" and i + 1 < len(source_text):
                i += 2
                continue
            if ch == str_char:
                in_str = False
        else:
            if ch in ('"', "'"):
                in_str = True
                str_char = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source_text[start:i + 1]
        i += 1
    raise ValueError(f"Unbalanced braces for: {header_prefix}")


def build_ahk_harness(auth_port, noauth_port, result_path, work_dir):
    host_src = (ROOT_DIR / "PresenterSync.ahk").read_text(encoding="utf-8")
    remote_src = (ROOT_DIR / "PresenterSync_Remote.ahk").read_text(encoding="utf-8")

    host_blocks = [
        extract_ahk_block(host_src, "IsPptKeyNotMute("),
        extract_ahk_block(host_src, "TriggerMute("),
    ]
    remote_blocks = [
        extract_ahk_block(remote_src, "class RemoteConfig"),
        extract_ahk_block(remote_src, "class RemoteState"),
        extract_ahk_block(remote_src, "GetRemoteEffectiveAlpha("),
        extract_ahk_block(remote_src, "ConnectToRemoteOBS("),
        extract_ahk_block(remote_src, "FailoverToNextCandidate("),
        extract_ahk_block(remote_src, "HandleRemoteObsClose("),
        extract_ahk_block(remote_src, "HandleRemoteObsMessage("),
        extract_ahk_block(remote_src, "RemoteHeartbeatTick("),
        extract_ahk_block(remote_src, "SyncRemoteMuteState("),
        extract_ahk_block(remote_src, "RemoveToolTip("),
        extract_ahk_block(remote_src, "OnRemoteClickerMute("),
    ]

    lib_dir = str(ROOT_DIR / "Lib")
    remote_ini = str(work_dir / "remote_e2e.ini")
    host_ini = str(work_dir / "host_e2e.ini")
    harness_path = work_dir / "run_e2e_harness.ahk"

    ahk_code = f"""#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut
#Include "{lib_dir}\\WebSocket.ahk"
#Include "{lib_dir}\\Crypto.ahk"
#Include "{lib_dir}\\Gdip.ahk"
#Include "{lib_dir}\\OBS_Network.ahk"
#Include "{lib_dir}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

PassCount := 0
FailCount := 0

Assert(name, cond, detail := "") {{
    global PassCount, FailCount
    local msgLine
    if (cond) {{
        PassCount += 1
        msgLine := "[PASS] " name (detail != "" ? " - " detail : "")
    }} else {{
        FailCount += 1
        msgLine := "[FAIL] " name (detail != "" ? " - " detail : "")
    }}
    FileAppend(msgLine "`n", "{result_path}", "UTF-8")
}}

FlushAndBail() {{
    if WinExist("WebSocket Setup")
        WinClose("WebSocket Setup")
    FileAppend("[FAIL] Watchdog timeout reached`n", "{result_path}", "UTF-8")
    ExitApp(9)
}}
SetTimer FlushAndBail, -9000

WaitUntil(pred, timeoutMs := 3000) {{
    start := A_TickCount
    while (!pred.Call() && (A_TickCount - start) < timeoutMs)
        Sleep 25
    return pred.Call()
}}

; Stubs referenced by extracted remote config/tray handlers when running headless
CheckRemotePointerEnable(cfg, ThisHotkey) => true
BuildRemoteTrayMenu(cfg, state) => 0

; --- Extracted Real Production Functions (PresenterSync.ahk) ---
{chr(10).join(host_blocks)}

; --- Extracted Real Production Functions (PresenterSync_Remote.ahk) ---
{chr(10).join(remote_blocks)}

; =====================================================================
; TEST 1: PresenterSync_Remote Real Handlers Full-Duplex over TCP WS
; =====================================================================
rCfg := RemoteConfig("{remote_ini}")
rCfg.ObsPassword := "secretHost123"
rCfg.TargetMicName := 'Mic "1"'
rCfg.ShowIndicator := false
rState := RemoteState(rCfg)
rState.MicGui := ""
cand := {{raw: "127.0.0.1:{auth_port}", host: "127.0.0.1", port: "{auth_port}"}}

rWs := WebSocket("ws://127.0.0.1:{auth_port}", {{
    message: HandleRemoteObsMessage.Bind(rCfg, rState, cand),
    close: HandleRemoteObsClose.Bind(rCfg, rState, cand)
}})
rState.obsWs := rWs

Assert("Remote Op 0/1/2 auth connects & receives InitRemoteMute",
    WaitUntil(() => rState.obsConnected && rState.connStatus == "connected" && rState.isMuted == false))

; Remote clicker press -> ToggleInputMute -> Op 5 InputMuteStateChanged
Sleep 180
OnRemoteClickerMute(rCfg, rState)
Assert("Remote clicker press toggles OBS & syncs isMuted=true via Op 5",
    WaitUntil(() => rState.isMuted == true))

; Hardware debounce blocks bounce within 150ms
OnRemoteClickerMute(rCfg, rState)
Sleep 50
Assert("Remote hardware debounce preserves true during 50ms bounce", rState.isMuted == true)

; Valid second click after debounce toggles back to false
Sleep 150
OnRemoteClickerMute(rCfg, rState)
Assert("Remote second clicker press syncs isMuted=false via Op 5",
    WaitUntil(() => rState.isMuted == false))

; Heartbeat keep-alive
RemoteHeartbeatTick(rCfg, rState)
Sleep 60

; Simulate missing mic error then Op 5 recovery inside HandleRemoteObsMessage
HandleRemoteObsMessage(rCfg, rState, cand, rWs, '{{"op":7,"d":{{"requestId":"InitRemoteMute","requestStatus":{{"result":false,"code":600}}}}}}')
Assert("Remote InitRemoteMute result:false sets connStatus=mic_error", rState.connStatus == "mic_error")
HandleRemoteObsMessage(rCfg, rState, cand, rWs, '{{"op":5,"d":{{"eventType":"InputMuteStateChanged","eventData":{{"inputName":"Mic \\"1\\"","inputMuted":true}}}}}}')
Assert("Remote Op 5 InputMuteStateChanged recovers connStatus=connected & isMuted=true",
    rState.connStatus == "connected" && rState.isMuted == true)

; Close with 4009 auth failure sets auth_failed cleanly
rState.obsConnected := false
HandleRemoteObsClose(rCfg, rState, cand, rWs, 4009, "Auth failed")
Assert("Remote HandleRemoteObsClose 4009 sets auth_failed", !rState.obsConnected && rState.connStatus == "auth_failed")
SetTimer rState.reconnectTimerFn, 0
SetTimer rState.heartbeatTimerFn, 0
SetTimer rState.breathTimerFn, 0

; =====================================================================
; TEST 2: Host OBS_Network + TriggerMute Real Handlers over TCP WS (No Auth)
; =====================================================================
hCfg := Config("{host_ini}")
hCfg.EnableWS := true
hCfg.EnablePPT := true
hCfg.ShowIndicator := false
hCfg.AudioRoutingMode := 1
hCfg.ObsMuteHotkey := "None"
hCfg.obsPassword := ""
hCfg.targetMicName := 'Mic "1"'
hCfg.HwMuteHotkey := "Esc"
hState := OverlayState(hCfg)

hWs := WebSocket("ws://127.0.0.1:{noauth_port}", {{
    message: HandleObsMessage.Bind(hCfg, hState),
    close: HandleObsClose.Bind(hCfg, hState)
}})
hState.obsWs := hWs

Assert("Host blank password connects seamlessly to unauthenticated OBS",
    WaitUntil(() => hState.obsConnected && hState.currentSceneName == 'Scene "Main" \\ 1'))

; Host TriggerMute in Mode 1 via WS (ObsMuteHotkey=None)
Sleep 180
TriggerMute(hCfg, hState)
Assert("Host TriggerMute Mode 1 toggles via WS & receives Op 5 mute=true",
    WaitUntil(() => hState.isMuted == true))

; Host TriggerMute in Mode 3 via WS + escaped CurrentProgramSceneChanged parse
Sleep 180
hCfg.AudioRoutingMode := 3
TriggerMute(hCfg, hState)
Assert("Host TriggerMute Mode 3 toggles via WS & parses escaped Scene",
    WaitUntil(() => hState.isMuted == false && hState.currentSceneName == 'Cam / "2" \\ Live'))

try hWs.shutdown()
hState.obsConnected := false

; =====================================================================
; TEST 3: Real 4009 PromptForPassword Save + Cancel Flow in HandleObsClose
; =====================================================================
SubmitPwTimer() {{
    if WinWait("WebSocket Setup",, 2) {{
        hwnd := WinExist("WebSocket Setup")
        ControlSetText("newSecret99", "Edit1", "ahk_id " hwnd)
        Sleep 40
        try WinActivate("ahk_id " hwnd)
        Sleep 40
        ControlSend("{{Enter}}", "Edit1", "ahk_id " hwnd)
    }}
}}
SetTimer SubmitPwTimer, -80
HandleObsClose(hCfg, hState, "", 4009, "Auth failed")
Assert("Host HandleObsClose 4009 saves re-entered password & keeps EnableWS=true",
    hCfg.obsPassword == "newSecret99" && hCfg.EnableWS == true)
SetTimer hState.obsTimerFn, 0

CancelPwTimer() {{
    if WinWait("WebSocket Setup",, 2)
        WinClose("WebSocket Setup")
}}
SetTimer CancelPwTimer, -80
HandleObsClose(hCfg, hState, "", 4009, "Auth failed")
Assert("Host HandleObsClose 4009 cancel disables EnableWS & clears password without Reload",
    hCfg.EnableWS == false && hCfg.obsPassword == "")
SetTimer hState.obsTimerFn, 0
SetTimer FlushAndBail, 0

; =====================================================================
; TEST 4: Real IsPptKeyNotMute Hardware Key Normalization
; =====================================================================
hCfg.HwMuteHotkey := "Esc"
Assert("IsPptKeyNotMute blocks Esc when HwMuteHotkey=Esc", IsPptKeyNotMute(hCfg, "Esc") == false)
hCfg.HwMuteHotkey := "Escape"
Assert("IsPptKeyNotMute blocks Esc when HwMuteHotkey=Escape (GetKeyName alias)", IsPptKeyNotMute(hCfg, "Esc") == false)
hCfg.HwMuteHotkey := "PgDn"
Assert("IsPptKeyNotMute blocks PgDn when HwMuteHotkey=PgDn", IsPptKeyNotMute(hCfg, "PgDn") == false)
Assert("IsPptKeyNotMute allows PgUp when HwMuteHotkey=PgDn", IsPptKeyNotMute(hCfg, "PgUp") == true)
hCfg.HwMuteHotkey := "NumpadEnter"
Assert("IsPptKeyNotMute allows Enter when HwMuteHotkey=NumpadEnter", IsPptKeyNotMute(hCfg, "Enter") == true)
hCfg.HwMuteHotkey := "F5"
Assert("IsPptKeyNotMute allows +F5 when HwMuteHotkey=F5", IsPptKeyNotMute(hCfg, "+F5") == true)
hCfg.HwMuteHotkey := "None"
Assert("IsPptKeyNotMute allows Esc when HwMuteHotkey=None", IsPptKeyNotMute(hCfg, "Esc") == true)

summary := "PASS=" PassCount "`nFAIL=" FailCount "`n"
FileAppend(summary, "{result_path}", "UTF-8")
ExitApp(FailCount > 0 ? 1 : 0)
"""
    harness_path.write_text(ahk_code, encoding="utf-8")
    return harness_path


def main():
    if not AHK_EXE.exists():
        print(f"ERROR: AutoHotkey64.exe not found at {AHK_EXE}", file=sys.stderr)
        sys.exit(2)

    auth_server = MockObsServer(password="secretHost123", initial_muted=False, mic_name='Mic "1"')
    noauth_server = MockObsServer(password="", initial_muted=False, mic_name='Mic "1"')

    try:
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            result_path = work_dir / "e2e_results.txt"
            harness = build_ahk_harness(auth_server.port, noauth_server.port, result_path, work_dir)

            try:
                proc = subprocess.run(
                    [str(AHK_EXE), "/ErrorStdOut", str(harness)],
                    capture_output=True,
                    text=True,
                    timeout=9,
                )
            except subprocess.TimeoutExpired as exc:
                output = result_path.read_text(encoding="utf-8") if result_path.exists() else ""
                print("TIMEOUT! Partial log:\n" + output)
                if exc.stdout:
                    print("STDOUT:", exc.stdout)
                if exc.stderr:
                    print("STDERR:", exc.stderr, file=sys.stderr)
                sys.exit(1)

            output = result_path.read_text(encoding="utf-8") if result_path.exists() else ""
            print(output.strip())
            if proc.stdout.strip():
                print("AHK STDOUT:", proc.stdout.strip())
            if proc.stderr.strip():
                print("STDERR:", proc.stderr.strip(), file=sys.stderr)

            # Verify server-side telemetry matches expectations
            remote_toggles = [e for e in auth_server.events if e[0] == "ToggleInputMute"]
            host_toggles = [e for e in noauth_server.events if e[0] == "ToggleInputMute"]
            keepalives = [e for e in auth_server.events if e[0] == "GetVersion" and e[1] == "KeepAlive"]

            server_checks = [
                ("Server received 2 debounced ToggleInputMute from Remote", len(remote_toggles) == 2),
                ("Server received Remote GetVersion KeepAlive", len(keepalives) == 1),
                ("Server received 2 HostClickerMute ToggleInputMute requests",
                 len(host_toggles) == 2 and all(e[1] == "HostClickerMute" for e in host_toggles)),
            ]
            srv_fail = 0
            for label, ok in server_checks:
                print(f"[{'PASS' if ok else 'FAIL'}] {label}")
                if not ok:
                    srv_fail += 1

            if proc.returncode != 0 or srv_fail > 0 or not output:
                print(f"E2E FAILED (ahk_rc={proc.returncode}, srv_fail={srv_fail})")
                print("Auth server events:", auth_server.events)
                print("NoAuth server events:", noauth_server.events)
                sys.exit(1)

            print("ALL REAL HANDLER E2E CHECKS PASSED")
    finally:
        auth_server.close()
        noauth_server.close()


if __name__ == "__main__":
    main()
