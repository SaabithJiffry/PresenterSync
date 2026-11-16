"""
Live E2E verification for PresenterSync v6.6.0 Option A:
- Public PS_DISCOVER_V1 UDP beacon (zero secrets, stable hostUuid)
- Legacy PSYNC_DISCOVER coexistence
- Real AHK DiscoverPublicHostsUdp + FollowPairedHostIpShift (DHCP IP-shift auto-follow) + ProbeHostBridgeHealth
- Windows sleep/resume (WM_POWERBROADCAST 0x4 / 0x7) listener re-bind, live sync_resync push & post-wake UDP probe
"""

import json
import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_host_bridge import AHK_EXE, REPO_DIR, SERVER_AHK, http_json, ws_connect, ws_recv_json  # noqa: E402

READY_FILE = os.path.join(REPO_DIR, "tests", "_udp_disc_ready.json")
TEMP_FILES = [
    READY_FILE,
    READY_FILE + ".cmd",
    READY_FILE + ".power",
    os.path.join(REPO_DIR, "tests", "_udp_client_probe.ahk"),
    os.path.join(REPO_DIR, "tests", "_udp_client_probe.out"),
    os.path.join(REPO_DIR, "tests", "test_host_bridge_cfg.ini"),
    os.path.join(REPO_DIR, "tests", "_udp_client_probe.ini"),
]


def clean_temp_files() -> None:
    for p in TEMP_FILES:
        if os.path.exists(p):
            try:
                os.remove(p)
            except OSError:
                pass


