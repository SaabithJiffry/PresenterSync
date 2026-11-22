"""
Shared multi-process Python + AutoHotkey v2 E2E test harness helpers.
Strictly binds to 127.0.0.1, uses ephemeral ports and isolated temp dirs,
and guarantees process-tree cleanup on exit.
"""

import atexit
import base64
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

AHK_EXE = r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def find_free_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def ws_connect(host: str, port: int, path: str, timeout: float = 5.0) -> tuple[socket.socket, bytes]:
    s = socket.create_connection((host, port), timeout=timeout)
    s.settimeout(timeout)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode("ascii")
    s.sendall(req)

    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise RuntimeError("EOF before 101 Switching Protocols")
        buf += chunk
    idx = buf.index(b"\r\n\r\n") + 4
    hdr = buf[:idx].decode("utf-8", errors="replace")
    rest = buf[idx:]
    assert "101 " in hdr, f"Expected 101 Switching Protocols, got: {hdr}"
    expected_accept = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    ).decode("ascii")
    assert expected_accept in hdr, f"Bad Sec-WebSocket-Accept in {hdr}"
    return s, rest


def ws_send_text(s: socket.socket, text: str) -> None:
    payload = text.encode("utf-8")
    mask = os.urandom(4)
    header = bytearray([0x81])
    n = len(payload)
    if n <= 125:
        header.append(0x80 | n)
    elif n <= 65535:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", n))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", n))
    header.extend(mask)
    masked = bytes(payload[i] ^ mask[i % 4] for i in range(n))
    s.sendall(bytes(header) + masked)


def ws_recv_json(s: socket.socket, buf: bytearray, timeout: float = 5.0) -> dict:
    s.settimeout(timeout)
    while True:
        while len(buf) < 2:
            chunk = s.recv(4096)
            if not chunk:
                raise EOFError("Socket closed")
            buf.extend(chunk)
        b0, b1 = buf[0], buf[1]
        op = b0 & 0x0F
        plen = b1 & 0x7F
        off = 2
        if plen == 126:
            while len(buf) < 4:
                chunk = s.recv(4096)
                if not chunk:
                    raise EOFError("Socket closed")
                buf.extend(chunk)
            plen = struct.unpack("!H", buf[2:4])[0]
            off = 4
        elif plen == 127:
            while len(buf) < 10:
                chunk = s.recv(4096)
                if not chunk:
                    raise EOFError("Socket closed")
                buf.extend(chunk)
            plen = struct.unpack("!Q", buf[2:10])[0]
            off = 10
        while len(buf) < off + plen:
            chunk = s.recv(4096)
            if not chunk:
                raise EOFError("Socket closed")
            buf.extend(chunk)
        payload = bytes(buf[off : off + plen])
        del buf[: off + plen]
        if op == 0x9:  # ping -> pong
            mask = os.urandom(4)
            s.sendall(
                bytes([0x8A, 0x80 | len(payload)])
                + mask
                + bytes(payload[i] ^ mask[i % 4] for i in range(len(payload)))
            )
            continue
        if op == 0xA:
            continue
        if op == 0x8:
            raise EOFError("WS Close frame received")
        return json.loads(payload.decode("utf-8"))


def http_request(
    method: str, url: str, payload: dict | None = None, timeout: float = 5.0
) -> tuple[int, dict[str, str], str]:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            hdrs = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, hdrs, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        hdrs = {k.lower(): v for k, v in e.headers.items()} if e.headers else {}
        return e.code, hdrs, e.read().decode("utf-8", errors="replace")


def http_json(method: str, url: str, payload: dict | None = None, timeout: float = 5.0) -> tuple[int, dict]:
    status, _, body = http_request(method, url, payload=payload, timeout=timeout)
    return status, json.loads(body)


def read_ini_val(path: str, section: str, key: str) -> str:
    if not os.path.exists(path):
        return ""
    cur_sec = ""
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith(";"):
                continue
            if s.startswith("[") and s.endswith("]"):
                cur_sec = s[1:-1].strip()
                continue
            if cur_sec.lower() == section.lower() and "=" in s:
                k, v = s.split("=", 1)
                if k.strip().lower() == key.lower():
                    return v.strip()
    return ""


