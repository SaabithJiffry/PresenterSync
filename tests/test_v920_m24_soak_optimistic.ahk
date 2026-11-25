#Requires AutoHotkey v2.0
#SingleInstance Off
; ============================================================================
; test_v920_m24_soak_optimistic.ahk - M2.4 Soak Hardening & <16ms Optimistic Toggle
; ============================================================================

SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\DiagnosticLogger.ahk
#Include ..\Lib\SessionTimeline.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk
#Include ..\Lib\HudRenderer.ahk

global g_Passed := 0
global g_Failed := 0
global g_FailMessages := []

AssertTrue(cond, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (cond) {
        g_Passed++
    } else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg)
    }
}

AssertEq(actual, expected, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (actual = expected) {
        g_Passed++
    } else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg " (expected='" String(expected) "', actual='" String(actual) "')")
    }
}

; Dummy globals referenced by included Host modules when running standalone
global MicGui := 0
global State := { isMuted: false, micName: "Mic", currentScene: "Main", scenes: ["Main", "Slides"] }
global Cfg := {}

try {
    ; ------------------------------------------------------------------------
    ; 1. Voice meter cadence constant (20 Hz / 50 ms)
    ; ------------------------------------------------------------------------
    AssertEq(UIConstants.VOICE_METER_INTERVAL_MS, 50, "VOICE_METER_INTERVAL_MS should be 50ms")

    ; ------------------------------------------------------------------------
    ; 2. Gdip surface/font/stringFormat cache + ReleaseSurface + Shutdown
    ; ------------------------------------------------------------------------
    Gdip.Startup()
    testGui := Gui("-Caption +E0x80000")
    testGui.Show("x-32000 y-32000 w120 h40 NoActivate")
    hwnd := testGui.Hwnd

    Gdip.RenderPill(hwnd, -32000, -32000, 120, 40, 0xFF1E1E2E, 0xFF89B4FA, 255, 12)
    Gdip.DrawText(Gdip._surfaces[hwnd].pGraphics, "Hello", "Segoe UI", 10, 0, 0xFFFFFFFF, 0, 0, 100, 30)
    ; Call RenderPill again to ensure surface is reused rather than duplicated
    Gdip.RenderPill(hwnd, -32000, -32000, 120, 40, 0xFF1E1E2E, 0xFFA6E3A1, 255, 12)

    AssertTrue(Gdip._surfaces.Has(hwnd), "Gdip._surfaces should cache surface for hwnd")
    AssertTrue(Gdip._fonts.Count >= 1 || Gdip._stringFormats.Count >= 1, "Gdip should cache StringFormats/Fonts")

    Gdip.ReleaseSurface(hwnd)
    AssertTrue(!Gdip._surfaces.Has(hwnd), "ReleaseSurface should remove hwnd from _surfaces")
    testGui.Destroy()

    Gdip.Shutdown()
    AssertEq(Gdip._surfaces.Count, 0, "Gdip.Shutdown should clear _surfaces")
    AssertEq(Gdip._fonts.Count, 0, "Gdip.Shutdown should clear _fonts")
    AssertEq(Gdip._stringFormats.Count, 0, "Gdip.Shutdown should clear _stringFormats")

    ; ------------------------------------------------------------------------
    ; 3. Theme.EnsureInitialized & Theme.Shutdown callback cleanup
    ; ------------------------------------------------------------------------
    Theme.EnsureInitialized()
    AssertTrue(Theme.initialized, "Theme.EnsureInitialized should set initialized=true")
    Theme.Shutdown()
    AssertEq(Theme.initialized, false, "Theme.Shutdown should reset initialized=false")
    AssertEq(Theme.hkSubclassPtr, 0, "Theme.Shutdown should zero hkSubclassPtr")
    AssertEq(Theme.tabSubclassPtr, 0, "Theme.Shutdown should zero tabSubclassPtr")
    AssertEq(Theme.staticSubclassPtr, 0, "Theme.Shutdown should zero staticSubclassPtr")
    AssertEq(Theme.btnSubclassPtr, 0, "Theme.Shutdown should zero btnSubclassPtr")

    ; ------------------------------------------------------------------------
    ; 4. DiagnosticLogger.CheckLatency rate-limit cooldown
    ; ------------------------------------------------------------------------
    DiagnosticLogger.PERF_LOG_COOLDOWN_MS := 30000
    DiagnosticLogger._LastPerfLogTick := Map()
    DiagnosticLogger.CheckLatency("HOTPATH", "FirstSlow", A_TickCount - 100, 10, "t1")
    AssertTrue(DiagnosticLogger._LastPerfLogTick.Count >= 1, "CheckLatency should record _LastPerfLogTick on slow op")
    firstKey := ""
    firstTick := 0
    for k, v in DiagnosticLogger._LastPerfLogTick {
        firstKey := k
        firstTick := v
        break
    }
    DiagnosticLogger.CheckLatency("HOTPATH", "FirstSlow", A_TickCount - 100, 10, "t2")
    AssertEq(DiagnosticLogger._LastPerfLogTick[firstKey], firstTick, "CheckLatency should rate-limit within 30s cooldown")

    ; ------------------------------------------------------------------------
    ; 5. SessionTimeline autosave rotation at MAX_AUTOSAVE_BYTES
    ; ------------------------------------------------------------------------
    tmpDir := A_Temp "\ps_m24_timeline_" A_TickCount
    DirCreate(tmpDir)
    origAutosave := SessionTimeline.AutosaveFile
    origMax := SessionTimeline.MAX_AUTOSAVE_BYTES
    SessionTimeline.AutosaveFile := tmpDir "\timeline_autosave.json"
    SessionTimeline.MAX_AUTOSAVE_BYTES := 128

    ; Write >= 128 bytes to trigger rotation
    bigPayload := ""
    loop 200
        bigPayload .= "A"
    FileAppend(bigPayload, SessionTimeline.AutosaveFile, "UTF-8")
    SessionTimeline._RotateAutosaveIfNeeded()
    AssertTrue(FileExist(SessionTimeline.AutosaveFile ".1"), "Autosave should rotate to .1 when >= MAX_AUTOSAVE_BYTES")
    AssertTrue(!FileExist(SessionTimeline.AutosaveFile), "Primary autosave should be moved to .1 after rotation")

    SessionTimeline.AutosaveFile := origAutosave
    SessionTimeline.MAX_AUTOSAVE_BYTES := origMax
    try DirDelete(tmpDir, true)

    ; ------------------------------------------------------------------------
    ; 6. HostBridge PruneRateLimits & recvBuf shrink
    ; ------------------------------------------------------------------------
    hb := HostCompanionBridge()
    hb.rateLimits := Map()
    hb.rateLimits["stale_ip"] := { fails: 0, lockUntil: 0, lastUdpTick: 1000, lastV1Tick: 1000, lastActivityTick: 1000 }
    hb.rateLimits["fresh_ip"] := { fails: 0, lockUntil: 0, lastUdpTick: 140000, lastV1Tick: 140000, lastActivityTick: 140000 }
    hb.PruneRateLimits(150000)
    AssertTrue(!hb.rateLimits.Has("stale_ip"), "PruneRateLimits should evict >120s stale entries")
    AssertTrue(hb.rateLimits.Has("fresh_ip"), "PruneRateLimits should retain fresh entries")

    ; recvBuf shrink check when _DrainWsFrames finishes with recvLen == 0 and recvBuf.Size > 16384
    mockClient := {
        sock: 0,
        recvBuf: Buffer(32768, 0),
        recvLen: 0,
        isWs: true,
        closed: false,
        authed: false,
        ip: "127.0.0.1",
        deviceId: "",
        deviceName: "",
        role: "presenter",
        lastRxTick: A_TickCount,
        lastPingTick: A_TickCount,
        missedPongs: 0
    }
    hb._DrainWsFrames(mockClient)
    AssertEq(mockClient.recvBuf.Size, 4096, "_DrainWsFrames should shrink idle recvBuf >16KB back to 4096")

    ; ------------------------------------------------------------------------
    ; 7. Optimistic SyncUIState: no premature broadcast, authoritative confirms
    ; ------------------------------------------------------------------------
    st := {
        isMuted: false,
        sceneChanged: false,
        currentScene: "Main",
        _optimisticMute: false,
        _optimisticMuteTick: 0
    }
    cfgObj := {
        obsMutedColor: "E04040",
        obsUnmutedColor: "40C060",
        writeCount: 0
    }
    cfgObj.DefineProp("WriteBool", { Call: (this, sec, key, val) => (this.writeCount += 1, true) })
    cfgObj.DefineProp("WriteBoolDeferred", { Call: (this, sec, key, val, delayMs := 250) => (this.writeCount += 1, true) })

    ; Optimistic flip to muted=true (must NOT write INI prematurely)
    SyncUIState(cfgObj, st, true, true)
    AssertEq(st.isMuted, true, "Optimistic SyncUIState should flip state.isMuted immediately")
    AssertEq(cfgObj.writeCount, 0, "Optimistic SyncUIState must not trigger INI write prematurely")

    ; Authoritative confirm with muted=true
    SyncUIState(cfgObj, st, true, false)
    AssertEq(st.isMuted, true, "Authoritative SyncUIState confirm should preserve muted=true")

    ; Authoritative rollback to muted=false
    SyncUIState(cfgObj, st, false, false)
    AssertEq(st.isMuted, false, "Authoritative SyncUIState rollback should restore muted=false")

} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M2.4 AHK Test Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}

FileAppend("M2.4 AHK Test Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
