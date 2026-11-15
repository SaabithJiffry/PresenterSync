"""
End-to-End Live WebSocket Integration Test for PresenterSync v4.5.0
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
        self.clients = []
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(5)
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def broadcast(self, frame_bytes):
        with self.lock:
            targets = list(self.clients)
        for c in targets:
            try:
                c.sendall(frame_bytes)
            except Exception:
                pass

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
                    with self.lock:
                        if conn not in self.clients:
                            self.clients.append(conn)
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
                        self.broadcast(encode_frame(json.dumps({
                            "op": 5,
                            "d": {"eventType": "InputMuteStateChanged", "eventData": {"inputName": req_data.get("inputName"), "inputMuted": self.mic_muted}}
                        })))
                        # Also exercise CurrentProgramSceneChanged escaped JSON parsing on host TriggerMute #2
                        if req_id == "HostClickerMute" and not self.mic_muted:
                            self.broadcast(encode_frame(json.dumps({
                                "op": 5,
                                "d": {"eventType": "CurrentProgramSceneChanged", "eventData": {"sceneName": 'Cam / "2" \\ Live'}}
                            })))
                    elif req_type == "BroadcastCustomEvent":
                        conn.sendall(encode_frame(json.dumps({
                            "op": 7,
                            "d": {"requestType": req_type, "requestId": req_id, "requestStatus": {"result": True, "code": 100}}
                        })))
                        self.broadcast(encode_frame(json.dumps({
                            "op": 5,
                            "d": {"eventType": "CustomEvent", "eventData": req_data.get("eventData", {})}
                        })))
        except Exception:
            pass
        finally:
            with self.lock:
                if conn in self.clients:
                    self.clients.remove(conn)
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
        extract_ahk_block(remote_src, "SyncRemoteBridgeTelemetry("),
        extract_ahk_block(remote_src, "RemoveToolTip("),
        extract_ahk_block(remote_src, "OnRemoteClickerMute("),
        extract_ahk_block(remote_src, "RegisterRemotePointerHotkey("),
        extract_ahk_block(remote_src, "UnregisterRemotePointerHotkey("),
        extract_ahk_block(remote_src, "ExitRemoteApp("),
        extract_ahk_block(remote_src, "RegisterRemoteAppHotkeys("),
        extract_ahk_block(remote_src, "UnregisterRemoteAppHotkeys("),
        extract_ahk_block(remote_src, "ToggleRemotePointerMute("),
        extract_ahk_block(remote_src, "ChangeRemotePointerKeyUI("),
        extract_ahk_block(remote_src, "ChangeRemoteAppHotkeysUI("),
        extract_ahk_block(remote_src, "BuildRemoteHelpStatusLine("),
        extract_ahk_block(remote_src, "ShowRemoteHelpUI("),
        extract_ahk_block(remote_src, "ShowRemoteAboutUI("),
        extract_ahk_block(remote_src, "ShowRemoteConnectionUI("),
        extract_ahk_block(remote_src, "TestConnectionAction("),
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
#Include "{lib_dir}\\RemoteBridgeClient.ahk"

global g_RemoteCli := ParseRemoteCliArgs([])
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

E2EFailFast(exc, mode) {{
    global FailCount
    FailCount += 1
    FileAppend(Format("[FAIL] Unhandled exception ({{}}) in {{}} ({{}}:{{}}): {{}}`n", mode, exc.What, exc.File, exc.Line, exc.Message), "{result_path}", "UTF-8")
    ExitApp(1)
}}
OnError(E2EFailFast)

HardE2EWatchdog() {{
    FileAppend("[FAIL] Hard E2E watchdog timeout reached (13s)`n", "{result_path}", "UTF-8")
    ExitApp(2)
}}
SetTimer HardE2EWatchdog, -13000

FlushAndBail() {{
    if WinExist("WebSocket Setup")
        WinClose("WebSocket Setup")
    FileAppend("[FAIL] Watchdog timeout reached`n", "{result_path}", "UTF-8")
    ExitApp(9)
}}
SetTimer FlushAndBail, -12000

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

; Stale WebSocket guard: messages/closes from old sockets must not clobber active connection state
rStaleWs := {{}}
HandleRemoteObsMessage(rCfg, rState, cand, rStaleWs, '{{"op":5,"d":{{"eventType":"InputMuteStateChanged","eventData":{{"inputName":"Mic \\"1\\"","inputMuted":false}}}}}}')
HandleRemoteObsClose(rCfg, rState, cand, rStaleWs, 4009, "Stale socket close")
Assert("Remote ignores stale WebSocket message & close events",
    rState.obsConnected == true && rState.connStatus == "connected" && rState.isMuted == true)

; Close with 4009 auth failure sets auth_failed cleanly when password was supplied
rState.obsConnected := false
HandleRemoteObsClose(rCfg, rState, cand, rWs, 4009, "Auth failed")
Assert("Remote HandleRemoteObsClose 4009 sets auth_failed", !rState.obsConnected && rState.connStatus == "auth_failed")
SetTimer rState.reconnectTimerFn, 0
SetTimer rState.heartbeatTimerFn, 0
SetTimer rState.breathTimerFn, 0

; Close with 4009 after Hello auth challenge & blank ObsPassword distinguishes pw_required cleanly
savedPass := rCfg.ObsPassword
rCfg.ObsPassword := ""
rState._sawAuthChallenge := true
HandleRemoteObsClose(rCfg, rState, cand, rWs, 4009, "Auth failed")
Assert("Remote HandleRemoteObsClose 4009 w/ blank password + challenge sets pw_required",
    !rState.obsConnected && rState.connStatus == "pw_required")
rCfg.ObsPassword := savedPass
SetTimer rState.reconnectTimerFn, 0

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

; HostClickerMute missing source response resets shared tooltip timer cleanly
HandleObsMessage(hCfg, hState, hWs, '{{"op":7,"d":{{"requestId":"HostClickerMute","requestStatus":{{"result":false,"code":600}}}}}}')
SetTimer(ClearObsNetworkToolTip, 0)
ToolTip()

; Host stale WebSocket guard
hStaleWs := {{}}
HandleObsMessage(hCfg, hState, hStaleWs, '{{"op":5,"d":{{"eventType":"InputMuteStateChanged","eventData":{{"inputName":"Mic \\"1\\"","inputMuted":true}}}}}}')
HandleObsClose(hCfg, hState, hStaleWs, 4009, "Stale host close")
Assert("Host ignores stale WebSocket message & close events",
    hState.obsConnected == true && hState.isMuted == false)

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

; =====================================================================
; TEST 5: Live RefreshHudAppearance Recomputes Headroom & Tier Visibility
; =====================================================================
hudIni := "{work_dir}\\hud_e2e.ini"
hudCfg := Config(hudIni)
hudCfg.ShowIndicator := true
hudCfg.EnableWS := true
hudCfg.EnableZoom := false
hudCfg.ShowExtraHuds := false
vTopHud := SysGet(77)
hudCfg.savedX := 220
hudCfg.savedY := vTopHud + 5
hudState := OverlayState(hudCfg)
InitHUD(hudCfg, hudState, false)
hudCfg.ShowExtraHuds := true
RefreshHudAppearance(hudCfg, hudState)
expectedHudY := vTopHud + hudState.recHeight + hudState.row3Height + hudState.row4Height + (3 * hudState.hudGap)
recVis := DllCall("IsWindowVisible", "Ptr", hudState.RecGui.Hwnd)
studioVis := DllCall("IsWindowVisible", "Ptr", hudState.StudioGui.Hwnd)
streamVis := DllCall("IsWindowVisible", "Ptr", hudState.StreamGui.Hwnd)
hudState.MicGui.Destroy()
hudState.RecGui.Destroy()
hudState.ChatGui.Destroy()
hudState.StudioGui.Destroy()
hudState.SceneGui.Destroy()
hudState.StreamGui.Destroy()
hudState.VCamGui.Destroy()
Assert("RefreshHudAppearance updates savedY headroom & reveals Extra HUD windows",
    hudState.savedY == expectedHudY && recVis != 0 && studioVis != 0 && streamVis != 0)

; =====================================================================
; TEST 6: Dual-Client Live Integration (Host + Remote Multi-Candidate Failover & 2-Way Sync)
; =====================================================================
dualHostCfg := Config("{work_dir}\\dual_host.ini")
dualHostCfg.EnableWS := true
dualHostCfg.EnablePPT := true
dualHostCfg.ShowIndicator := false
dualHostCfg.AudioRoutingMode := 1
dualHostCfg.ObsMuteHotkey := "None"
dualHostCfg.obsPassword := "secretHost123"
dualHostCfg.targetMicName := 'Mic "1"'
dualHostState := OverlayState(dualHostCfg)

dualHostWs := WebSocket("ws://127.0.0.1:{auth_port}", {{
    message: HandleObsMessage.Bind(dualHostCfg, dualHostState),
    close: HandleObsClose.Bind(dualHostCfg, dualHostState)
}}, true, "", 2000)
dualHostState.obsWs := dualHostWs

dualRemCfg := RemoteConfig("{work_dir}\\dual_remote.ini")
dualRemCfg.HostAddress := "127.0.0.1:1, 127.0.0.1:{auth_port}"
dualRemCfg.HostPort := "{auth_port}"
dualRemCfg.ObsPassword := "secretHost123"
dualRemCfg.TargetMicName := 'Mic "1"'
dualRemCfg.ShowIndicator := false
dualRemState := RemoteState(dualRemCfg)
dualRemState.MicGui := ""
ConnectToRemoteOBS(dualRemCfg, dualRemState)

Assert("Dual-client: Remote fails over from offline candidate 1 to live candidate 2 & both connect",
    WaitUntil(() => dualHostState.obsConnected && dualRemState.obsConnected && dualRemState.activeHost == "127.0.0.1:{auth_port}", 4500))

helpLine := BuildRemoteHelpStatusLine(dualRemCfg, dualRemState)
Assert("Dual-client: BuildRemoteHelpStatusLine reflects connected activeHost",
    InStr(helpLine, "Connected to 127.0.0.1:{auth_port}") > 0)

Sleep 180
OnRemoteClickerMute(dualRemCfg, dualRemState)
Assert("Dual-client: Smart Board Remote clicker mutes OBS & syncs BOTH Remote and Primary Host HUD states",
    WaitUntil(() => dualRemState.isMuted == true && dualHostState.isMuted == true))

Sleep 180
TriggerMute(dualHostCfg, dualHostState)
Assert("Dual-client: Primary Host clicker unmutes OBS & syncs BOTH Primary Host and Smart Board Remote HUD states",
    WaitUntil(() => dualHostState.isMuted == false && dualRemState.isMuted == false))

; Test Remote Pointer Mute Toggle (Ctrl+F12 behavior):
; When OFF, clicking pointer on secondary laptop does NOT mute OBS, but live mic status from Primary still updates HUD!
Assert("Remote default shortcuts are ^F12 and !+F12",
    dualRemCfg.PptHotkey == "^F12" && dualRemCfg.ExitHotkey == "!+F12")
ToggleRemotePointerMute(dualRemCfg, dualRemState)
Assert("ToggleRemotePointerMute disables EnablePointerMute", dualRemCfg.EnablePointerMute == false)

Sleep 180
OnRemoteClickerMute(dualRemCfg, dualRemState)
Sleep 120
Assert("When EnablePointerMute=false, secondary laptop clicker does NOT mute OBS",
    dualRemState.isMuted == false && dualHostState.isMuted == false)

; Meanwhile, Primary Host mutes -> secondary laptop still receives live mic status!
Sleep 180
TriggerMute(dualHostCfg, dualHostState)
Assert("When EnablePointerMute=false, secondary laptop HUD still displays live mic status from Primary",
    WaitUntil(() => dualHostState.isMuted == true && dualRemState.isMuted == true))

; Toggle EnablePointerMute back ON and unmute from secondary laptop
ToggleRemotePointerMute(dualRemCfg, dualRemState)
Assert("ToggleRemotePointerMute re-enables EnablePointerMute", dualRemCfg.EnablePointerMute == true)
Sleep 180
OnRemoteClickerMute(dualRemCfg, dualRemState)
Assert("When EnablePointerMute=true, secondary laptop clicker unmutes OBS again",
    WaitUntil(() => dualHostState.isMuted == false && dualRemState.isMuted == false))

; Test Safe Manual Close Remote Companion over LAN BroadcastCustomEvent
closeFlags := {{lan: false, wan: false}}
dualRemState.onRemoteCloseSignal := (*) => (closeFlags.lan := true)
SendCloseRemoteSignal(dualHostCfg, dualHostState)
Assert("Safe manual SendCloseRemoteSignal broadcasts CloseRemote & triggers Remote shutdown handler",
    WaitUntil(() => closeFlags.lan == true))

; Test Internet Relay Mode (Different Networks) end-to-end between Host and Remote
dualHostCfg.RemoteNetworkMode := "Internet"
dualHostCfg.InternetPairingCode := "PS-TEST-2026"
dualRemCfg.NetworkMode := "Internet"
dualRemCfg.InternetPairingCode := "PS-TEST-2026"

; Wire mock relay loopback between Host and Remote
hostRelayOut := []
remRelayOut := []
dualHostState.relayMockWs := {{sendText: (this, pkt) => (hostRelayOut.Push(pkt), HandleRemoteObsMessage(dualRemCfg, dualRemState, {{raw: "Internet (PS-TEST-2026)"}}, dualRemState.obsWs, pkt))}}
dualRemState.relayMockWs := {{sendText: (this, pkt) => (remRelayOut.Push(pkt), HandleHostRelayMessage(dualHostCfg, dualHostState, dualHostState.relayWs, pkt))}}

; Remote clicker press over Internet Relay -> Host toggles OBS -> Host broadcasts state over Relay -> Remote syncs
Sleep 180
OnRemoteClickerMute(dualRemCfg, dualRemState)
Assert("Internet Relay Mode: Remote clicker toggles OBS via Relay & syncs mute state back to Remote",
    WaitUntil(() => dualHostState.isMuted == true && dualRemState.isMuted == true && remRelayOut.Length >= 1 && hostRelayOut.Length >= 1))

; Safe Manual Close over Internet Relay
dualRemState.onRemoteCloseSignal := (*) => (closeFlags.wan := true)
SendCloseRemoteSignal(dualHostCfg, dualHostState)
Assert("Internet Relay Mode: SendCloseRemoteSignal delivers close_remote packet to Remote",
    closeFlags.wan == true)

; Test Internet Relay "event":"open" handshake from ntfy on Remote & Host Relay close refresh
dualRemState.isMuted := false
HandleRemoteObsMessage(dualRemCfg, dualRemState, {{raw: "Internet (PS-TEST-2026)"}}, dualRemState.obsWs, '{{"id":"open1","time":1700000000,"event":"open","topic":"psync_test"}}')
Assert("Internet Relay Mode: Remote 'event':'open' dispatches sync_req and receives Host state",
    dualRemState.isMuted == true)

helpRefreshTracker := {{called: false}}
dualHostState.relayConnected := true
dualHostState.refreshHelpFn := (*) => (helpRefreshTracker.called := true)
HandleHostRelayClose(dualHostCfg, dualHostState, "", 1000, "Normal close")
SetTimer dualHostState.relayTimerFn, 0
Assert("HandleHostRelayClose resets relayConnected=false and notifies refreshHelpFn",
    dualHostState.relayConnected == false && helpRefreshTracker.called == true)

; Test Remote Dialog Windows Geometry & Bounds
AuditRemoteDialog(name, dlgObj, minW := 260, minH := 120) {{
    if (!IsObject(dlgObj) || !WinExist("ahk_id " dlgObj.Hwnd)) {{
        Assert(name " window opens", false)
        return
    }}
    dlgObj.GetClientPos(,, &cw, &ch)
    insideOk := true
    maxBot := 0
    for ctrl in dlgObj {{
        ctrl.GetPos(&x, &y, &w, &h)
        if (x < 0 || y < 0 || (x + w) > (cw + 2) || (y + h) > (ch + 2)) {{
            insideOk := false
            break
        }}
        if (y + h > maxBot)
            maxBot := y + h
    }}
    tabCtrl := ""
    tcy := 0
    for ctrl in dlgObj {{
        if (ctrl.Type = "Tab2" || ctrl.Type = "Tab" || ctrl.Type = "Tab3") {{
            tabCtrl := ctrl
            ctrl.GetPos(, &tcy)
            break
        }}
    }}
    tabRowOk := true
    overlapOk := true
    if IsObject(tabCtrl) {{
        rowCnt := SendMessage(0x132C, 0, 0, tabCtrl.Hwnd)
        tabCnt := SendMessage(0x1304, 0, 0, tabCtrl.Hwnd)
        if (rowCnt != 1)
            tabRowOk := false
        Loop tabCnt {{
            tabCtrl.Choose(A_Index)
            Sleep(15)
            visRects := []
            for vc in dlgObj {{
                if (vc.Type = "Tab2" || vc.Type = "Tab" || vc.Type = "Tab3")
                    continue
                if (!DllCall("IsWindowVisible", "Ptr", vc.Hwnd))
                    continue
                vc.GetPos(&vx, &vy, &vw, &vh)
                visRects.Push({{ x: vx, y: vy, r: vx + vw, b: vy + vh }})
            }}
            Loop visRects.Length {{
                i := A_Index
                a := visRects[i]
                j := i + 1
                while (j <= visRects.Length) {{
                    b := visRects[j]
                    if (Max(0, Min(a.r, b.r) - Max(a.x, b.x)) > 0 && Max(0, Min(a.b, b.b) - Max(a.y, b.y)) > 0)
                        overlapOk := false
                    j += 1
                }}
            }}
        }}
    }}
    WinClose("ahk_id " dlgObj.Hwnd)
    Assert(name " layout, tabs & control bounds valid",
        cw >= minW && ch >= minH && insideOk && (ch - maxBot) >= 8 && tabRowOk && overlapOk,
        Format("Client={{}}x{{}}, maxBot={{}}, tabRowOk={{}}, overlapOk={{}}", cw, ch, maxBot, tabRowOk, overlapOk))
}}

AuditRemoteDialog("Remote OBS Connection UI", ShowRemoteConnectionUI(dualRemCfg, dualRemState, false), 360, 380)
AuditRemoteDialog("Remote App Shortcuts UI", ChangeRemoteAppHotkeysUI(dualRemCfg, dualRemState), 300, 110)
AuditRemoteDialog("Remote Help UI", ShowRemoteHelpUI(dualRemCfg, dualRemState), 580, 440)

remAbout0 := ShowRemoteAboutUI()
remAbout0Edit := "", remAbout0HelpDisabled := false, remAbout0NoOverlap := true
remAboutRects := []
for c in remAbout0 {{
    if (c.Type = "Edit")
        remAbout0Edit := c.Value
    else if (c.Type = "Button" && InStr(c.Text, "Open Help"))
        remAbout0HelpDisabled := !c.Enabled
    c.GetPos(&ax, &ay, &aw, &ah)
    remAboutRects.Push({{ x: ax, y: ay, r: ax + aw, b: ay + ah }})
}}
Loop remAboutRects.Length {{
    ai := A_Index, ar := remAboutRects[ai], aj := ai + 1
    while (aj <= remAboutRects.Length) {{
        br := remAboutRects[aj]
        if (Max(0, Min(ar.r, br.r) - Max(ar.x, br.x)) > 0 && Max(0, Min(ar.b, br.b) - Max(ar.y, br.y)) > 0)
            remAbout0NoOverlap := false
        aj += 1
    }}
}}
remAbout0Hwnd := remAbout0.Hwnd
AuditRemoteDialog("Remote About UI (0-arg)", remAbout0, 440, 440)
try WinWaitClose("ahk_id " remAbout0Hwnd, , 1)
Sleep(30)

remAboutCfg := ShowRemoteAboutUI(dualRemCfg, dualRemState)
remAboutCfgHelpEnabled := false
for c in remAboutCfg {{
    if (c.Type = "Button" && InStr(c.Text, "Open Help"))
        remAboutCfgHelpEnabled := c.Enabled
}}
AuditRemoteDialog("Remote About UI (With Config)", remAboutCfg, 440, 440)
remAboutInc := InStr(remAbout0Edit, "STREAMLINED BY DESIGN") ? StrSplit(remAbout0Edit, "STREAMLINED BY DESIGN")[1] : ""
Assert("Remote About curates strictly Remote capabilities without host bloat",
    remAbout0NoOverlap && remAbout0HelpDisabled && remAboutCfgHelpEnabled
    && InStr(remAbout0Edit, "WHAT REMOTE INCLUDES:")
    && InStr(remAboutInc, "1-Tier LIVE / MUTED Mic HUD")
    && InStr(remAboutInc, "PS-XXXX-XXXX")
    && !InStr(remAboutInc, "Control Center")
    && !InStr(remAboutInc, "Virtual Camera")
    && !InStr(remAboutInc, "Studio Mode"))

remHelpLive := ShowRemoteHelpUI(dualRemCfg, dualRemState)
liveRefreshOk := false
if (IsObject(dualRemState.refreshHelpFn)) {{
    SetHudColorPreset(dualRemCfg, dualRemState, "Broadcast Tally")
    liveRefreshOk := WinExist("ahk_id " remHelpLive.Hwnd) != 0
}}
WinClose("ahk_id " remHelpLive.Hwnd)
try WinWaitClose("ahk_id " remHelpLive.Hwnd, , 1)
SetHudColorPreset(dualRemCfg, dualRemState, "Standard")
remConnectHits := SearchHelpEntries("connect", "All", true)
Assert("Remote Help diagram redraws live on preset change & 'connect' search matches >= 4 entries",
    liveRefreshOk && remConnectHits.Length >= 4,
    Format("liveOk={{}} hits={{}}", liveRefreshOk, remConnectHits.Length))

; Verify IsLocalTcpPortListening & fast non-blocking LAN loopback failover against dead localhost port
tTcp0 := A_TickCount
authOpen := IsLocalTcpPortListening({auth_port})
failFastState := RemoteState(rCfg)
failFastState.MicGui := ""
failFastCfg := RemoteConfig("{remote_ini}")
failFastCfg.NetworkMode := "LAN"
failFastCfg.EnableRelayFallback := false
failFastCfg.HostAddress := "127.0.0.1"
failFastCfg.HostPort := "59997"
failFastState.candidates := ParseCandidateEndpoints(failFastCfg.HostAddress, failFastCfg.HostPort)
failFastState.candidateIndex := 1
ConnectToRemoteOBS(failFastCfg, failFastState)
SetTimer failFastState.reconnectTimerFn, 0
tcpElapsedMs := A_TickCount - tTcp0
Assert("IsLocalTcpPortListening detects open server & ConnectToRemoteOBS skips closed loopback in < 200ms",
    authOpen && !IsLocalTcpPortListening(59997) && !failFastState.obsConnected && tcpElapsedMs < 200,
    Format("authOpen={{}} dt={{}}ms", authOpen, tcpElapsedMs))

SetTimer dualRemState.reconnectTimerFn, 0
SetTimer dualRemState.heartbeatTimerFn, 0
SetTimer dualRemState.breathTimerFn, 0
if IsObject(dualRemState.obsWs)
    try dualRemState.obsWs.shutdown()
if IsObject(dualHostWs)
    try dualHostWs.shutdown()

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
                    timeout=14,
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
            remote_toggles = [e for e in auth_server.events if e[0] == "ToggleInputMute" and e[1] == "RemoteClickerMute"]
            host_toggles = [e for e in noauth_server.events if e[0] == "ToggleInputMute" and e[1] == "HostClickerMute"]
            dual_host_toggles = [e for e in auth_server.events if e[0] == "ToggleInputMute" and e[1] == "HostClickerMute"]
            keepalives = [e for e in auth_server.events if e[0] == "GetVersion" and e[1] == "KeepAlive"]
            close_broadcasts = [e for e in auth_server.events if e[0] == "BroadcastCustomEvent"]

            server_checks = [
                ("Server received 4 debounced ToggleInputMute from Remote (while blocking when EnablePointerMute=false)", len(remote_toggles) == 4),
                ("Server received Remote GetVersion KeepAlive", len(keepalives) == 1),
                ("Server received 2 HostClickerMute ToggleInputMute requests on NoAuth & 3 on Auth",
                 len(host_toggles) == 2 and len(dual_host_toggles) == 3),
                ("Server received BroadcastCustomEvent CloseRemote from Primary Host", len(close_broadcasts) >= 1),
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
