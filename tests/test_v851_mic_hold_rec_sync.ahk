; ==============================================================================
; Test Suite: test_v851_mic_hold_rec_sync.ahk
; Description: Verifies v8.5.1 Adaptation #1 (MicGui long-press constants & state)
;              and Adaptation #2 (True OBS recording elapsed timer sync).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\HudRenderer.ahk"

global g_IsTestMode := true

passed := 0
failed := 0

AssertTrue(cond, label) {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label "`n", "*")
    }
}

tmpIni := A_Temp "\PresenterSync_v851_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)
st.recTimerFn := "" ; Avoid real GUI SetTimer side effects in unit test

; 1. Adaptation #1: MIC_LONG_PRESS_MS & OverlayState holdProgress properties
AssertTrue(UIConstants.MIC_LONG_PRESS_MS == 600, "UIConstants.MIC_LONG_PRESS_MS == 600")
AssertTrue(st.micHoldProgress == 0.0, "OverlayState initializes micHoldProgress == 0.0")
AssertTrue(st.secondaryMicHoldProgress == 0.0, "OverlayState initializes secondaryMicHoldProgress == 0.0")

; 2. Adaptation #2: SyncRecState anchors obsRecAnchorMs & obsRecAnchorTick
SyncRecState(cfg, st, 1, 125400, "obs")
AssertTrue(st.obsRecState == 1, "SyncRecState sets obsRecState == 1")
AssertTrue(st.obsRecElapsedSec == 125, "SyncRecState sets obsRecElapsedSec == 125 for 125400ms")
AssertTrue(st.recElapsedSec == 125, "SyncRecState sets recElapsedSec == 125")
AssertTrue(st.obsRecAnchorMs == 125400, "SyncRecState anchors obsRecAnchorMs == 125400")
AssertTrue(st.obsRecAnchorTick > 0, "SyncRecState anchors obsRecAnchorTick > 0")

; 3. Zero-drift RecTimerTick: simulate 30s elapsed via obsRecAnchorTick -= 30000
st.obsRecAnchorTick -= 30000
RecTimerTick(cfg, st)
AssertTrue(st.obsRecElapsedSec == 155, "RecTimerTick computes exact 155s after 30s elapsed (zero drift)")
AssertTrue(st.recElapsedSec == 155, "RecTimerTick updates recElapsedSec == 155")

; 4. Authoritative SyncRecStatus / PollRecStatus resync corrects recElapsedSec
class MockObsWs {
    sent := []
    sendText(txt) {
        this.sent.Push(txt)
    }
}
mockWs := MockObsWs()

; 5a. RecordStateChanged -> triggers GetRecordStatus (SyncRecStatus)
recStartedEvent := '{"op":5,"d":{"eventType":"RecordStateChanged","eventData":{"outputActive":true,"outputState":"OBS_WEBSOCKET_OUTPUT_STARTED"}}}'
HandleObsMessage(cfg, st, mockWs, recStartedEvent)
AssertTrue(mockWs.sent.Length >= 1 && InStr(mockWs.sent[1], '"requestType":"GetRecordStatus"') && InStr(mockWs.sent[1], '"requestId":"SyncRecStatus"'), "RecordStateChanged STARTED triggers GetRecordStatus SyncRecStatus")

; 5b. SyncRecStatus opCode 7 response updates recElapsedSec to 160
syncResp := '{"op":7,"d":{"requestType":"GetRecordStatus","requestId":"SyncRecStatus","requestStatus":{"result":true,"code":100},"responseData":{"outputActive":true,"outputPaused":false,"outputDuration":160000}}}'
HandleObsMessage(cfg, st, mockWs, syncResp)
AssertTrue(st.recElapsedSec == 160 && st.obsRecElapsedSec == 160, "SyncRecStatus response updates recElapsedSec to 160")

; 5c. PollRecStatus opCode 7 response updates recElapsedSec to 175
pollResp := '{"op":7,"d":{"requestType":"GetRecordStatus","requestId":"PollRecStatus","requestStatus":{"result":true,"code":100},"responseData":{"outputActive":true,"outputPaused":false,"outputDuration":175200}}}'
HandleObsMessage(cfg, st, mockWs, pollResp)
AssertTrue(st.recElapsedSec == 175 && st.obsRecElapsedSec == 175, "PollRecStatus response updates recElapsedSec to 175")

; Pause freezes anchor cleanly
SyncRecState(cfg, st, 2, -1, "obs")
AssertTrue(st.obsRecState == 2 && st.obsRecAnchorTick == 0, "Pause freezes obsRecAnchorTick == 0")

; Stop resets anchor cleanly
SyncRecState(cfg, st, 0, -1, "obs")
AssertTrue(st.obsRecState == 0 && st.obsRecAnchorMs == 0 && st.obsRecAnchorTick == 0 && st.recElapsedSec == 0, "Stop resets anchor and recElapsedSec")

try FileDelete(tmpIni)
FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
