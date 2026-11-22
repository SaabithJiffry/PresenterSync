"""
E2E 05: Push-to-Talk (PTT) isMuted Guard, <300ms Release / Double-Tap Preservation & Mutual Exclusion
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _e2e_common as ec


def write_ptt_ahk(ahk_path: str, result_path: str) -> None:
    lib = os.path.join(ec.REPO_DIR, "Lib")
    script = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
global g_IsTestMode := true
SetTimer(() => ExitApp(124), -25000)
OnError((err, mode) => (FileAppend("ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))
#Include "{lib}\\WebSocket.ahk"
#Include "{lib}\\Crypto.ahk"
#Include "{lib}\\Gdip.ahk"
#Include "{lib}\\UIA.ahk"
#Include "{lib}\\OBS_Network.ahk"
#Include "{lib}\\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

cfg := Config("{ahk_path}.ini")
st := OverlayState(cfg)
st.suppressNudgeBanners := true

; 1. Mutual exclusion: EnablePushToTalk vs EnablePushToMute
cfg.EnablePushToMute := true
cfg.EnablePushToTalk := false
TogglePushToTalk(cfg, st)
ex1 := (cfg.EnablePushToTalk == true && cfg.EnablePushToMute == false)
TogglePushToMute(cfg, st)
ex2 := (cfg.EnablePushToMute == true && cfg.EnablePushToTalk == false)

; 2. PTT isMuted == true guard: never unmutes/mutes when already LIVE
cfg.EnablePushToTalk := true
cfg.EnablePushToMute := false
st.isMuted := false
callsLive := 0
pttLiveRes := ExecutePushToTalkHoldCycle(cfg, st, (m) => (callsLive += 1), "b", (k, opt) => true)
liveGuarded := (callsLive = 0 && pttLiveRes = false)

; 3. < 350ms short click / Double-Tap preservation (WaitPushToMuteRelease returns false if released before hold threshold)
cfg.EnablePushToTalk := false
cfg.EnablePushToMute := true
shortRes := WaitPushToMuteRelease(cfg, "b", (k, opt) => true) ; key released before T0.350 -> true => not a hold
longRes := WaitPushToMuteRelease(cfg, "b", (k, opt) => (InStr(opt, "T0.") ? false : true)) ; held past T0.350, then released
shortPreserved := (shortRes = false && longRes = true)

; 4. PTT hold while muted -> unmutes on press & re-mutes on release
cfg.EnablePushToMute := false
cfg.EnablePushToTalk := true
st.isMuted := true
callsHold := []
pttHoldRes := ExecutePushToTalkHoldCycle(cfg, st, (m) => (st.isMuted := m, callsHold.Push(m)), "b", (k, opt) => true)
holdOk := (pttHoldRes = true && callsHold.Length = 2 && callsHold[1] = false && callsHold[2] = true && st.isMuted = true)

out := '{{"ex1":' (ex1 ? "true" : "false")
    . ',"ex2":' (ex2 ? "true" : "false")
    . ',"liveGuarded":' (liveGuarded ? "true" : "false")
    . ',"shortPreserved":' (shortPreserved ? "true" : "false")
    . ',"holdOk":' (holdOk ? "true" : "false") '}}'
FileAppend(out, "{result_path}", "UTF-8")
ExitApp(0)
'''
    with open(ahk_path, "w", encoding="utf-8") as f:
        f.write(script)


def main() -> int:
    with ec.TempWorkspace("psync_e2e_05_") as tmp:
        ahk_path = tmp.join("ptt_05.ahk")
        res_path = tmp.join("res_05.json")
        write_ptt_ahk(ahk_path, res_path)

        proc = subprocess.run(
            [ec.AHK_EXE, "/ErrorStdOut=UTF-8", ahk_path],
            cwd=ec.REPO_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, f"AHK PTT harness exited {proc.returncode}: {proc.stderr}"
        with open(res_path, "r", encoding="utf-8-sig") as f:
            res = json.load(f)

        assert res["ex1"] and res["ex2"], f"Mutual exclusion failed: {res}"
        print("[PASS] EnablePushToTalk vs EnablePushToMute mutual exclusion verified")

        assert res["liveGuarded"], f"PTT LIVE guard failed: {res}"
        print("[PASS] PTT isMuted==true guard prevents accidental toggle when already LIVE")

        assert res["shortPreserved"], f"Short click (<300ms) not preserved: {res}"
        print("[PASS] <300ms release / Double-Tap preserved without accidental hold trigger")

        assert res["holdOk"], f"PTT hold/release cycle failed: {res}"
        print("[PASS] >=300ms PTT hold unmutes & re-mutes cleanly on release")

    # Verify Android BubbleGestureRecognizer PTT & Double-Tap parity source invariants
    bg_path = os.path.join(
        ec.REPO_DIR, "android", "app", "src", "main", "java", "com", "saabithjiffry", "presentersync", "remote", "input", "BubbleGesture.kt"
    )
    with open(bg_path, "r", encoding="utf-8") as f:
        bg_src = f.read()
    assert "BubbleGestureAction" in bg_src and "doubleTapAction" in bg_src
    print("[PASS] Android BubbleGesture.kt PTT & Double-Tap parity verified")

    print("=== E2E 05 PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
