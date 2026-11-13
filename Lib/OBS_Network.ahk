; ==============================================================================
; Module: OBS_Network.ahk
; Description: OBS WebSocket v5 client connection, message handling & Zoom UIA sync
; ==============================================================================

#Include "%A_LineFile%\..\WebSocket.ahk"
#Include "%A_LineFile%\..\UIA.ahk"
#Include "%A_LineFile%\..\Crypto.ahk"

FormatSendKey(hk) {
    if RegExMatch(hk, "^(.*?)([a-zA-Z0-9_]+)$", &m) {
        key := (StrLen(m[2]) == 1) ? StrLower(m[2]) : m[2]
        return m[1] "{" key "}"
    }
    return hk
}

ConnectToOBS(cfg, state) {
    SetTimer state.obsTimerFn, 0
    if (!cfg.EnableWS || state.obsConnected)
        return

    if IsObject(state.obsWs) {
        try state.obsWs.shutdown()
        state.obsWs := ""
    }

    try {
        state.obsWs := WebSocket("ws://127.0.0.1:4455", {
            message: HandleObsMessage.Bind(cfg, state),
            close: HandleObsClose.Bind(cfg, state)
        })
    } catch {
        state.obsWs := ""
        if (cfg.EnableWS)
            SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
    }
}

HandleObsClose(cfg, state, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (state.obsWs == ws)
        state.obsWs := ""

    if (!cfg.EnableWS)
        return

    if (!state.obsConnected) {
        cfg.obsPassword := ""
        cfg.Write("Settings", "ObsPassword", "")
        MsgBox("PresenterSync detected an incorrect OBS password.`n`nPlease re-enter your OBS WebSocket details.", "Authentication Failed", "Icon!")
        Reload()
        return
    }

    state.obsConnected := false
    SyncRecState(cfg, state, 0)
    SyncStudioState(cfg, state, false)
    SyncSceneState(cfg, state, "Scene")
    if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
        try state.refreshHelpFn.Call()
    SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
}

HandleObsMessage(cfg, state, ws, rawMsg) {
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)

    if (!RegExMatch(msg, '"op"\s*:\s*(\d+)', &matchOp))
        return
    opCode := Integer(matchOp[1])

    if (opCode == 0) {
        authString := ""
        if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &matchSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &matchChallenge)) {
            salt := matchSalt[1]
            challenge := matchChallenge[1]

            secret := HashSHA256_Base64(cfg.obsPassword . salt)
            authResponse := HashSHA256_Base64(secret . challenge)
            authString := ',"authentication":"' authResponse '"'
        }

        ; 2047 = EventSubscription::All (all standard low-volume events; excludes 20Hz InputVolumeMeters)
        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047' authString '}}'
        ws.sendText(identifyJson)
    }
    else if (opCode == 2) {
        SetTimer state.obsTimerFn, 0
        state.obsConnected := true
        stateJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitState","requestData":{"inputName":"' cfg.targetMicName '"}}}'
        ws.sendText(stateJson)
        recJson := '{"op":6,"d":{"requestType":"GetRecordStatus","requestId":"InitRecState"}}'
        ws.sendText(recJson)
        studioJson := '{"op":6,"d":{"requestType":"GetStudioModeEnabled","requestId":"InitStudioState"}}'
        ws.sendText(studioJson)
        sceneJson := '{"op":6,"d":{"requestType":"GetCurrentProgramScene","requestId":"InitSceneState"}}'
        ws.sendText(sceneJson)
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    else if (opCode == 5) {
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            if (InStr(msg, '"inputName":"' cfg.targetMicName '"') || InStr(msg, '"inputName": "' cfg.targetMicName '"')) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    PushObsMuteToZoom(cfg, state, isMutedOBS)
                    SyncUIState(cfg, state, isMutedOBS)
                }
            }
        }
        else if (InStr(msg, '"eventType":"RecordStateChanged"') || InStr(msg, '"eventType": "RecordStateChanged"')) {
            if (RegExMatch(msg, '"outputState"\s*:\s*"([^"]+)"', &matchRecOut)) {
                outState := matchRecOut[1]
                if (outState = "OBS_WEBSOCKET_OUTPUT_STARTED" || outState = "OBS_WEBSOCKET_OUTPUT_RESUMED")
                    SyncRecState(cfg, state, 1)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_PAUSED")
                    SyncRecState(cfg, state, 2)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_STOPPED")
                    SyncRecState(cfg, state, 0)
            }
        }
        else if (InStr(msg, '"eventType":"StudioModeStateChanged"') || InStr(msg, '"eventType": "StudioModeStateChanged"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(cfg, state, matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"eventType":"CurrentProgramSceneChanged"') || InStr(msg, '"eventType": "CurrentProgramSceneChanged"')) {
            if (RegExMatch(msg, '"sceneName"\s*:\s*"([^"]+)"', &matchScene)) {
                SyncSceneState(cfg, state, matchScene[1])
            }
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')) {
            if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                PushObsMuteToZoom(cfg, state, isMutedOBS)
                SyncUIState(cfg, state, isMutedOBS)
            }
        }
        else if (InStr(msg, '"requestId":"InitRecState"') || InStr(msg, '"requestId": "InitRecState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchActive)) {
                active := (matchActive[1] == "true")
                paused := false
                if (RegExMatch(msg, '"outputPaused"\s*:\s*(true|false)', &matchPaused))
                    paused := (matchPaused[1] == "true")
                SyncRecState(cfg, state, active ? (paused ? 2 : 1) : 0)
            }
        }
        else if (InStr(msg, '"requestId":"InitStudioState"') || InStr(msg, '"requestId": "InitStudioState"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(cfg, state, matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"requestId":"InitSceneState"') || InStr(msg, '"requestId": "InitSceneState"')) {
            if (RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"([^"]+)"', &matchScene) || RegExMatch(msg, '"sceneName"\s*:\s*"([^"]+)"', &matchScene)) {
                SyncSceneState(cfg, state, matchScene[1])
            }
        }
    }
}

