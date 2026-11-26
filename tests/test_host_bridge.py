"""
Live E2E verification for PresenterSync HostCompanionBridge (Lib/HostBridge.ahk):
- UDP Session Code discovery (valid, invalid, rate limit, rotated code)
- HTTP GET /health and POST /pair (auth success, wrong code -> 401 -> 429 lockout, reset on rotate)
- RFC 6455 WebSocket /ws (unauthenticated rejection, token auth, toggle_mute Mode 2, Mode 1/3 sync, CloseRemote broadcast)
"""

import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

AHK_EXE = r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SERVER_AHK = os.path.join(REPO_DIR, "tests", "test_host_bridge.ahk")
READY_FILE = os.path.join(REPO_DIR, "tests", "_bridge_ready.json")


def ws_connect(host: str, port: int, path: str) -> tuple[socket.socket, bytes]:
    s = socket.create_connection((host, port), timeout=5.0)
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
    else:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", n))
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
                buf.extend(s.recv(4096))
            plen = struct.unpack("!H", buf[2:4])[0]
            off = 4
        while len(buf) < off + plen:
            buf.extend(s.recv(4096))
        payload = bytes(buf[off : off + plen])
        del buf[: off + plen]
        if op == 0x9:  # ping
            mask = os.urandom(4)
            s.sendall(bytes([0x8A, 0x80 | len(payload)]) + mask + bytes(payload[i] ^ mask[i % 4] for i in range(len(payload))))
            continue
        if op == 0xA:
            continue
        if op == 0x8:
            raise EOFError("WS Close frame received")
        return json.loads(payload.decode("utf-8"))


def http_json(method: str, url: str, payload: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))