def write_remote_ini(
    path: str,
    bridge_port: int,
    obs_port: int,
    session_code: str,
    instance_name: str,
    host: str = "127.0.0.1",
) -> None:
    content = (
        "[Connection]\n"
        "NetworkMode=LAN\n"
        "EnableRelayFallback=0\n"
        f"HostAddress={host}\n"
        f"HostPort={obs_port}\n"
        f"BridgePort={bridge_port}\n"
        f"SessionPairingCode={session_code}\n"
        "TargetMicName=Studio Mic\n"
        f"InstanceName={instance_name}\n"
        "[Settings]\n"
        "FirstRun=0\n"
        "IsMuted=0\n"
        "[Appearance]\n"
        "ShowIndicator=1\n"
        "EnableHudClickActions=1\n"
        "EnableAudioCue=0\n"
        "EnableMuteToast=0\n"
        "[Pointer]\n"
        "EnablePointerMute=1\n"
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def wait_for_condition(desc: str, fn, timeout: float = 6.0, step: float = 0.08):
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            res = fn()
            if res:
                return res
        except Exception as e:
            last_err = e
        time.sleep(step)
    raise AssertionError(f"Timed out after {timeout}s waiting for: {desc} (last_err={last_err})")


def wait_ws_packet(sock: socket.socket, buf: bytearray, predicate, desc: str = "packet", timeout: float = 5.0) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        rem = max(0.2, deadline - time.time())
        pkt = ws_recv_json(sock, buf, timeout=rem)
        if predicate(pkt):
            return pkt
    raise AssertionError(f"Timed out waiting for WS {desc} after {timeout}s")


class TempWorkspace:
    def __init__(self, prefix: str = "psync_e2e_"):
        self.path = tempfile.mkdtemp(prefix=prefix)
        atexit.register(self.cleanup)

    def join(self, *parts: str) -> str:
        return os.path.join(self.path, *parts)

    def cleanup(self) -> None:
        shutil.rmtree(self.path, ignore_errors=True)

    def __enter__(self) -> "TempWorkspace":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.cleanup()


class ManagedSubprocess:
    def __init__(self, cmd: list[str], cwd: str = REPO_DIR):
        self.proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        atexit.register(self.terminate)

    @property
    def pid(self) -> int:
        return self.proc.pid

    def poll(self):
        return self.proc.poll()

    def terminate(self) -> None:
        if self.proc.poll() is not None:
            return
        try:
            self.proc.terminate()
            self.proc.wait(timeout=2.0)
        except Exception:
            pass
        if self.proc.poll() is None:
            try:
                subprocess.run(
                    ["taskkill", "/T", "/F", "/PID", str(self.proc.pid)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5.0,
                )
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass

    def __enter__(self) -> "ManagedSubprocess":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.terminate()


class MockObsWsServer:
    """Pure-Python OBS WebSocket v5 mock server bound strictly to 127.0.0.1."""

    def __init__(self, studio_mode: bool = True):
        self.port = find_free_loopback_port()
        self.studio_mode = studio_mode
        self.current_scene = "Main"
        self.scenes = ["Main", "Slides", "BRB"]
        self.muted = False
        self.recording = False
        self.requests: list[dict] = []
        self._lock = threading.Lock()
        self._clients: list[socket.socket] = []
        self._stop = threading.Event()
        self._srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._srv.bind(("127.0.0.1", self.port))
        self._srv.listen(8)
        self._srv.settimeout(0.25)
        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        atexit.register(self.close)

    def _accept_loop(self) -> None:
        while not self._stop.is_set():
            try:
                cli, _ = self._srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handle_client, args=(cli,), daemon=True).start()

    @staticmethod
    def _send_server_text(cli: socket.socket, obj: dict) -> None:
        data = json.dumps(obj).encode("utf-8")
        hdr = bytearray([0x81])
        n = len(data)
        if n <= 125:
            hdr.append(n)
        elif n <= 65535:
            hdr.append(126)
            hdr.extend(struct.pack("!H", n))
        else:
            hdr.append(127)
            hdr.extend(struct.pack("!Q", n))
        cli.sendall(bytes(hdr) + data)

    @staticmethod
    def _recv_client_frame(cli: socket.socket, buf: bytearray) -> tuple[int, bytes]:
        while len(buf) < 2:
            chunk = cli.recv(4096)
            if not chunk:
                raise EOFError()
            buf.extend(chunk)
        op = buf[0] & 0x0F
        masked = (buf[1] & 0x80) != 0
        plen = buf[1] & 0x7F
        off = 2
        if plen == 126:
            while len(buf) < 4:
                buf.extend(cli.recv(4096))
            plen = struct.unpack("!H", buf[2:4])[0]
            off = 4
        elif plen == 127:
            while len(buf) < 10:
                buf.extend(cli.recv(4096))
            plen = struct.unpack("!Q", buf[2:10])[0]
            off = 10
        mask_len = 4 if masked else 0
        while len(buf) < off + mask_len + plen:
            chunk = cli.recv(4096)
            if not chunk:
                raise EOFError()
            buf.extend(chunk)
        if masked:
            mask = bytes(buf[off : off + 4])
            raw = bytes(buf[off + 4 : off + 4 + plen])
            payload = bytes(raw[i] ^ mask[i % 4] for i in range(plen))
        else:
            payload = bytes(buf[off : off + plen])
        del buf[: off + mask_len + plen]
        return op, payload

    def _handle_client(self, cli: socket.socket) -> None:
        try:
            cli.settimeout(5.0)
            buf = b""
            while b"\r\n\r\n" not in buf:
                chunk = cli.recv(4096)
                if not chunk:
                    return
                buf += chunk
            idx = buf.index(b"\r\n\r\n") + 4
            hdr_text = buf[:idx].decode("utf-8", errors="replace")
            ws_buf = bytearray(buf[idx:])
            ws_key = ""
            for line in hdr_text.splitlines():
                if line.lower().startswith("sec-websocket-key:"):
                    ws_key = line.split(":", 1)[1].strip()
                    break
            accept = base64.b64encode(
                hashlib.sha1((ws_key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
            ).decode("ascii")
            cli.sendall(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                ).encode("ascii")
            )
            self._send_server_text(cli, {"op": 0, "d": {"obsWebSocketVersion": "5.4.0", "rpcVersion": 1}})
            with self._lock:
                self._clients.append(cli)

            cli.settimeout(0.5)
            while not self._stop.is_set():
                try:
                    op, payload = self._recv_client_frame(cli, ws_buf)
                except socket.timeout:
                    continue
                if op == 0x8:
                    break
                if op == 0x9:
                    cli.sendall(bytes([0x8A, len(payload)]) + payload)
                    continue
                if op != 0x1:
                    continue
                msg = json.loads(payload.decode("utf-8"))
                m_op = msg.get("op")
                d = msg.get("d", {})
                if m_op == 1:
                    self._send_server_text(cli, {"op": 2, "d": {"negotiatedRpcVersion": 1}})
                elif m_op == 6:
                    rtype = d.get("requestType", "")
                    rid = d.get("requestId", "")
                    rdata = d.get("requestData") or {}
                    with self._lock:
                        self.requests.append({"requestType": rtype, "requestId": rid, "requestData": rdata, "ts": time.time()})
                    resp_data = self._dispatch_request(rtype, rdata)
                    self._send_server_text(
                        cli,
                        {
                            "op": 7,
                            "d": {
                                "requestType": rtype,
                                "requestId": rid,
                                "requestStatus": {"result": True, "code": 100},
                                "responseData": resp_data,
                            },
                        },
                    )
        except Exception:
            pass
        finally:
            with self._lock:
                if cli in self._clients:
                    self._clients.remove(cli)
            try:
                cli.close()
            except Exception:
                pass

    def _dispatch_request(self, rtype: str, rdata: dict) -> dict:
        if rtype == "TriggerStudioModeTransition":
            idx = self.scenes.index(self.current_scene) if self.current_scene in self.scenes else 0
            self.current_scene = self.scenes[(idx + 1) % len(self.scenes)]
            return {}
        if rtype == "SetCurrentProgramScene":
            sc = rdata.get("sceneName", "")
            if sc:
                self.current_scene = sc
            return {}
        if rtype == "GetCurrentProgramScene":
            return {"currentProgramSceneName": self.current_scene}
        if rtype == "GetSceneList":
            return {
                "currentProgramSceneName": self.current_scene,
                "scenes": [{"sceneIndex": i, "sceneName": s} for i, s in enumerate(self.scenes)],
            }
        if rtype == "GetStudioModeEnabled":
            return {"studioModeEnabled": self.studio_mode}
        if rtype == "ToggleInputMute":
            self.muted = not self.muted
            return {"inputMuted": self.muted}
        if rtype == "SetInputMute":
            self.muted = bool(rdata.get("inputMuted", self.muted))
            return {}
        if rtype == "GetInputMute":
            return {"inputMuted": self.muted}
        if rtype == "GetInputList":
            return {"inputs": [{"inputName": "Studio Mic", "inputKind": "wasapi_input_capture"}]}
        if rtype == "ToggleRecord":
            self.recording = not self.recording
            return {}
        if rtype == "GetRecordStatus":
            return {"outputActive": self.recording, "outputPaused": False}
        return {}

    def broadcast_mute(self, muted: bool, input_name: str = "Studio Mic") -> None:
        self.muted = muted
        pkt = {"op": 5, "d": {"eventType": "InputMuteStateChanged", "eventIntent": 1, "eventData": {"inputName": input_name, "inputMuted": muted}}}
        with self._lock:
            for c in list(self._clients):
                try:
                    self._send_server_text(c, pkt)
                except Exception:
                    pass

    def count_requests(self, request_type: str) -> int:
        with self._lock:
            return sum(1 for r in self.requests if r["requestType"] == request_type)

    def client_count(self) -> int:
        with self._lock:
            return len(self._clients)

    def close(self) -> None:
        self._stop.set()
        with self._lock:
            for c in list(self._clients):
                try:
                    c.close()
                except Exception:
                    pass
            self._clients.clear()
        try:
            self._srv.close()
        except Exception:
            pass

    def __enter__(self) -> "MockObsWsServer":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()