ReleaseSyncLock(state) {
    state.IsSyncing := false
}

PushObsMuteToZoom(cfg, state, obsIsMuted) {
    if (cfg.AudioRoutingMode != 3 || state.IsSyncing || cfg.ZoomMuteHotkey = "")
        return
    if !WinExist("ahk_exe Zoom.exe")
        return

    zoomState := DetectZoomStates()
    if (!zoomState.hasMic || zoomState.muted == obsIsMuted)
        return

    state.IsSyncing := true
    SetKeyDelay -1, 30
    try ControlSend FormatSendKey(cfg.ZoomMuteHotkey),, "ahk_exe Zoom.exe"
    SetKeyDelay 50, 50
    SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
}

DetectZoomStates(targetSpec := "ahk_exe Zoom.exe") {
    result := {foundWindow: false, hasMic: false, muted: false, hasRec: false, recState: 0, hasChat: false, unreadChat: 0}
    hwndList := WinGetList(targetSpec)
    if (hwndList.Length == 0)
        return result

    result.foundWindow := true
    for hwnd in hwndList {
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            continue
        ww := 0, wh := 0
        try WinGetPos(,, &ww, &wh, hwnd)
        if (ww < 50 || wh < 50)
            continue
        names := UIA.GetWindowElementNames(hwnd, false)
        for n in names {
            if (!result.hasMic) {
                if RegExMatch(n, "i)\bunmute\b.*\baudio\b|^unmute(\b|,|$)") {
                    result.hasMic := true
                    result.muted := true
                } else if (RegExMatch(n, "i)\bmute\b.*\baudio\b|^mute(\b|,|$)") && !RegExMatch(n, "i)\b(when joining|on entry|all|participants)\b")) {
                    result.hasMic := true
                    result.muted := false
                }
            }
            if (result.recState == 0) {
                if RegExMatch(n, "i)\bresume\b.*\brecording\b") {
                    result.hasRec := true
                    result.recState := 2
                } else if RegExMatch(n, "i)\b(pause|stop)\b.*\brecording\b") {
                    result.hasRec := true
                    result.recState := 1
                } else if (!result.hasRec && RegExMatch(n, "i)^record(\b|,|$)|^record (on this computer|to the cloud)")) {
                    result.hasRec := true
                    result.recState := 0
                }
            }
            if RegExMatch(n, "i)\bchat\b.*?(\d+)\s*unread|(\d+)\s*unread.*\bchat\b", &mChat) {
                result.hasChat := true
                cnt := Integer(mChat[1] != "" ? mChat[1] : mChat[2])
                if (cnt > result.unreadChat)
                    result.unreadChat := cnt
            } else if (!result.hasChat && RegExMatch(n, "i)^chat(\b|,|$)|open chat|show chat|chat panel")) {
                result.hasChat := true
            }
        }
        if (result.hasMic && result.hasRec && result.recState > 0 && result.hasChat && result.unreadChat > 0)
            break
    }
    return result
}

ZoomStateMonitor(cfg, state) {
    if (!cfg.EnableZoom && !cfg.EnableWS)
        return

    zoomInfo := DetectZoomStates()
    if (zoomInfo.hasChat)
        SyncChatState(cfg, state, zoomInfo.unreadChat)
    else
        SyncChatState(cfg, state, 0)

    if (!zoomInfo.hasMic) {
        wasConn := state.zoomConnected
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomSawRecControl := false
        if (cfg.EnableZoom && !cfg.EnableWS)
            SyncRecState(cfg, state, 0)
        if (wasConn && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return
    }

    wasConn := state.zoomConnected
    state.zoomConnected := (cfg.EnableZoom && !cfg.EnableWS)
    if (state.zoomConnected != wasConn && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
    if (cfg.EnableZoom && !cfg.EnableWS) {
        SyncUIState(cfg, state, zoomInfo.muted)
        if (zoomInfo.hasRec) {
            state.zoomSawRecControl := true
            if (A_TickCount >= state.zoomRecGraceUntil)
                SyncRecState(cfg, state, zoomInfo.recState)
        } else if (state.zoomSawRecControl && A_TickCount >= state.zoomRecGraceUntil) {
            state.zoomSawRecControl := false
            SyncRecState(cfg, state, 0)
        }
    } else if (cfg.EnableWS && cfg.AudioRoutingMode == 3 && state.obsConnected && !state.IsSyncing) {
        if (state.zoomLastMuted != -1 && zoomInfo.muted != state.zoomLastMuted && zoomInfo.muted != state.isMuted) {
            if (cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "" && WinExist("ahk_exe obs64.exe")) {
                state.IsSyncing := true
                SetKeyDelay -1, 30
                try ControlSend FormatSendKey(cfg.ObsMuteHotkey),, "ahk_exe obs64.exe"
                SetKeyDelay 50, 50
                SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
            }
        }
    }
    state.zoomLastMuted := zoomInfo.muted
}

UpdateZoomMonitorTimer(cfg, state) {
    if (cfg.EnableZoom || cfg.EnableWS)
        SetTimer state.zoomTimerFn, UIConstants.ZOOM_POLL_INTERVAL_MS
    else
        SetTimer state.zoomTimerFn, 0
}
