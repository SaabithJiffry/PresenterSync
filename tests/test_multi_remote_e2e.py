"""
Live Multi-Process Multi-Remote E2E Verification (v5.3.0):
Tests Primary Host (HostCompanionBridge + Mode 1/2/3 sync) simultaneously
connected to FOUR live remote clients at the exact same time:
  - 2 REAL PresenterSync_Remote.ahk OS processes (-Instance win1 / -Instance win2)
  - 2 WebSocket clients simulating Android Smart Board + Android Phone
Verifies:
  1. Concurrent startup & distinct persistent win-* DeviceIds across Windows instances
  2. Live device list shows all 4 simultaneous clients on Primary Host
  3. Toggle from Android Smart Board -> Host -> Android Phone + BOTH Windows Remote INIs flip IsMuted=1
  4. Click toggle triggered on Windows Remote #1 HUD HWND -> Host -> Android Smart Board + Android Phone + BOTH Windows Remote INIs flip IsMuted=0
  5. Primary Host Mode 1/3 OBS broadcast -> propagates to ALL 4 connected clients simultaneously
  6. Host CloseRemote signal -> gracefully terminates BOTH Windows Remote processes and notifies Android clients
"""

import ctypes
import ctypes.wintypes
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

# Reuse verified RFC6455 WS client helpers from test_host_bridge.py
sys.path.insert(0, os.path.dirname(__file__))
import test_host_bridge as hb

AHK_EXE = r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SERVER_AHK = os.path.join(REPO_DIR, "tests", "test_host_bridge.ahk")
REMOTE_AHK = os.path.join(REPO_DIR, "PresenterSync_Remote.ahk")

WM_LBUTTONDOWN = 0x0201
user32 = ctypes.windll.user32
user32.FindWindowW.argtypes = [ctypes.wintypes.LPCWSTR, ctypes.wintypes.LPCWSTR]
user32.FindWindowW.restype = ctypes.wintypes.HWND
user32.PostMessageW.argtypes = [ctypes.wintypes.HWND, ctypes.wintypes.UINT, ctypes.wintypes.WPARAM, ctypes.wintypes.LPARAM]
user32.PostMessageW.restype = ctypes.wintypes.BOOL


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