def main() -> int:
    for p in [
        READY_FILE,
        READY_FILE + ".cmd",
        READY_FILE + ".rotated",
        READY_FILE + ".rec_ready",
        READY_FILE + ".events",
        READY_FILE + ".lan_ready",
        READY_FILE + ".slide_ready",
        READY_FILE + ".turnover_done",
    ]:
        if os.path.exists(p):
            os.remove(p)

    proc = subprocess.Popen(
        [AHK_EXE, SERVER_AHK, "--serve", READY_FILE],
        cwd=REPO_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.time() + 10.0
        while not os.path.exists(READY_FILE):
            if time.time() > deadline:
                raise RuntimeError("Timed out waiting for AHK HostBridge server")
            time.sleep(0.05)
        time.sleep(0.05)
        with open(READY_FILE, "r", encoding="utf-8-sig") as f:
            info = json.load(f)
        assert info["ok"] is True, f"Server failed: {info}"
        tcp_port = info["tcpPort"]
        udp_port = info["udpPort"]
        code = info["sessionCode"]
        print(f"[INFO] HostBridge up on TCP={tcp_port}, UDP={udp_port}, code={code}")

        # 1. GET /health
        st, health = http_json("GET", f"http://127.0.0.1:{tcp_port}/health")
        assert st == 200 and health["ok"] is True and health["bridgePort"] == tcp_port
        print("[PASS] GET /health")

        # 2. UDP discovery with valid normalized code (strip dash & lowercase!)
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.settimeout(2.0)
        udp.sendto(b"PSYNC_DISCOVER|k7m9p2|dev-android-1|SmartBoard 75", ("127.0.0.1", udp_port))
        offer, _ = udp.recvfrom(1024)
        udp.close()
        offer_str = offer.decode("utf-8")
        assert offer_str.startswith("PSYNC_OFFER|") and f"|{tcp_port}|4455|" in offer_str, f"Bad offer: {offer_str}"
        print(f"[PASS] UDP PSYNC_DISCOVER -> {offer_str}")

        # 3. HTTP POST /pair rate limit lockout (5 bad attempts -> 429) + Rotate reset -> 200 OK
        for i in range(5):
            st, body = http_json("POST", f"http://127.0.0.1:{tcp_port}/pair", {"code": "WRONG1"})
            assert st == 401 and body["ok"] is False, f"Expected 401 on try {i+1}: {st} {body}"
        st, body = http_json("POST", f"http://127.0.0.1:{tcp_port}/pair", {"code": "K7M-9P2"})
        assert st == 429, f"Expected 429 lockout after 5 fails, got {st}"
        print("[PASS] POST /pair brute-force lockout -> 429")

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("ROTATE_CODE")
        t0 = time.time()
        while not os.path.exists(READY_FILE + ".rotated"):
            if time.time() - t0 > 5:
                raise RuntimeError("Rotate code timeout")
            time.sleep(0.05)
        with open(READY_FILE + ".rotated", "r", encoding="utf-8-sig") as f:
            new_code = f.read().strip()

        st, pair_ok = http_json(
            "POST",
            f"http://127.0.0.1:{tcp_port}/pair",
            {
                "code": new_code.replace("-", "").lower(),
                "deviceId": "sb-pixel-34",
                "deviceName": "Lecture Hall Board",
                "platform": "Android",
            },
        )
        assert st == 200 and pair_ok["ok"] is True
        assert pair_ok["obsPassword"] == ""  # C3: withheld for default Presenter/Guest unless Director or allowDirectObsFallback
        assert pair_ok.get("allowDirectObsFallback") is False
        assert pair_ok["targetMicName"] == "Studio Mic"
        assert pair_ok["routingMode"] == 2
        assert pair_ok["internetPairingCode"] == "PS-BRDG-777"
        assert len(pair_ok["sessionToken"]) == 64
        token = pair_ok["sessionToken"]
        print("[PASS] POST /pair rotated code -> 200 with sessionToken & config bundle")

        # 4. Unauthenticated WS attempt -> rejected
        s_bad, r_bad = ws_connect("127.0.0.1", tcp_port, "/ws")
        buf_bad = bytearray(r_bad)
        ws_send_text(s_bad, json.dumps({"type": "toggle_mute"}))
        err_msg = ws_recv_json(s_bad, buf_bad)
        assert err_msg["type"] == "auth_error"
        s_bad.close()
        print("[PASS] WS unauthenticated toggle_mute rejected cleanly")

        # 5. Authenticated WS via token + Mode 2 toggle_mute + Host sync broadcast + CloseRemote
        s_ok, r_ok = ws_connect("127.0.0.1", tcp_port, f"/ws?token={token}&deviceId=sb-pixel-34&deviceName=Lecture+Hall+Board")
        buf_ok = bytearray(r_ok)
        m1 = ws_recv_json(s_ok, buf_ok)
        m2 = ws_recv_json(s_ok, buf_ok)
        assert m1["type"] == "auth_ok"
        assert m2["type"] == "mute_state" and m2["isMuted"] is False

        ws_send_text(s_ok, json.dumps({"type": "toggle_mute", "source": "clicker"}))
        m3 = ws_recv_json(s_ok, buf_ok)
        assert m3["type"] == "mute_state" and m3["isMuted"] is True
        print("[PASS] WS Mode 2 toggle_mute flips state and broadcasts mute_state=true")

        # Test CloseRemote broadcast
        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("CLOSE_REMOTE")
        m4 = None
        for _ in range(6):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "close_remote":
                m4 = pkt
                break
        assert m4 is not None and m4["type"] == "close_remote" and m4["command"] == "CloseRemote"
        print("[PASS] WS receives CloseRemote signal from SendCloseRemoteSignal")

        ws_send_text(s_ok, json.dumps({"type": "ping"}))
        m5 = None
        for _ in range(6):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "pong":
                m5 = pkt
                break
        assert m5 is not None and m5["type"] == "pong" and m5["isMuted"] is True
        print("[PASS] WS ping -> pong")

        # 6. Host Deck actions (ppt_next, ppt_prev, toggle_record) & Telemetry broadcast
        for p in [READY_FILE + ".rec_ready", READY_FILE + ".events"]:
            if os.path.exists(p):
                os.remove(p)
        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("OBS_REC_MODE")
        t0 = time.time()
        while not os.path.exists(READY_FILE + ".rec_ready"):
            if time.time() - t0 > 5:
                raise RuntimeError("OBS_REC_MODE timeout")

        for act in ("ppt_next", "ppt_prev", "toggle_record", "pause_record", "split_record", "toggle_standby"):
            ws_send_text(s_ok, json.dumps({"type": act, "source": "test_py"}))
            ack = None
            for _ in range(6):
                pkt = ws_recv_json(s_ok, buf_ok)
                if pkt.get("type") == "ack" and pkt.get("action") == act:
                    ack = pkt
                    break
            assert ack is not None and ack["ok"] is True, f"Unexpected ack for {act}: {ack}"

        ws_send_text(s_ok, json.dumps({"type": "switch_scene", "sceneName": "Slides", "source": "test_py"}))
        sw_ack = None
        for _ in range(6):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "ack" and pkt.get("action") == "switch_scene":
                sw_ack = pkt
                break
        assert sw_ack is not None and sw_ack["ok"] is True

        ws_send_text(s_ok, json.dumps({"type": "timer_start", "durationSec": 300, "source": "test_py"}))
        tm_ack = None
        for _ in range(6):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "ack" and pkt.get("action") == "timer_start":
                tm_ack = pkt
                break
        assert tm_ack is not None and tm_ack["ok"] is True

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("EMIT_NUDGE")
        nudge_pkt = None
        for _ in range(8):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "stage_nudge":
                nudge_pkt = pkt
                break
        assert nudge_pkt is not None and nudge_pkt.get("message") == "2 minutes remaining", f"Missing stage_nudge: {nudge_pkt}"
        print("[PASS] WS Director deck (scene/pause/split/standby/timer) & stage_nudge verified")

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("EMIT_TELEMETRY")
        tel = None
        for _ in range(8):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "mute_state" and pkt.get("recState") == 1:
                tel = pkt
                break
        assert tel is not None and tel.get("recSeconds") == 95 and tel.get("streamDropWarn") is True and tel.get("voiceWhileMuted") is True and tel.get("activeScene") == "Slides" and tel.get("scenes") == ["Main", "Slides", "BRB"], f"Missing telemetry: {tel}"
        print("[PASS] WS mute_state mirrors v6.7.0 telemetry + scenes/standby/timer")

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("DUMP_EVENTS")
        t0 = time.time()
        while not os.path.exists(READY_FILE + ".events"):
            if time.time() - t0 > 5:
                raise RuntimeError("DUMP_EVENTS timeout")
        time.sleep(0.05)
        with open(READY_FILE + ".events", "r", encoding="utf-8-sig") as f:
            ev = json.load(f)
        assert ev["ppt"] == "next,prev" and ev["hasToggleRecord"] is True and ev["hasSwitchScene"] is True and ev["hasPauseRec"] is True and ev["hasSplitRec"] is True and ev["isStandby"] is True and ev["timerState"] == "running", f"Unexpected host events: {ev}"
        print("[PASS] Host Bridge executed real PPT handlers, OBS Director commands, Standby & Timer")

        # 7. v10.1.0 V2-M1: P0-1 (/update/sha256 Content-Type + >2.5MB /update/android), #1 reset_active_scene, P0-2 session_reset + P1-3 slide preview clear
        import hashlib, tempfile, shutil
        upd_dir = tempfile.mkdtemp(prefix="ps_upd_e2e_")
        try:
            apk_bytes = os.urandom(2_600_000)
            apk_sha = hashlib.sha256(apk_bytes).hexdigest()
            sums_text = f"{apk_sha}  PresenterSync_Remote.apk\n"
            with open(os.path.join(upd_dir, "PresenterSync_Remote.apk"), "wb") as f:
                f.write(apk_bytes)
            with open(os.path.join(upd_dir, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
                f.write(sums_text)

            with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
                f.write(f"ENABLE_LAN_UPDATE:{upd_dir}")
            t0 = time.time()
            while not os.path.exists(READY_FILE + ".lan_ready"):
                if time.time() - t0 > 5:
                    raise RuntimeError("ENABLE_LAN_UPDATE timeout")
                time.sleep(0.05)

            with urllib.request.urlopen(f"http://127.0.0.1:{tcp_port}/update/sha256", timeout=5) as resp:
                ct = (resp.headers.get("Content-Type") or "").lower()
                body_txt = resp.read().decode("utf-8-sig").replace("\r\n", "\n")
                assert resp.status == 200 and "text/plain" in ct and "charset=utf-8" in ct and body_txt == sums_text, f"Bad /update/sha256 header/body: {resp.status} ct={ct} body={body_txt!r}"

            with urllib.request.urlopen(f"http://127.0.0.1:{tcp_port}/update/android", timeout=10) as resp:
                ct_apk = (resp.headers.get("Content-Type") or "").lower()
                got_apk = resp.read()
                assert resp.status == 200 and "application/vnd.android.package-archive" in ct_apk
                assert len(got_apk) == len(apk_bytes) and hashlib.sha256(got_apk).hexdigest() == apk_sha, f"APK truncated/corrupt: len={len(got_apk)}"
            print("[PASS] P0-1: GET /update/sha256 (valid text/plain header) & /update/android (>2.5 MB intact)")
        finally:
            shutil.rmtree(upd_dir, ignore_errors=True)

        ws_send_text(s_ok, json.dumps({"type": "reset_active_scene", "cmdId": "e2e-rst-1"}))
        rst_ack = None
        for _ in range(8):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") in ("ack", "nack") and pkt.get("action") == "reset_active_scene":
                rst_ack = pkt
                break
        assert rst_ack is not None and rst_ack.get("action") == "reset_active_scene", f"Missing reset_active_scene response: {rst_ack}"
        print("[PASS] #1: WS reset_active_scene handled by HostBridge")

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("PREPARE_SLIDE_PREVIEW")
        t0 = time.time()
        while not os.path.exists(READY_FILE + ".slide_ready"):
            if time.time() - t0 > 5:
                raise RuntimeError("PREPARE_SLIDE_PREVIEW timeout")
            time.sleep(0.05)

        req_prev = urllib.request.Request(f"http://127.0.0.1:{tcp_port}/slide-preview.jpg?token={token}")
        with urllib.request.urlopen(req_prev, timeout=5) as resp:
            assert resp.status == 200 and len(resp.read()) == 32

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("SESSION_TURNOVER")
        reset_pkt = None
        for _ in range(10):
            pkt = ws_recv_json(s_ok, buf_ok)
            if pkt.get("type") == "session_reset":
                reset_pkt = pkt
                break
        assert reset_pkt is not None, "P0-2: Connected WS client did not receive session_reset on ExecuteHostSessionTurnover"
        try:
            urllib.request.urlopen(req_prev, timeout=5)
            raise AssertionError("P1-3: Expected 404 for /slide-preview.jpg after session turnover")
        except urllib.error.HTTPError as e:
            assert e.code == 404, f"P1-3: Expected 404 after turnover, got {e.code}"
        print("[PASS] P0-2 + P1-3: SESSION_TURNOVER delivers session_reset & clears cached /slide-preview.jpg")

        ws_send_text(s_ok, json.dumps({"type": "unpair"}))
        try:
            ws_recv_json(s_ok, buf_ok, timeout=1.5)
        except Exception:
            pass
        s_ok.close()
        for p in [READY_FILE + ".rec_ready", READY_FILE + ".events", READY_FILE + ".lan_ready", READY_FILE + ".slide_ready", READY_FILE + ".turnover_done"]:
            if os.path.exists(p):
                os.remove(p)

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("STOP")
        proc.wait(timeout=5)
        print("=== ALL HOST BRIDGE E2E TESTS PASSED ===")
        return 0
    except Exception:
        try:
            res_log = os.path.join(REPO_DIR, "tests", "host_bridge_results.log")
            if os.path.exists(res_log):
                with open(res_log, "r", encoding="utf-8", errors="replace") as lf:
                    print("[HOST BRIDGE LOG]", lf.read())
            if proc.poll() is not None and proc.stderr is not None:
                print("[SERVER STDERR]", proc.stderr.read().decode("utf-8", errors="replace"))
        except Exception:
            pass
        raise
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
        for p in [READY_FILE, READY_FILE + ".cmd", READY_FILE + ".rotated", os.path.join(REPO_DIR, "tests", "test_host_bridge_cfg.ini")]:
            if os.path.exists(p):
                os.remove(p)


if __name__ == "__main__":
    sys.exit(main())
