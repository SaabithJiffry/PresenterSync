"""
E2E 06: CLI WM_COPYDATA Forwarding, DiagnosticLogger 50-Breadcrumb & Redaction,
        ApplyWindowCaptureAffinity, Watchdogs, AES-256-GCM Relay & Smart Board 0.5x-5.0x Metrics
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_ipc_receiver_ahk(ahk_path: str, ready_path: str, log_path: str) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -25000)
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
cfg.ObsTransitionHotkey := "F11"
st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.obsConnected := false
st.triggerMuteFn := (*) => (st.isMuted := !st.isMuted)

ipcGui := Gui("+ToolWindow", "PresenterSync_HostIpcMsg")
ipcGui.Show("Hide")
OnHostCopyDataMsg(wP, lP, msg, hwnd) {{
    if (hwnd != ipcGui.Hwnd)
        return 0
    dw := NumGet(lP, 0, "UPtr")
    cb := NumGet(lP, A_PtrSize, "UInt")
    lp := NumGet(lP, A_PtrSize * 2, "Ptr")
    cmd := (dw = 0x5053434C && cb > 0 && lp) ? StrGet(lp, cb, "UTF-8") : ""
    ok := DispatchCliCommandString(cmd, cfg, st)
    FileAppend(cmd ":" (ok ? "1" : "0") "`n", "{log_path}", "UTF-8")
    return ok ? 1 : 0
}}
OnMessage(0x004A, OnHostCopyDataMsg)
FileAppend('{{"hwnd":' ipcGui.Hwnd '}}', "{ready_path}", "UTF-8")
Persistent(true)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def write_cli_sender_ahk(ahk_path: str) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\OBS_Network.ahk"
cmd := ParseHostCliArgs(A_Args)
ok := SendHostCliCopyData(cmd)
ExitApp(ok ? 0 : 1)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def write_diag_watchdog_render_ahk(ahk_path: str, tmp_log_dir: str, res_path: str) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -25000)
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

DiagnosticLogger.LogDir := "{tmp_log_dir}"
cfg := Config("{ahk_path}.ini")
cfg.obsPassword := "TopSecretObs99!"
cfg.InternetPairingCode := "PS-PRIV-999"
cfg.SessionPairingCode := "SEC-999"
st := OverlayState(cfg)
DiagnosticLogger.Init("PresenterSyncTest", cfg, st)

; 1. 50-event breadcrumb ring + secret redaction + PERF_LAG
Loop 55
    DiagnosticLogger.RecordBreadcrumb("Test", "Step" A_Index, "val=" A_Index)
DiagnosticLogger.LogIssue("ERROR", "TestSub", "Failure with secret TopSecretObs99!", "unit_test")
DiagnosticLogger.CheckLatency("Perf", "SlowOp", A_TickCount - 200, 120, "simulated_lag")
logTail := DiagnosticLogger.GetRecentLogTail(24000)
diagOk := (DiagnosticLogger.Breadcrumbs.Length <= 50)
    && !InStr(logTail, "TopSecretObs99!")
    && InStr(logTail, "PERF_LAG")

; 2. ApplyWindowCaptureAffinity (WDA_EXCLUDEFROMCAPTURE)
g := Gui("+ToolWindow -Caption", "AffTest")
g.Show("x-32000 y-32000 w80 h40 NoActivate")
aff1 := ApplyWindowCaptureAffinity(g.Hwnd, true)
aff0 := ApplyWindowCaptureAffinity(g.Hwnd, false)
g.Destroy()

; 3. Watchdogs
cfg.EnableLowDiskWatchdog := true
cfg.EnableDeadMicWatchdog := true
diskRes := EvaluateLowDiskSpace(200)
deadRes := EvaluateDeadMic(st, true, 0.0, 20000)
voiceRes := EvaluateMutedVoiceAlert(cfg, st, 0.25, 2000)
wdOk := (diskRes = 2) && (deadRes != 0) && (voiceRes = true)

; 4. Smart Board 0.5x - 5.0x scale bounds
scaleOk := true
for _, sc in [0.5, 1.0, 2.5, 5.0] {{
    cfg.IndicatorScale := sc
    st.ComputeDimensions(cfg)
    if (st.baseWidth <= 0 || st.baseHeight <= 0)
        scaleOk := false
}}

out := '{{"diagOk":' (diagOk ? "true" : "false")
    . ',"affOk":' ((aff1 && aff0) ? "true" : "false")
    . ',"wdOk":' (wdOk ? "true" : "false")
    . ',"scaleOk":' (scaleOk ? "true" : "false") '}}'
FileAppend(out, "{res_path}", "UTF-8")
ExitApp(0)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("psync_e2e_06_") as tmp:
        # 1. Live 2-process CLI WM_COPYDATA forwarding
        recv_ahk = tmp.join("ipc_recv.ahk")
        send_ahk = tmp.join("ipc_send.ahk")
        ready_path = tmp.join("ipc_ready.json")
        cmd_log = tmp.join("ipc_cmds.log")
        write_ipc_receiver_ahk(recv_ahk, ready_path, cmd_log)
        write_cli_sender_ahk(send_ahk)

        with ec.ManagedSubprocess([ec.AHK_EXE, "/ErrorStdOut=UTF-8", recv_ahk]):
            ec.wait_for_condition("IPC receiver ready", lambda: os.path.exists(ready_path), timeout=6.0)
            for cli_args in [["--mute"], ["--unmute"], ["--transition"], ["--nudge", "Wrap up"], ["--scene", "Slides"]]:
                p = subprocess.run([ec.AHK_EXE, "/ErrorStdOut=UTF-8", send_ahk] + cli_args, cwd=ec.REPO_DIR, timeout=10)
                assert p.returncode == 0, f"CLI sender failed for {cli_args}: rc={p.returncode}"

            def all_cmds_logged() -> bool:
                if not os.path.exists(cmd_log):
                    return False
                txt = open(cmd_log, "r", encoding="utf-8-sig").read()
                return all(k in txt for k in ["mute:1", "unmute:1", "transition:", "nudge:Wrap up:1", "scene:Slides:1"])

            ec.wait_for_condition("All 5 CLI IPC commands received", all_cmds_logged, timeout=5.0)
            print("[PASS] 2-process CLI WM_COPYDATA forwarding (--mute, --unmute, --transition, --nudge, --scene)")

        # 2. Diagnostics, WDA_EXCLUDEFROMCAPTURE, Watchdogs, 0.5x-5.0x scale
        diag_ahk = tmp.join("diag_wd.ahk")
        log_dir = tmp.join("logs")
        os.makedirs(log_dir, exist_ok=True)
        res_path = tmp.join("res_06.json")
        write_diag_watchdog_render_ahk(diag_ahk, log_dir, res_path)
        proc = subprocess.run([ec.AHK_EXE, "/ErrorStdOut=UTF-8", diag_ahk], cwd=ec.REPO_DIR, capture_output=True, text=True, timeout=25)
        assert proc.returncode == 0, f"AHK diag/watchdog exited {proc.returncode}: {proc.stderr}"
        with open(res_path, "r", encoding="utf-8-sig") as f:
            res = json.load(f)
        assert res["diagOk"], f"DiagnosticLogger check failed: {res}"
        print("[PASS] DiagnosticLogger 50-breadcrumb ring, secret redaction & PERF_LAG verified")
        assert res["affOk"], f"ApplyWindowCaptureAffinity failed: {res}"
        print("[PASS] ApplyWindowCaptureAffinity (WDA_EXCLUDEFROMCAPTURE) verified")
        assert res["wdOk"], f"Watchdogs check failed: {res}"
        print("[PASS] Watchdogs (Low-Disk, Dead-Mic, Voice-While-Muted) verified")
        assert res["scaleOk"], f"0.5x-5.0x scaling failed: {res}"
        print("[PASS] Smart Board 0.5x-5.0x scale metrics verified")

    # 3. Cross-language AES-256-GCM relay parity
    crypto_test = os.path.join(ec.REPO_DIR, "tests", "test_v762_cross_lang_crypto.py")
    cp = subprocess.run([sys.executable, "-u", crypto_test], cwd=ec.REPO_DIR, capture_output=True, text=True, timeout=30)
    assert cp.returncode == 0, f"Cross-lang AES-GCM failed: {cp.stdout}\n{cp.stderr}"
    print("[PASS] Cross-language AES-256-GCM relay parity verified")

    print("=== E2E 06 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
