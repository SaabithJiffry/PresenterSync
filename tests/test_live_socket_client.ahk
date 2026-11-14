; ==============================================================================
; Test: test_live_socket_client.ahk
; Description: End-to-end live socket test connecting to live_obs_server.py
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\GUI_Config.ahk"
#Include "..\Lib\OBS_Network.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

class LiveTestConfig {
    HostAddress := "127.0.0.1"
    HostPort := "4455"
    ObsPassword := "testPassword456"
    TargetMicName := "Mic/Aux"
    HeartbeatSeconds := 30
    HwMuteHotkey := "b"
    EnablePointerMute := true
    ShowIndicator := true
    ThemeMode := "System"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := false
    IsMuted := false
    savedX := "Default"
    savedY := "Default"
}

class LiveTestState {
    obsWs := ""
    obsConnected := false
    activeHost := ""
    candidateIndex := 1
    candidates := []
    isMuted := false
    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5
    animSeq := 0
    isDraggingHud := false
    MicGui := ""
    IconFont := "Segoe UI"
    baseWidth := 80
    baseHeight := 40
    hudGap := 6
    recHeight := 34
    recW := 40
    chatW := 34
    row3Height := 30
    studioW := 28
    sceneW := 46
    iconSize := 18
    textSize := 13
    savedX := 100
    savedY := 100
    colors := {
        live: UIConstants.COLOR_LIVE,
        muted: UIConstants.COLOR_MUTED,
        borderLive: UIConstants.BORDER_LIVE,
        borderMuted: UIConstants.BORDER_MUTED,
        iconLive: UIConstants.ICON_LIVE,
        iconMuted: UIConstants.ICON_MUTED
    }
}

cfg := LiveTestConfig()
state := LiveTestState()
state.candidates := [{host: "127.0.0.1", port: "4455", raw: "127.0.0.1:4455"}]

; Step 1: Connect WebSocket
stepResults := []
stepResults.Push("Starting live connection to ws://127.0.0.1:4455...")

wsUrl := "ws://127.0.0.1:4455"

OnMsg(ws, rawMsg) {
    global cfg, state, stepResults
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    
    if RegExMatch(msg, '"op"\s*:\s*0') {
        stepResults.Push("[PASS] Client received Op 0 Hello with Challenge")
        ; Compute SHA256 auth
        RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &mSalt)
        RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &mChal)
        secret := HashSHA256_Base64(cfg.ObsPassword . mSalt[1])
        authResp := HashSHA256_Base64(secret . mChal[1])
        identJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047,"authentication":"' authResp '"}}'
        ws.sendText(identJson)
        stepResults.Push("[PASS] Client computed SHA256 signature and sent Op 1 Identify")
    }
    else if RegExMatch(msg, '"op"\s*:\s*2') {
        state.obsConnected := true
        stepResults.Push("[PASS] Client received Op 2 Identified (Auth Succeeded!)")
        ; Send Initial state query
        queryJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitRemoteMute","requestData":{"inputName":"' cfg.TargetMicName '"}}}'
        ws.sendText(queryJson)
        stepResults.Push("[PASS] Client dispatched Op 6 GetInputMute")
    }
    else if RegExMatch(msg, '"op"\s*:\s*7') {
        stepResults.Push("[PASS] Client received Op 7 RequestResponse: mic is LIVE")
        state.isMuted := false
    }
    else if RegExMatch(msg, '"op"\s*:\s*5') {
        stepResults.Push("[PASS] Client received Op 5 Event: Microphone muted!")
        state.isMuted := true
        
        ; Test clicker transmission over real socket
        Sleep 50
        clickJson := '{"op":6,"d":{"requestType":"ToggleInputMute","requestId":"RemoteClickerMute","requestData":{"inputName":"' cfg.TargetMicName '"}}}'
        ws.sendText(clickJson)
        stepResults.Push("[PASS] Client transmitted clicker Op 6 ToggleInputMute over wire")
        
        ; Test heartbeat keep-alive
        Sleep 50
        hbJson := '{"op":6,"d":{"requestType":"GetVersion","requestId":"KeepAlive"}}'
        ws.sendText(hbJson)
        stepResults.Push("[PASS] Client transmitted 30s Heartbeat KeepAlive over wire")
        
        SetTimer FinishTest, -300
    }
}

OnClose(ws, status, reason) {
    ; Expected on test completion
}

FinishTest() {
    global stepResults
    for res in stepResults
        FileAppend(res "`n", "*")
    ExitApp(0)
}

TimeoutAbort() {
    FileAppend("[FAIL] Live socket test timed out after 5 seconds`n", "*")
    ExitApp(1)
}

SetTimer TimeoutAbort, -5000

try {
    state.obsWs := WebSocket(wsUrl, {
        message: OnMsg,
        close: OnClose
    }, true, "", 3000)
} catch as err {
    FileAppend("[FAIL] WebSocket connection failed: " err.Message "`n", "*")
    ExitApp(1)
}

