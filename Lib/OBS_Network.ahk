; ==============================================================================
; Module: OBS_Network.ahk
; Description: OBS WebSocket v5 client connection, message handling & Zoom sync
; ==============================================================================

ConnectToOBS(cfg, state) {
    if (!cfg.EnableWS)
        return

    try {
        state.obsWs := WebSocket("ws://127.0.0.1:4455", {
            message: HandleObsMessage.Bind(cfg, state),
            close: HandleObsClose.Bind(cfg, state)
        })
    } catch {
        if (cfg.EnableWS)
            SetTimer state.obsTimerFn, 5000
    }
}

HandleObsClose(cfg, state, ws, status, reason) {
    if (!cfg.EnableWS)
        return

    if (!state.obsConnected) {
        cfg.Write("Settings", "ObsPassword", "")
        MsgBox("PresenterSync detected an incorrect OBS password.`n`nPlease re-enter your OBS WebSocket details.", "Authentication Failed", "Icon!")
        Reload()
        return
    }

    state.obsConnected := false
    SyncRecState(cfg, state, 0)
    SyncStudioState(cfg, state, false)
    SyncSceneState(cfg, state, "Scene")
    SetTimer state.obsTimerFn, 5000
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

        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":33554431' authString '}}'
        ws.sendText(identifyJson)
    }
    else if (opCode == 2) {
        state.obsConnected := true
        stateJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitState","requestData":{"inputName":"' cfg.targetMicName '"}}}'
        ws.sendText(stateJson)
        recJson := '{"op":6,"d":{"requestType":"GetRecordStatus","requestId":"InitRecState"}}'
        ws.sendText(recJson)
        studioJson := '{"op":6,"d":{"requestType":"GetStudioModeEnabled","requestId":"InitStudioState"}}'
        ws.sendText(studioJson)
        sceneJson := '{"op":6,"d":{"requestType":"GetCurrentProgramScene","requestId":"InitSceneState"}}'
        ws.sendText(sceneJson)
    }
    else if (opCode == 5) {
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            if (InStr(msg, '"inputName":"' cfg.targetMicName '"') || InStr(msg, '"inputName": "' cfg.targetMicName '"')) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    SyncUIState(cfg, state, isMutedOBS)
                    PushObsMuteToZoom(cfg, state, isMutedOBS)
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
                SyncUIState(cfg, state, isMutedOBS)
                PushObsMuteToZoom(cfg, state, isMutedOBS)
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
    SetTimer state.releaseSyncTimerFn, -1000
}
