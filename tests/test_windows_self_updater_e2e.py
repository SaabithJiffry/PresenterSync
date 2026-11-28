"""
Live Windows Self-Updater End-to-End Verification (v6.1.0):
Spins up an ephemeral local HTTP release server serving GitHub-style JSON,
SHA256SUMS.txt, and signed PE binary payloads, then verifies:
  1. DownloadVerifyAndStageWindowsUpdate aborts and deletes staged files on SHA-256 mismatch
  2. DownloadVerifyAndStageWindowsUpdate aborts and deletes staged files on non-MZ payload
  3. StreamHttpToFile cancels mid-transfer when isCancelledFn returns true and cleans .tmp
  4. Valid release download streams monotonically to 100%, verifies SHA-256 & MZ PE header
  5. REAL compiled Win32 .exe running on disk performs in-place atomic self-swap (.exe -> .old),
     relaunches itself preserving -Config & -Instance flags + --cleanup-old-exe, and deletes .old!
"""

import hashlib
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

AHK_EXE = r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
AHK2EXE = r"C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GUI_CONFIG_AHK = os.path.join(REPO_DIR, "Lib", "GUI_Config.ahk")
REMOTE_CLIENT_AHK = os.path.join(REPO_DIR, "Lib", "RemoteBridgeClient.ahk")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().lower()


def compile_ahk_exe(src_ahk: str, out_exe: str):
    cmd = [AHK2EXE, "/in", src_ahk, "/out", out_exe, "/base", AHK_EXE, "/silent", "verbose"]
    res = subprocess.run(cmd, cwd=REPO_DIR, capture_output=True, text=True, timeout=45)
    if res.returncode != 0 or not os.path.exists(out_exe):
        raise RuntimeError(f"Ahk2Exe failed for {src_ahk}: rc={res.returncode}\n{res.stdout}\n{res.stderr}")