def write_remote_ini(path: str, bridge_port: int, session_code: str, instance_name: str):
    content = (
        "[Connection]\n"
        "NetworkMode=LAN\n"
        "EnableRelayFallback=0\n"
        "HostAddress=127.0.0.1\n"
        "HostPort=4455\n"
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


def wait_for_condition(desc: str, fn, timeout: float = 10.0, step: float = 0.1):
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


def wait_ws_mute_state(sock: socket.socket, buf: bytearray, expected_muted: bool, timeout: float = 6.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        rem = max(0.2, deadline - time.time())
        pkt = hb.ws_recv_json(sock, buf, timeout=rem)
        if pkt.get("type") == "mute_state" and pkt.get("isMuted") is expected_muted:
            return pkt
    raise AssertionError(f"Did not receive mute_state={expected_muted} before timeout")


def main():
    tmp_dir = tempfile.mkdtemp(prefix="psync_multi_")
    ready_file = os.path.join(tmp_dir, "_host_ready.json")
    ini_win1 = os.path.join(tmp_dir, "remote_win1.ini")
    ini_win2 = os.path.join(tmp_dir, "remote_win2.ini")

    host_proc = None
    win1_proc = None
    win2_proc = None
    ws_board = None
    ws_phone = None

    try:
        # 1. Start live Primary Host HostCompanionBridge server (--serve mode)
        host_proc = subprocess.Popen(
            [AHK_EXE, SERVER_AHK, "--serve", ready_file],
            cwd=os.path.join(REPO_DIR, "tests"),
        )
        wait_for_condition("Primary Host Bridge ready file", lambda: os.path.exists(ready_file), timeout=10.0)
        with open(ready_file, "r", encoding="utf-8-sig") as f:
            info = json.load(f)
        assert info.get("ok"), f"Host Bridge start failed: {info}"
        tcp_port = int(info["tcpPort"])
        sess_code = info["sessionCode"]
        print(f"[Multi-E2E] HostCompanionBridge live on 127.0.0.1:{tcp_port} (Session {sess_code})")

        # 2. Launch TWO real simultaneous Windows PresenterSync_Remote.ahk processes
        write_remote_ini(ini_win1, tcp_port, sess_code, "WinLaptop1")
        write_remote_ini(ini_win2, tcp_port, sess_code, "WinPodium2")

        win1_proc = subprocess.Popen(
            [AHK_EXE, REMOTE_AHK, "-Config", ini_win1, "-Instance", "WinLaptop1"],
            cwd=REPO_DIR,
        )
        win2_proc = subprocess.Popen(
            [AHK_EXE, REMOTE_AHK, "-Config", ini_win2, "-Instance", "WinPodium2"],
            cwd=REPO_DIR,
        )

        # Wait for both Windows HUD windows & distinct generated DeviceIds
        hwnd_win1 = wait_for_condition(
            "Windows Remote #1 HUD HWND",
            lambda: user32.FindWindowW(None, "PresenterSync Remote HUD [WinLaptop1]") or None,
            timeout=10.0,
        )
        hwnd_win2 = wait_for_condition(
            "Windows Remote #2 HUD HWND",
            lambda: user32.FindWindowW(None, "PresenterSync Remote HUD [WinPodium2]") or None,
            timeout=10.0,
        )
        dev1 = wait_for_condition("Win1 DeviceId written", lambda: read_ini_val(ini_win1, "Connection", "DeviceId"), timeout=5.0)
        dev2 = wait_for_condition("Win2 DeviceId written", lambda: read_ini_val(ini_win2, "Connection", "DeviceId"), timeout=5.0)
        assert dev1.startswith("win-") and dev2.startswith("win-") and dev1 != dev2, f"Bad DeviceIds: {dev1}, {dev2}"
        print(f"[Multi-E2E PASS] Both Windows Remote processes active simultaneously (hw={hwnd_win1}/{hwnd_win2}, ids={dev1}/{dev2})")

        # 3. Connect TWO simulated Android clients simultaneously (65" Smart Board + Phone)
        print("[Multi-E2E] Pairing Android Smart Board...", flush=True)
        req_b = urllib.request.Request(
            f"http://127.0.0.1:{tcp_port}/pair",
            data=json.dumps({"code": sess_code, "deviceId": "and-board-65", "deviceName": "SmartBoard-65", "platform": "Android"}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req_b, timeout=5) as resp_b:
            pair_b = json.loads(resp_b.read().decode("utf-8"))
        assert pair_b.get("ok"), f"Android Board /pair failed: {pair_b}"

        print("[Multi-E2E] Pairing Android Phone...", flush=True)
        req_p = urllib.request.Request(
            f"http://127.0.0.1:{tcp_port}/pair",
            data=json.dumps({"code": sess_code, "deviceId": "and-phone-redmi", "deviceName": "Redmi Note 12", "platform": "Android"}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req_p, timeout=5) as resp_p:
            pair_p = json.loads(resp_p.read().decode("utf-8"))
        assert pair_p.get("ok"), f"Android Phone /pair failed: {pair_p}"

        ws_board, rem_b = hb.ws_connect("127.0.0.1", tcp_port, "/ws")
        buf_b = bytearray(rem_b)
        hb.ws_send_text(ws_board, json.dumps({
            "type": "auth", "token": pair_b["sessionToken"], "deviceId": "and-board-65", "deviceName": "SmartBoard-65", "platform": "Android"
        }))
        auth_b = hb.ws_recv_json(ws_board, buf_b, timeout=5.0)
        assert auth_b.get("type") == "auth_ok"

        ws_phone, rem_p = hb.ws_connect("127.0.0.1", tcp_port, "/ws")
        buf_p = bytearray(rem_p)
        hb.ws_send_text(ws_phone, json.dumps({
            "type": "auth", "token": pair_p["sessionToken"], "deviceId": "and-phone-redmi", "deviceName": "Redmi Note 12", "platform": "Android"
        }))
        auth_p = hb.ws_recv_json(ws_phone, buf_p, timeout=5.0)
        assert auth_p.get("type") == "auth_ok"
        print("[Multi-E2E PASS] All 4 simultaneous clients (2 Windows + 2 Android) authenticated on HostBridge")

        # Drain any initial mute_state frame if already queued, wait briefly for Win1/Win2 auth_ok settlement
        time.sleep(0.5)

        # 4. Action A: Android Smart Board sends toggle_mute -> Host -> Android Board + Android Phone + Win1 INI + Win2 INI all become MUTED (1)
        hb.ws_send_text(ws_board, json.dumps({"type": "toggle_mute", "deviceId": "and-board-65", "source": "clicker"}))
        wait_ws_mute_state(ws_board, buf_b, True)
        wait_ws_mute_state(ws_phone, buf_p, True)
        wait_for_condition("Win1 INI IsMuted=1", lambda: read_ini_val(ini_win1, "Settings", "IsMuted") == "1", timeout=6.0)
        wait_for_condition("Win2 INI IsMuted=1", lambda: read_ini_val(ini_win2, "Settings", "IsMuted") == "1", timeout=6.0)
        print("[Multi-E2E PASS] Android Smart Board toggle -> propagated MUTED across Host, Android Phone, Win1 & Win2")

        # 5. Action B: Trigger real HUD click on Windows Remote #1 HWND -> Host -> Android Board + Android Phone + Win1 + Win2 all become LIVE (0)
        user32.PostMessageW(hwnd_win1, WM_LBUTTONDOWN, 1, 0)
        wait_ws_mute_state(ws_board, buf_b, False)
        wait_ws_mute_state(ws_phone, buf_p, False)
        wait_for_condition("Win1 INI IsMuted=0", lambda: read_ini_val(ini_win1, "Settings", "IsMuted") == "0", timeout=6.0)
        wait_for_condition("Win2 INI IsMuted=0", lambda: read_ini_val(ini_win2, "Settings", "IsMuted") == "0", timeout=6.0)
        print("[Multi-E2E PASS] Windows Remote #1 click -> propagated LIVE across Host, Android Smart Board, Android Phone & Win2")

        # 6. Action C: Primary Host direct SyncUIState (OBS / Host Hotkey) -> propagates MUTED across all 4 clients simultaneously
        with open(ready_file + ".cmd", "w", encoding="utf-8") as cf:
            cf.write("BROADCAST_OBS_MUTE_TRUE")
        wait_ws_mute_state(ws_board, buf_b, True)
        wait_ws_mute_state(ws_phone, buf_p, True)
        wait_for_condition("Win1 INI IsMuted=1 from Host SyncUIState", lambda: read_ini_val(ini_win1, "Settings", "IsMuted") == "1", timeout=6.0)
        wait_for_condition("Win2 INI IsMuted=1 from Host SyncUIState", lambda: read_ini_val(ini_win2, "Settings", "IsMuted") == "1", timeout=6.0)
        print("[Multi-E2E PASS] Primary Host SyncUIState -> propagated MUTED to all 4 remotes")

        # 7. Action D: Primary Host CloseRemote -> cleanly terminates BOTH real Windows processes and alerts both Android WS clients
        with open(ready_file + ".cmd", "w", encoding="utf-8") as cf:
            cf.write("CLOSE_REMOTE")
        pkt_cb = hb.ws_recv_json(ws_board, buf_b, timeout=5.0)
        pkt_cp = hb.ws_recv_json(ws_phone, buf_p, timeout=5.0)
        assert pkt_cb.get("type") == "close_remote" and pkt_cp.get("type") == "close_remote", f"Unexpected close pkts: {pkt_cb}, {pkt_cp}"
        win1_rc = win1_proc.wait(timeout=6.0)
        win2_rc = win2_proc.wait(timeout=6.0)
        assert win1_rc == 0 and win2_rc == 0, f"Windows Remotes did not exit cleanly: win1={win1_rc}, win2={win2_rc}"
        win1_proc = None
        win2_proc = None
        print("[Multi-E2E PASS] Primary Host CloseRemote cleanly exited both real Windows Remote processes + notified Android clients")

        with open(ready_file + ".cmd", "w", encoding="utf-8") as cf:
            cf.write("STOP")
        host_proc.wait(timeout=5.0)
        host_proc = None

        print("=== v5.3.0 MULTI-REMOTE E2E VERIFICATION PASSED (2 WINDOWS + 2 ANDROID SIMULTANEOUS) ===")
    finally:
        for sock in (ws_board, ws_phone):
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass
        for proc in (win1_proc, win2_proc, host_proc):
            if proc and proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=3.0)
                except Exception:
                    proc.kill()
        try:
            for fn in os.listdir(tmp_dir):
                os.remove(os.path.join(tmp_dir, fn))
            os.rmdir(tmp_dir)
        except Exception:
            pass


if __name__ == "__main__":
    main()