def main() -> int:
    clean_temp_files()
    proc = subprocess.Popen(
        [AHK_EXE, "/ErrorStdOut=utf-8", SERVER_AHK, "--serve", READY_FILE],
        cwd=REPO_DIR,
    )
    ws = None
    try:
        t0 = time.time()
        while not os.path.exists(READY_FILE):
            if time.time() - t0 > 12:
                raise TimeoutError("Timed out waiting for HostBridge --serve ready")
            time.sleep(0.05)

        time.sleep(0.05)
        with open(READY_FILE, "r", encoding="utf-8-sig") as f:
            info = json.load(f)
        assert info.get("ok"), f"Bridge start failed: {info}"
        tcp_port = int(info["tcpPort"])
        udp_port = int(info["udpPort"])
        disc_port = int(info["discoverPort"])
        host_uuid = info["hostUuid"]
        sess_code = info["sessionCode"]
        assert disc_port > 0 and len(host_uuid) == 36, f"Bad metadata: {info}"
        print(f"[INFO] Live Bridge TCP={tcp_port} UDP={udp_port} DISCOVER={disc_port} UUID={host_uuid}")

        # 1. Public PS_DISCOVER_V1 UDP probe (zero secrets)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(3.0)
        sock.sendto(b"PS_DISCOVER_V1", ("127.0.0.1", disc_port))
        raw_reply, _ = sock.recvfrom(2048)
        sock.close()
        reply_text = raw_reply.decode("utf-8")
        for secret in ["bridgePass123", "PS-BRDG-777", sess_code, "obsPassword", "sessionToken"]:
            assert secret not in reply_text, f"Secret leaked in public beacon: {secret}"
        beacon = json.loads(reply_text)
        assert beacon["proto"] == "PS_DISCOVER_V1"
        assert beacon["hostUuid"] == host_uuid
        assert int(beacon["bridgePort"]) == tcp_port
        assert int(beacon["obsPort"]) == 4455
        print(f"[PASS] UDP PS_DISCOVER_V1 beacon valid & zero-secret ({beacon['deviceName']} • :{beacon['bridgePort']})")

        # 2. Legacy PSYNC_DISCOVER compatibility
        sock2 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock2.settimeout(3.0)
        sock2.sendto(f"PSYNC_DISCOVER|{sess_code}".encode("utf-8"), ("127.0.0.1", udp_port))
        legacy_reply, _ = sock2.recvfrom(1024)
        sock2.close()
        assert legacy_reply.decode("utf-8").startswith("PSYNC_OFFER|")
        print("[PASS] Legacy PSYNC_DISCOVER coexists cleanly alongside PS_DISCOVER_V1")

        # 3. GET /health exposes matching hostUuid
        st_code, health = http_json("GET", f"http://127.0.0.1:{tcp_port}/health")
        assert st_code == 200 and health.get("ok") and health.get("hostUuid") == host_uuid
        print("[PASS] GET /health reports matching hostUuid")

        # 4. Pair over HTTP /pair & connect live WebSocket
        st_code, pair_resp = http_json("POST", f"http://127.0.0.1:{tcp_port}/pair", {
            "code": sess_code,
            "deviceId": "e2e-disc-win-1",
            "deviceName": "SmartBoard E2E",
            "platform": "Windows",
        })
        assert st_code == 200 and pair_resp.get("ok") and pair_resp.get("hostUuid") == host_uuid
        tok = pair_resp["sessionToken"]
        ws, initial_buf = ws_connect("127.0.0.1", tcp_port, f"/ws?token={tok}&deviceId=e2e-disc-win-1")
        ws_buf = bytearray(initial_buf)
        m1 = ws_recv_json(ws, ws_buf, timeout=3.0)
        m2 = ws_recv_json(ws, ws_buf, timeout=3.0)
        assert m1["type"] == "auth_ok" and m1.get("hostUuid") == host_uuid
        assert m2["type"] == "mute_state"
        print("[PASS] HTTP /pair & WS auth_ok deliver authoritative hostUuid")

        # 5. Real AHK client DiscoverPublicHostsUdp + FollowPairedHostIpShift + ProbeHostBridgeHealth
        probe_ahk = os.path.join(REPO_DIR, "tests", "_udp_client_probe.ahk")
        probe_out = os.path.join(REPO_DIR, "tests", "_udp_client_probe.out")
        probe_ini = os.path.join(REPO_DIR, "tests", "_udp_client_probe.ini")
        ahk_code = f'''#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include "..\\Lib\\WebSocket.ahk"
#Include "..\\Lib\\Crypto.ahk"
#Include "..\\Lib\\Gdip.ahk"
#Include "..\\Lib\\UIA.ahk"
#Include "..\\Lib\\OBS_Network.ahk"
#Include "..\\Lib\\GUI_Config.ahk"
#Include "..\\Lib\\RemoteBridgeClient.ahk"

beacons := DiscoverPublicHostsUdp({disc_port}, 700, ["127.0.0.1"])
cfg := {{ PairedHostUuid: "{host_uuid}", HostAddress: "192.168.55.99, STUDIO.local", HostPort: "4455", BridgePort: "4456", ConfigFile: "{probe_ini}" }}
shift := FollowPairedHostIpShift(cfg, beacons)
hGood := ProbeHostBridgeHealth("127.0.0.1", {tcp_port}, "{host_uuid}", 900)
hBad := ProbeHostBridgeHealth("127.0.0.1", {tcp_port}, "00000000-0000-4000-8000-000000000000", 900)
out := JSON_Dump_Simple(beacons.Length, shift.shifted, shift.newIp, cfg.HostAddress, cfg.BridgePort, hGood.ok, hBad.ok)
FileAppend(out, "{probe_out}", "UTF-8")
ExitApp(0)

JSON_Dump_Simple(bLen, shifted, newIp, hAddr, bPort, okGood, okBad) {{
    return '{{"count":' bLen ',"shifted":' (shifted ? "true" : "false") ',"newIp":"' newIp '","hostAddress":"' hAddr '","bridgePort":"' bPort '","healthGood":' (okGood ? "true" : "false") ',"healthBad":' (okBad ? "true" : "false") '}}'
}}
'''
        with open(probe_ahk, "w", encoding="utf-8") as f:
            f.write(ahk_code)
        ap = subprocess.Popen([AHK_EXE, "/ErrorStdOut=utf-8", probe_ahk], cwd=REPO_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            a_out, a_err = ap.communicate(timeout=12)
        except subprocess.TimeoutExpired:
            ap.kill()
            a_out, a_err = ap.communicate()
            raise AssertionError(f"AHK client probe timed out! stdout={a_out!r} stderr={a_err!r}")
        assert ap.returncode == 0, f"AHK client probe failed ({ap.returncode}): {a_out} {a_err}"
        with open(probe_out, "r", encoding="utf-8-sig") as f:
            probe_res = json.load(f)
        assert probe_res["count"] >= 1, f"Expected >= 1 beacon: {probe_res}"
        assert probe_res["shifted"] is True, f"Expected IP shift: {probe_res}"
        new_ip = probe_res["newIp"]
        assert new_ip != "192.168.55.99" and new_ip != "", f"Invalid newIp: {probe_res}"
        assert probe_res["hostAddress"].startswith(f"{new_ip}, 192.168.55.99"), f"Unexpected hostAddress: {probe_res}"
        assert int(probe_res["bridgePort"]) == tcp_port
        assert probe_res["healthGood"] is True and probe_res["healthBad"] is False
        print(f"[PASS] Windows Remote DiscoverPublicHostsUdp + DHCP IP-shift auto-follow -> {probe_res['hostAddress']}")

        # 6. Simulate Windows sleep & resume (WM_POWERBROADCAST 0x4 -> 0x7)
        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("POWER_SUSPEND")
        t_ps = time.time()
        while not os.path.exists(READY_FILE + ".power"):
            if time.time() - t_ps > 5:
                raise TimeoutError("Timed out waiting for POWER_SUSPEND handling")
            time.sleep(0.03)
        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("POWER_RESUME")

        t_pw = time.time()
        while True:
            if os.path.exists(READY_FILE + ".power"):
                txt = open(READY_FILE + ".power", "r", encoding="utf-8-sig").read()
                if txt.startswith("resumed:"):
                    break
            if time.time() - t_pw > 5:
                raise TimeoutError("Timed out waiting for POWER_RESUME handling")
            time.sleep(0.05)

        resync_msg = None
        for _ in range(5):
            pkt = ws_recv_json(ws, ws_buf, timeout=3.0)
            if pkt.get("type") == "sync_resync":
                resync_msg = pkt
                break
        assert resync_msg is not None and resync_msg.get("reason") == "power_resume", f"Missing sync_resync: {resync_msg}"
        assert resync_msg.get("hostUuid") == host_uuid

        # Verify UDP discovery listener responds again cleanly after wake re-bind
        sock3 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock3.settimeout(3.0)
        sock3.sendto(b"PS_DISCOVER_V1", ("127.0.0.1", disc_port))
        wake_beacon = json.loads(sock3.recvfrom(2048)[0].decode("utf-8"))
        sock3.close()
        assert wake_beacon["hostUuid"] == host_uuid
        print("[PASS] Windows power resume rebound listeners, sent sync_resync over WS, & answered post-wake UDP probe")

        with open(READY_FILE + ".cmd", "w", encoding="utf-8") as f:
            f.write("STOP")
        proc.wait(timeout=5)
        print("=== ALL M6 UDP DISCOVERY & POWER RECOVERY E2E CHECKS PASSED ===")
        return 0
    finally:
        if ws is not None:
            try:
                ws.close()
            except Exception:
                pass
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
        clean_temp_files()


if __name__ == "__main__":
    sys.exit(main())