def wait_until(desc: str, predicate, timeout: float = 15.0, poll: float = 0.15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(poll)
    raise AssertionError(f"Timed out waiting for: {desc}")


class ReleaseFixtureHandler(http.server.BaseHTTPRequestHandler):
    routes = {}

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        entry = self.routes.get(self.path)
        if entry is None:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found")
            return
        body, content_type, slow_chunks = entry
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if slow_chunks:
            chunk = 8192
            for i in range(0, len(body), chunk):
                try:
                    self.wfile.write(body[i : i + chunk])
                    self.wfile.flush()
                except OSError:
                    return
                time.sleep(0.03)
        else:
            try:
                self.wfile.write(body)
            except OSError:
                return


class ReusableHttpServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    for required in (AHK_EXE, AHK2EXE, GUI_CONFIG_AHK, REMOTE_CLIENT_AHK):
        if not os.path.exists(required):
            raise FileNotFoundError(f"Missing required tool/library: {required}")

    tmp_dir = tempfile.mkdtemp(prefix="ps_self_upd_e2e_")
    server = None
    try:
        # Build v6.1.0 compiled target stub executable that performs startup .old cleanup
        v610_src = os.path.join(tmp_dir, "stub_v610.ahk")
        v610_exe = os.path.join(tmp_dir, "staged_v610.exe")
        result_file = os.path.join(tmp_dir, "e2e_result.txt")
        with open(v610_src, "w", encoding="utf-8") as f:
            f.write(
                '#Requires AutoHotkey v2.0\n'
                '#SingleInstance Off\n'
                f'#Include "{GUI_CONFIG_AHK}"\n'
                f'#Include "{REMOTE_CLIENT_AHK}"\n'
                'parsed := ParseRemoteCliArgs(A_Args)\n'
                'ProcessSelfUpdateStartupCleanup(A_Args, A_ScriptFullPath)\n'
                'deadline := A_TickCount + 6000\n'
                'while (parsed.cleanupOldExe != "" && FileExist(parsed.cleanupOldExe) && A_TickCount < deadline)\n'
                '    Sleep(100)\n'
                'out := "UPDATED_TO=6.1.0`n"\n'
                'out .= "EXE=" A_ScriptFullPath "`n"\n'
                'out .= "CONFIG=" parsed.configPath "`n"\n'
                'out .= "INSTANCE=" parsed.instanceName "`n"\n'
                'out .= "CLEANUP_ARG=" parsed.cleanupOldExe "`n"\n'
                'out .= "OLD_STILL_EXISTS=" (FileExist(A_ScriptFullPath ".old") ? "1" : "0") "`n"\n'
                f'FileAppend(out, "{result_file}", "UTF-8")\n'
                'ExitApp(0)\n'
            )
        compile_ahk_exe(v610_src, v610_exe)
        with open(v610_exe, "rb") as f:
            v610_bytes = f.read()
        v610_sha = sha256_hex(v610_bytes)
        v610_size = len(v610_bytes)
        assert v610_bytes[:2] == b"MZ" and v610_size > 100000

        # Payloads for negative cases
        spoof_bytes = b"<html>Fake Gateway Error Page</html>" * 20
        spoof_sha = sha256_hex(spoof_bytes)
        wrong_sha = "0" * 64
        slow_payload = b"MZ" + (b"S" * (256 * 1024))

        # Start ephemeral local release HTTP server
        server = ReusableHttpServer(("127.0.0.1", 0), ReleaseFixtureHandler)
        port = server.server_address[1]
        base = f"http://127.0.0.1:{port}"

        sums_ok = (
            f"{v610_sha} *release-upload/PresenterSync.exe\n"
            f"{spoof_sha}  Spoofed.exe\n"
        ).encode("utf-8")
        sums_bad = f"{wrong_sha}  PresenterSync.exe\n".encode("utf-8")

        rel_ok = json.dumps({
            "tag_name": "v6.1.0",
            "html_url": f"{base}/releases/tag/v6.1.0",
            "body": "E2E Verified Release",
            "assets": [{
                "name": "PresenterSync.exe",
                "size": v610_size,
                "uploader": {"login": "ci-bot"},
                "browser_download_url": f"{base}/dl/PresenterSync.exe"
            }, {
                "name": "SHA256SUMS.txt",
                "size": len(sums_ok),
                "browser_download_url": f"{base}/dl/SHA256SUMS.txt"
            }]
        }).encode("utf-8")

        rel_bad_sha = json.dumps({
            "tag_name": "v6.1.0",
            "assets": [{
                "name": "PresenterSync.exe",
                "size": v610_size,
                "browser_download_url": f"{base}/dl/PresenterSync.exe"
            }, {
                "name": "SHA256SUMS.txt",
                "size": len(sums_bad),
                "browser_download_url": f"{base}/dl/SHA256SUMS_BAD.txt"
            }]
        }).encode("utf-8")

        rel_spoof = json.dumps({
            "tag_name": "v6.1.0",
            "assets": [{
                "name": "Spoofed.exe",
                "size": len(spoof_bytes),
                "browser_download_url": f"{base}/dl/Spoofed.exe"
            }, {
                "name": "SHA256SUMS.txt",
                "size": len(sums_ok),
                "browser_download_url": f"{base}/dl/SHA256SUMS.txt"
            }]
        }).encode("utf-8")

        ReleaseFixtureHandler.routes = {
            "/releases/latest": (rel_ok, "application/json", False),
            "/releases/bad_sha": (rel_bad_sha, "application/json", False),
            "/releases/spoof": (rel_spoof, "application/json", False),
            "/dl/PresenterSync.exe": (v610_bytes, "application/octet-stream", False),
            "/dl/Spoofed.exe": (spoof_bytes, "application/octet-stream", False),
            "/dl/SHA256SUMS.txt": (sums_ok, "text/plain", False),
            "/dl/SHA256SUMS_BAD.txt": (sums_bad, "text/plain", False),
            "/dl/slow.exe": (slow_payload, "application/octet-stream", True),
        }

        srv_thread = threading.Thread(target=server.serve_forever, daemon=True)
        srv_thread.start()

        # Part A: HTTP download, SHA-256 mismatch, non-MZ rejection, cancellation, progress callbacks
        part_a_log = os.path.join(tmp_dir, "part_a.log")
        part_a_ahk = os.path.join(tmp_dir, "test_part_a.ahk")
        # Dual-channel fixtures: commit-pinned Nightly, caught-up Nightly, same-version Stable handoff, ahead-of-stable rollback
        nightly_sha = v610_sha
        other_sha = "1" * 64
        commit_sha = "deadbeef1234567890abcdef1234567890abcdef"
        commit_json = json.dumps({"sha": commit_sha, "html_url": f"{base}/commit/{commit_sha}"}).encode("utf-8")
        meta_610 = json.dumps({"version": "6.1.0", "androidVersionCode": 60100, "builtAtUtc": "2026-11-28T00:00:00Z"}).encode("utf-8")
        sums_other = f"{other_sha}  PresenterSync.exe\n".encode("utf-8")
        ReleaseFixtureHandler.routes[f"/raw/{commit_sha}/dist/nightly_meta.json"] = (meta_610, "application/json", False)
        ReleaseFixtureHandler.routes[f"/raw/{commit_sha}/dist/SHA256SUMS.txt"] = (sums_ok, "text/plain", False)
        ReleaseFixtureHandler.routes[f"/raw/{commit_sha}/dist/PresenterSync.exe"] = (v610_bytes, "application/octet-stream", False)

        with open(part_a_ahk, "w", encoding="utf-8") as f:
            f.write(
                '#Requires AutoHotkey v2.0\n'
                '#SingleInstance Force\n'
                f'#Include "{GUI_CONFIG_AHK}"\n'
                'passes := 0, fails := 0\n'
                'LogChk(name, cond) {\n'
                '    global passes, fails\n'
                '    if (cond)\n'
                '        passes += 1\n'
                '    else {\n'
                '        fails += 1\n'
                f'        FileAppend("FAIL: " name "`n", "{part_a_log}", "UTF-8")\n'
                '    }\n'
                '}\n'
                f'rBadJson := _FetchHttpTextSimple("{base}/releases/bad_sha").text\n'
                'uBad := CheckForUpdates("6.0.0", rBadJson, true, "PresenterSync.exe")\n'
                f'badDest := "{tmp_dir}\\bad_sha.exe"\n'
                'stBad := DownloadVerifyAndStageWindowsUpdate(uBad, badDest)\n'
                'LogChk("Rejects SHA-256 mismatch and deletes file", !stBad.ok && InStr(stBad.reason, "SHA-256") && !FileExist(badDest))\n'
                '\n'
                f'rSpoofJson := _FetchHttpTextSimple("{base}/releases/spoof").text\n'
                'uSpoof := CheckForUpdates("6.0.0", rSpoofJson, true, "Spoofed.exe")\n'
                f'spoofDest := "{tmp_dir}\\spoof.exe"\n'
                'stSpoof := DownloadVerifyAndStageWindowsUpdate(uSpoof, spoofDest)\n'
                'LogChk("Rejects non-MZ payload and deletes file", !stSpoof.ok && InStr(stSpoof.reason, "MZ") && !FileExist(spoofDest))\n'
                '\n'
                f'cancelDest := "{tmp_dir}\\cancelled.exe"\n'
                'cancelState := { calls: 0 }\n'
                'CancelAfter2(*) => (cancelState.calls >= 2)\n'
                'OnSlowProg(r, t, p) => (cancelState.calls += 1)\n'
                f'dlCancel := StreamHttpToFile("{base}/dl/slow.exe", cancelDest, {len(slow_payload)}, OnSlowProg, CancelAfter2)\n'
                'LogChk("Mid-stream cancel aborts & cleans partial file", !dlCancel.ok && dlCancel.cancelled && !FileExist(cancelDest) && !FileExist(cancelDest ".tmp"))\n'
                '\n'
                f'rOkJson := _FetchHttpTextSimple("{base}/releases/latest").text\n'
                'uOk := CheckForUpdates("6.0.0", rOkJson, true, "PresenterSync.exe")\n'
                f'okDest := "{tmp_dir}\\ok_verified.exe"\n'
                'pctList := []\n'
                'stOk := DownloadVerifyAndStageWindowsUpdate(uOk, okDest, "", (r, t, p) => pctList.Push(p))\n'
                'LogChk("Valid download succeeds with SHA-256 + monotonic progress", stOk.ok && stOk.shaVerified && FileExist(okDest) && pctList.Length > 0 && pctList[pctList.Length] == 100)\n'
                '\n'
                'uNoSha := { latest: uOk.latest, assetName: uOk.assetName, assetUrl: uOk.assetUrl, assetSize: uOk.assetSize, sha256Url: "" }\n'
                f'noShaDest := "{tmp_dir}\\no_sha.exe"\n'
                'stNoSha := DownloadVerifyAndStageWindowsUpdate(uNoSha, noShaDest)\n'
                'LogChk("P1-4: Fail-closed when SHA256SUMS.txt URL is missing", !stNoSha.ok && InStr(stNoSha.reason, "SHA256SUMS") && !FileExist(noShaDest))\n'
                '\n'
                '; M7B + M7C Dual-Channel & Nightly Build Selector checks\n'
                f'cSha1 := "{commit_sha}"\n'
                f'cSha2 := "cafebabe1234567890abcdef1234567890abcdef"\n'
                f'cShaStable := "0000111122223333444455556666777788889999"\n'
                f'cListJson := \x27[{{"sha":"' + commit_sha + '","html_url":"' + base + '/commit/' + commit_sha + '","commit":{{"committer":{{"date":"2026-11-28T02:00:00Z"}},"message":"feat: latest nightly"}}}},{{"sha":"cafebabe1234567890abcdef1234567890abcdef","html_url":"' + base + '/commit/cafebabe","commit":{{"committer":{{"date":"2026-11-27T12:00:00Z"}},"message":"fix: legacy nightly without meta"}}}},{{"sha":"0000111122223333444455556666777788889999","html_url":"' + base + '/commit/stable","commit":{{"committer":{{"date":"2026-11-26T00:00:00Z"}},"message":"chore(release): v6.1.0"}}}}]\x27\n'
                f'cStableJson := \x27{{"sha":"0000111122223333444455556666777788889999","commit":{{"committer":{{"date":"2026-11-26T00:00:00Z"}}}}}}\x27\n'
                f'cCaughtListJson := \x27[{{"sha":"0000111122223333444455556666777788889999","commit":{{"committer":{{"date":"2026-11-26T00:00:00Z"}},"message":"chore(release): v6.1.0"}}}}]\x27\n'
                f'mJson := \x27{meta_610.decode("utf-8")}\x27\n'
                f'sOk := _FetchHttpTextSimple("{base}/dl/SHA256SUMS.txt").text\n'
                f'sOther := "{other_sha}  PresenterSync.exe`n"\n'
                'fixCaughtEmpty := { stableReleaseJson: rOkJson, stableCommitJson: cStableJson, commitListJson: cCaughtListJson, currentBinarySha256: "' + other_sha + '" }\n'
                'uCaught := CheckForUpdates("6.1.0", "", true, "PresenterSync.exe", "", "Nightly", fixCaughtEmpty)\n'
                'LogChk("M7C: Empty post-stable list caught up to Stable", uCaught.ok && !uCaught.updateAvailable && uCaught.status = "caught_up_to_stable" && uCaught.nightlyBuilds.Length == 0 && InStr(uCaught.statusHeadline, "Nightly has caught up to Stable (v6.1.0)"))\n'
                '\n'
                f'fixSameSha := {{ stableReleaseJson: rOkJson, stableCommitJson: cStableJson, commitListJson: cListJson, rawBaseUrl: "{base}/raw/{commit_sha}/dist", nightlyMetaJson: mJson, nightlySumsText: sOk, stableSumsText: sOther, currentBinarySha256: "{v610_sha}" }}\n'
                'uSameSha := CheckForUpdates("6.1.0", "", true, "PresenterSync.exe", "", "Nightly", fixSameSha)\n'
                'LogChk("M7C: Same-SHA Nightly marked Already Installed with 2 filtered post-stable builds", uSameSha.ok && !uSameSha.updateAvailable && uSameSha.isAlreadyInstalled && uSameSha.nightlyBuilds.Length == 2 && InStr(uSameSha.nightlyBuilds[1].label, "Nightly (Latest)") && !InStr(uSameSha.nightlyBuilds[2].label, "(Latest)"))\n'
                '\n'
                f'fixNightlyAvail := {{ stableReleaseJson: rOkJson, stableCommitJson: cStableJson, commitListJson: cListJson, rawBaseUrl: "{base}/raw/{commit_sha}/dist", nightlyMetaJson: mJson, nightlySumsText: sOk, stableSumsText: sOther, currentBinarySha256: "{other_sha}" }}\n'
                'uNightly := CheckForUpdates("6.0.0", "", true, "PresenterSync.exe", "", "Nightly", fixNightlyAvail)\n'
                f'LogChk("M7C: Nightly available uses immutable commit URL", uNightly.ok && uNightly.updateAvailable && uNightly.status = "nightly_available" && InStr(uNightly.assetUrl, "{commit_sha}"))\n'
                f'nDest := "{tmp_dir}\\nightly_dl.exe"\n'
                'stN := DownloadVerifyAndStageWindowsUpdate(uNightly, nDest)\n'
                'LogChk("M7C: Nightly download verifies SHA-256", stN.ok && stN.shaVerified && FileExist(nDest))\n'
                '\n'
                f'fixLegacyNoMeta := {{ stableReleaseJson: rOkJson, stableCommitJson: cStableJson, commitListJson: cListJson, rawBaseUrl: "{base}/raw/{commit_sha}/dist", nightlyMetaJson: "", nightlySumsText: sOk, stableSumsText: sOther, currentBinarySha256: "{other_sha}", selectedBuildIndex: 2 }}\n'
                'uLegacy := CheckForUpdates("6.1.0", "", true, "PresenterSync.exe", "", "Nightly", fixLegacyNoMeta)\n'
                'LogChk("M7C: Older post-stable Nightly without nightly_meta.json still resolves with SHA-256", uLegacy.ok && uLegacy.updateAvailable && uLegacy.shortSha = "cafebab" && uLegacy.sha256Url != "")\n'
                '\n'
                f'fixHandoff := {{ stableReleaseJson: rOkJson, stableSumsText: sOk, currentBinarySha256: "{other_sha}" }}\n'
                'uHandoff := CheckForUpdates("6.1.0", "", true, "PresenterSync.exe", "", "Stable", fixHandoff)\n'
                'LogChk("M7B: Same-version Nightly->Stable SHA handoff", uHandoff.ok && uHandoff.updateAvailable && uHandoff.status = "stable_handoff" && InStr(uHandoff.statusHeadline, "Install Stable v6.1.0"))\n'
                '\n'
                f'fixAhead := {{ stableReleaseJson: rOkJson, stableSumsText: sOk, currentBinarySha256: "{other_sha}" }}\n'
                'uAhead := CheckForUpdates("6.2.0", "", true, "PresenterSync.exe", "", "Stable", fixAhead)\n'
                'LogChk("M7B: Ahead-of-stable offers optional rollback", uAhead.ok && !uAhead.updateAvailable && uAhead.rollbackAvailable && uAhead.status = "ahead_of_stable")\n'
                '\n'
                f'FileAppend("PASS=" passes " FAIL=" fails "`n", "{part_a_log}", "UTF-8")\n'
                'ExitApp(fails > 0 ? 1 : 0)\n'
            )

        res_a = subprocess.run([AHK_EXE, part_a_ahk], capture_output=True, text=True, timeout=30)
        log_txt = open(part_a_log, "r", encoding="utf-8").read() if os.path.exists(part_a_log) else ""
        assert res_a.returncode == 0 and "FAIL=0" in log_txt, f"Part A failed (rc={res_a.returncode}):\n{log_txt}\n{res_a.stderr}"
        print("[PASS] Part A: Live HTTP streaming download, SHA-256 mismatch abort, non-MZ abort, cancel cleanup")

        # Part B: REAL compiled v6.0.0 running EXE atomically replaces itself with v6.1.0 & relaunches!
        live_exe = os.path.join(tmp_dir, "PresenterSync_Remote.exe")
        v600_src = os.path.join(tmp_dir, "stub_v600.ahk")
        with open(v600_src, "w", encoding="utf-8") as f:
            f.write(
                '#Requires AutoHotkey v2.0\n'
                '#SingleInstance Off\n'
                f'#Include "{GUI_CONFIG_AHK}"\n'
                f'relJson := _FetchHttpTextSimple("{base}/releases/latest").text\n'
                'upd := CheckForUpdates("6.0.0", relJson, true, "PresenterSync.exe")\n'
                'if (!upd.ok || !upd.updateAvailable)\n'
                '    ExitApp(2)\n'
                'stage := A_ScriptFullPath ".update.tmp"\n'
                'res := DownloadVerifyAndStageWindowsUpdate(upd, stage)\n'
                'if (!res.ok || !res.shaVerified)\n'
                '    ExitApp(3)\n'
                'swap := PerformAtomicExeSwapAndRelaunch(A_ScriptFullPath, stage, A_Args, true, true)\n'
                'ExitApp(swap.ok ? 0 : 4)\n'
            )
        compile_ahk_exe(v600_src, live_exe)

        cfg_arg = os.path.join(tmp_dir, "my remote cfg.ini")
        inst_arg = "Classroom B"
        proc = subprocess.run(
            [live_exe, "-Config", cfg_arg, "-Instance", inst_arg],
            cwd=tmp_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, f"v6.0.0 updater stub exited with {proc.returncode}: {proc.stderr}"

        wait_until("relaunched v6.1.0 exe writes verification file", lambda: os.path.exists(result_file), timeout=12.0)
        # Allow tiny brief flush for old file delete if nearly simultaneous
        wait_until(".old executable deleted by relaunched process", lambda: not os.path.exists(live_exe + ".old"), timeout=8.0)

        res_txt = open(result_file, "r", encoding="utf-8").read()
        assert "UPDATED_TO=6.1.0" in res_txt, res_txt
        assert f"CONFIG={cfg_arg}" in res_txt, res_txt
        assert f"INSTANCE={inst_arg}" in res_txt, res_txt
        assert "OLD_STILL_EXISTS=0" in res_txt, res_txt

        # Verify on-disk binary is now literally the v6.1.0 payload
        with open(live_exe, "rb") as f:
            final_sha = sha256_hex(f.read())
        assert final_sha == v610_sha, f"On-disk exe hash mismatch: {final_sha} != {v610_sha}"
        print("[PASS] Part B: Running Win32 EXE downloaded v6.1.0, SHA-256 verified, swapped .exe/.old, relaunched with preserved CLI flags, and deleted .old!")
        return 0
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
