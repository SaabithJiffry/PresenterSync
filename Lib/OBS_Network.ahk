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
    if RegExMatch(hk, "^(.*?)([{}^!+#])$", &m)
        return m[1] "{" m[2] "}"
    return hk
}

ExtractBaseKeyName(hk) {
    s := Trim(String(hk))
    if (s = "" || s = "None")
        return ""
    s := RegExReplace(s, "i)\s+up$", "")
    s := RegExReplace(s, "^[*~$<>^!+#]+(?=.+$)", "")
    return Trim(s)
}

WaitPushToMuteRelease(cfg, hk, keyWaitFn := "") {
    if (!IsObject(cfg) || !cfg.HasOwnProp("EnablePushToMute") || !cfg.EnablePushToMute)
        return false
    baseKey := ExtractBaseKeyName(hk)
    if (baseKey = "")
        return false
    holdSec := (IsSet(UIConstants) && UIConstants.HasOwnProp("PUSH_TO_MUTE_HOLD_MS")) ? (UIConstants.PUSH_TO_MUTE_HOLD_MS / 1000.0) : 0.35
    holdOpt := "T" Format("{:.3f}", holdSec)
    if IsObject(keyWaitFn) {
        if (keyWaitFn.Call(baseKey, holdOpt))
            return false
        keyWaitFn.Call(baseKey, "T15")
        return true
    }
    if (KeyWait(baseKey, holdOpt))
        return false
    KeyWait(baseKey, "T15")
    return true
}

DispatchHostMuteToggle(cfg, state) {
    obsOpen := WinExist("ahk_exe obs64.exe")
    zoomOpen := WinExist("ahk_exe Zoom.exe")

    if (cfg.AudioRoutingMode == 1) {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMute(state.obsWs, cfg.targetMicName, "HostClickerMute"))
            return true
        if (!obsOpen || cfg.ObsMuteHotkey = "None" || cfg.ObsMuteHotkey = "") {
            SoundPlay "*16"
            return false
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 2) {
        if (!zoomOpen) {
            SoundPlay "*16"
            return false
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(cfg.ZoomMuteHotkey), , "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 3) {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMute(state.obsWs, cfg.targetMicName, "HostClickerMute"))
            return true
        if (!obsOpen && !zoomOpen) {
            SoundPlay "*16"
            return false
        }
        state.IsSyncing := true
        SetKeyDelay -1, 30
        if (obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
            try ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
        if (zoomOpen && cfg.ZoomMuteHotkey != "")
            try ControlSend FormatSendKey(cfg.ZoomMuteHotkey), , "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
        SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
    }

    if (!state.obsConnected && !state.zoomConnected)
        SyncUIState(cfg, state, !state.isMuted)
    return true
}

DispatchRemoteMuteToggle(cfg, state) {
    if (cfg.NetworkMode = "Internet") {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (!PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "toggle_mute", "1", authTok), "https://ntfy.sh", mockWs)) {
            ToolTip "PresenterSync Remote: Internet Relay unreachable"
            SetTimer () => ToolTip(), -2000
            return false
        }
        return true
    }

    if (!SendObsToggleInputMute(state.obsWs, cfg.TargetMicName, "RemoteClickerMute")) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer () => ToolTip(), -2000
        return false
    }
    return true
}

EscapeJsonStr(str) {
    s := StrReplace(String(str), "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`b", "\b")
    s := StrReplace(s, "`f", "\f")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

UnescapeJsonStr(str) {
    s := String(str)
    out := ""
    i := 1
    len := StrLen(s)
    while (i <= len) {
        ch := SubStr(s, i, 1)
        if (ch = "\" && i < len) {
            nxt := SubStr(s, i + 1, 1)
            switch nxt {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "b": out .= "`b"
                case "f": out .= "`f"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    if (i + 5 <= len && RegExMatch(SubStr(s, i + 2, 4), "^[0-9A-Fa-f]{4}$")) {
                        out .= Chr(Integer("0x" SubStr(s, i + 2, 4)))
                        i += 6
                        continue
                    }
                    out .= "\u"
                default: out .= nxt
            }
            i += 2
        } else {
            out .= ch
            i += 1
        }
    }
    return out
}

ClearObsNetworkToolTip() {
    ToolTip()
}

TrySendWsText(ws, payload) {
    if (!IsObject(ws))
        return false
    try {
        ws.sendText(payload)
        return true
    } catch {
        return false
    }
}

SendObsRequest(ws, requestType, requestId, requestDataJson := "") {
    dataPart := (requestDataJson != "") ? (',"requestData":' requestDataJson) : ""
    payload := '{"op":6,"d":{"requestType":"' requestType '","requestId":"' requestId '"' dataPart '}}'
    return TrySendWsText(ws, payload)
}

SendObsToggleInputMute(ws, micName, requestId := "HostClickerMute") {
    escMic := EscapeJsonStr(micName)
    return SendObsRequest(ws, "ToggleInputMute", requestId, '{"inputName":"' escMic '"}')
}

SendObsSetInputMute(ws, micName, muted, requestId := "ZoomSyncObsMute") {
    escMic := EscapeJsonStr(micName)
    mutedStr := muted ? "true" : "false"
    return SendObsRequest(ws, "SetInputMute", requestId, '{"inputName":"' escMic '","inputMuted":' mutedStr '}')
}

SendObsBroadcastCloseRemote(ws, requestId := "ManualCloseRemote") {
    return SendObsRequest(ws, "BroadcastCustomEvent", requestId, '{"eventData":{"source":"PresenterSync","command":"CloseRemote"}}')
}

GenerateInternetPairingCode() {
    chars := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    p1 := "", p2 := ""
    Loop 4 {
        p1 .= SubStr(chars, Random(1, StrLen(chars)), 1)
        p2 .= SubStr(chars, Random(1, StrLen(chars)), 1)
    }
    return "PS-" p1 "-" p2
}

GetInternetRelayTopic(pairingCode) {
    clean := StrUpper(Trim(pairingCode))
    if (clean = "")
        return ""
    hash := HashSHA256_Base64("PresenterSync_RelayTopic_v1|" clean)
    safe := RegExReplace(hash, "[^a-zA-Z0-9]", "")
    return "psync_" SubStr(safe, 1, 28)
}

GetInternetRelayAuthToken(pairingCode, password := "") {
    clean := StrUpper(Trim(pairingCode))
    hash := HashSHA256_Base64("PresenterSync_RelayAuth_v1|" clean "|" password)
    return RegExReplace(hash, "[^a-zA-Z0-9]", "")
}

FormatRelayPacket(src, cmd, data, authToken) {
    return "PSRELAY|" src "|" cmd "|" data "|" authToken
}

ParseRelayPacket(rawMsg) {
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    if RegExMatch(msg, 'PSRELAY\|([^|"]*)\|([^|"]*)\|([^|"]*)\|([^|"\r\n\s}]*)', &m) {
        return {src: m[1], cmd: m[2], data: m[3], auth: m[4]}
    }
    return ""
}

PublishInternetRelayPacket(topic, packetStr, relayBaseUrl := "https://ntfy.sh", mockTargetWs := "") {
    static activeRequests := []
    if (topic = "" || packetStr = "")
        return false
    if IsObject(mockTargetWs)
        return TrySendWsText(mockTargetWs, packetStr)
    try {
        baseUrl := RTrim(relayBaseUrl != "" ? relayBaseUrl : "https://ntfy.sh", "/")
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", baseUrl "/" topic, true)
        whr.SetRequestHeader("Cache-Control", "no-cache")
        whr.Send(packetStr)
        activeRequests.Push(whr)
        if (activeRequests.Length > 8)
            activeRequests.RemoveAt(1)
        return true
    } catch {
        return false
    }
}

BroadcastHostRelayMuteState(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (!cfg.HasOwnProp("RemoteNetworkMode") || cfg.RemoteNetworkMode != "Internet")
        return false
    topic := GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : "")
    if (topic = "")
        return false
    auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
    pkt := FormatRelayPacket("host", "state", state.isMuted ? "1" : "0", auth)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, pkt, "https://ntfy.sh", mockWs)
}

UpdateHostInternetRelay(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, 0
    if (cfg.HasOwnProp("RemoteNetworkMode") && cfg.RemoteNetworkMode = "Internet" && cfg.InternetPairingCode != "") {
        if (!state.relayConnected)
            SetTimer state.relayTimerFn, -80
    } else {
        state.relayConnected := false
        if IsObject(state.relayWs) {
            try state.relayWs.shutdown()
            state.relayWs := ""
        }
    }
}

ConnectHostInternetRelay(cfg, state) {
    if (state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, 0
    if (!cfg.HasOwnProp("RemoteNetworkMode") || cfg.RemoteNetworkMode != "Internet" || state.relayConnected)
        return
    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    if (topic = "")
        return
    if IsObject(state.relayWs) {
        try state.relayWs.shutdown()
        state.relayWs := ""
    }
    wsUrl := "wss://ntfy.sh/" topic "/ws"
    try {
        state.relayWs := WebSocket(wsUrl, {
            message: HandleHostRelayMessage.Bind(cfg, state),
            close: HandleHostRelayClose.Bind(cfg, state)
        }, true, "", 4000)
    } catch {
        state.relayWs := ""
        if (cfg.RemoteNetworkMode = "Internet" && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
            SetTimer state.relayTimerFn, -3000
    }
}

HandleHostRelayClose(cfg, state, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.relayWs) && state.relayWs != ws)
        return
    if (state.relayWs == ws)
        state.relayWs := ""
    state.relayConnected := false
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
    if (cfg.HasOwnProp("RemoteNetworkMode") && cfg.RemoteNetworkMode = "Internet" && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, -3000
}

HandleHostRelayMessage(cfg, state, ws, rawMsg) {
    if (IsObject(ws) && IsObject(state.relayWs) && ws != state.relayWs)
        return
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    if RegExMatch(msg, '"event"\s*:\s*"open"') {
        state.relayConnected := true
        BroadcastHostRelayMuteState(cfg, state)
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return
    }
    pkt := ParseRelayPacket(msg)
    if (!IsObject(pkt) || pkt.src != "remote")
        return

    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    expectedAuth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    if (pkt.auth != expectedAuth) {
        PublishInternetRelayPacket(topic, FormatRelayPacket("host", "auth_error", "0", "none"), "https://ntfy.sh", mockWs)
        return
    }

    if (pkt.cmd = "sync_req") {
        BroadcastHostRelayMuteState(cfg, state)
    } else if (pkt.cmd = "toggle_mute") {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMute(state.obsWs, cfg.targetMicName, "HostClickerMute"))
            return
        obsOpen := WinExist("ahk_exe obs64.exe")
        zoomOpen := WinExist("ahk_exe Zoom.exe")
        if (cfg.AudioRoutingMode == 3 && (obsOpen || zoomOpen)) {
            state.IsSyncing := true
            if (state.HasOwnProp("releaseSyncTimerFn") && state.releaseSyncTimerFn)
                SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
        }
        if ((cfg.AudioRoutingMode == 1 || cfg.AudioRoutingMode == 3) && obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "") {
            SetKeyDelay -1, 30
            try ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
            SetKeyDelay 50, 50
        }
        if ((cfg.AudioRoutingMode == 2 || cfg.AudioRoutingMode == 3) && zoomOpen && cfg.ZoomMuteHotkey != "") {
            SetKeyDelay -1, 30
            try ControlSend FormatSendKey(cfg.ZoomMuteHotkey), , "ahk_exe Zoom.exe"
            SetKeyDelay 50, 50
        }
        if (!state.obsConnected && !state.zoomConnected) {
            SyncUIState(cfg, state, !state.isMuted)
        }
        BroadcastHostRelayMuteState(cfg, state)
    }
}

SendCloseRemoteSignal(cfg, state) {
    sentLan := false
    sentWan := false

    ; 1. Dispatch over active OBS WebSocket (LAN Mode)
    if (IsObject(state) && state.obsConnected && IsObject(state.obsWs)) {
        sentLan := SendObsBroadcastCloseRemote(state.obsWs)
    } else {
        ; One-shot loopback connect to local OBS 127.0.0.1:4455 in case Host WS Sync is currently off
        try {
            tempBox := {ws: ""}
            CleanupTempWs() {
                SetTimer CleanupTempWs, 0
                if IsObject(tempBox.ws) {
                    try tempBox.ws.shutdown()
                    tempBox.ws := ""
                }
            }
            OnTempMsg(wsObj, raw) {
                m := (Type(raw) == "Buffer") ? StrGet(raw, "UTF-8") : String(raw)
                if RegExMatch(m, '"op"\s*:\s*0') {
                    authStr := ""
                    if (RegExMatch(m, '"salt"\s*:\s*"([^"]+)"', &mS) && RegExMatch(m, '"challenge"\s*:\s*"([^"]+)"', &mC)) {
                        sec := HashSHA256_Base64(cfg.obsPassword . mS[1])
                        resp := HashSHA256_Base64(sec . mC[1])
                        authStr := ',"authentication":"' resp '"'
                    }
                    TrySendWsText(wsObj, '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":0' authStr '}}')
                } else if RegExMatch(m, '"op"\s*:\s*2') {
                    SendObsBroadcastCloseRemote(wsObj)
                    SetTimer CleanupTempWs, -250
                }
            }
            tempBox.ws := WebSocket("ws://127.0.0.1:4455", {
                message: OnTempMsg,
                close: (wsObj, st, re) => CleanupTempWs()
            }, true, "", 1000)
            SetTimer CleanupTempWs, -1200
            sentLan := true
        }
    }

    ; 2. Also dispatch over Internet Relay if Internet Pairing Code is configured
    if (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode") && cfg.InternetPairingCode != "") {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
        mockWs := (IsObject(state) && state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (topic != "")
            sentWan := PublishInternetRelayPacket(topic, FormatRelayPacket("host", "close_remote", "1", auth), "https://ntfy.sh", mockWs)
    }

    return (sentLan || sentWan)
}

FormatPassthroughHook(hk) {
    return "~$" RegExReplace(hk, "^[~*$]+")
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
        }, true, "", 2000)
    } catch {
        state.obsWs := ""
        if (cfg.EnableWS)
            SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
    }
}

HandleObsClose(cfg, state, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.obsWs) && state.obsWs != ws)
        return
    if (state.obsWs == ws)
        state.obsWs := ""

    if (!cfg.EnableWS)
        return

    if (!state.obsConnected) {
        if (status == 4009) {
            SetTimer state.obsTimerFn, 0
            newPw := PromptForPassword("OBS WebSocket authentication failed or a password is required.`n`nEnter your OBS WebSocket password (or close to disable WebSocket Sync):")
            if (newPw != "") {
                cfg.obsPassword := newPw
                cfg.Write("Settings", "ObsPassword", newPw)
                BroadcastHostRelayMuteState(cfg, state)
                if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
                    try state.refreshHelpFn.Call()
                SetTimer state.obsTimerFn, -100
            } else {
                cfg.obsPassword := ""
                cfg.Write("Settings", "ObsPassword", "")
                cfg.EnableWS := false
                cfg.WriteBool("Settings", "EnableWS", false)
                BroadcastHostRelayMuteState(cfg, state)
                if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                    try state.rebuildTrayFn.Call()
                UpdateZoomMonitorTimer(cfg, state)
                RefreshHudAppearance(cfg, state)
                if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
                    try state.refreshHelpFn.Call()
            }
            return
        }
        SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
        return
    }

    state.obsConnected := false
    SyncRecState(cfg, state, 0)
    SyncStreamState(cfg, state, 0)
    SyncVCamState(cfg, state, false)
    SyncStudioState(cfg, state, false)
    SyncSceneState(cfg, state, "Scene")
    if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
        try state.refreshHelpFn.Call()
    SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
}

PollStreamStatus(cfg, state) {
    if (!cfg.EnableWS || !state.obsConnected || !IsObject(state.obsWs) || state.streamState == 0) {
        if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn)
            SetTimer(state.streamTimerFn, 0)
        return
    }
    SendObsRequest(state.obsWs, "GetStreamStatus", "PollStreamStatus")
}

HandleObsMessage(cfg, state, ws, rawMsg) {
    if (IsObject(ws) && IsObject(state.obsWs) && ws != state.obsWs)
        return
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
        TrySendWsText(ws, identifyJson)
    }
    else if (opCode == 2) {
        SetTimer state.obsTimerFn, 0
        state.obsConnected := true
        escMic := EscapeJsonStr(cfg.targetMicName)
        SendObsRequest(ws, "GetInputMute", "InitState", '{"inputName":"' escMic '"}')
        SendObsRequest(ws, "GetRecordStatus", "InitRecState")
        SendObsRequest(ws, "GetStudioModeEnabled", "InitStudioState")
        SendObsRequest(ws, "GetCurrentProgramScene", "InitSceneState")
        SendObsRequest(ws, "GetStreamStatus", "InitStreamState")
        SendObsRequest(ws, "GetVirtualCamStatus", "InitVCamState")
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    else if (opCode == 5) {
        if (RegExMatch(msg, '"eventType"\s*:\s*"InputMuteStateChanged"')) {
            if (RegExMatch(msg, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchInput) && UnescapeJsonStr(matchInput[1]) == cfg.targetMicName) {
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
        else if (InStr(msg, '"eventType":"StreamStateChanged"') || InStr(msg, '"eventType": "StreamStateChanged"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchStrmAct)) {
                active := (matchStrmAct[1] == "true")
                reconn := InStr(msg, "OBS_WEBSOCKET_OUTPUT_RECONNECTING") != 0
                SyncStreamState(cfg, state, reconn ? 2 : (active ? 1 : 0), 0.0, state.HasOwnProp("streamSkippedFrames") ? state.streamSkippedFrames : 0, reconn)
            }
        }
        else if (InStr(msg, '"eventType":"VirtualcamStateChanged"') || InStr(msg, '"eventType": "VirtualcamStateChanged"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchVcAct)) {
                SyncVCamState(cfg, state, matchVcAct[1] == "true")
            }
        }
        else if (InStr(msg, '"eventType":"StudioModeStateChanged"') || InStr(msg, '"eventType": "StudioModeStateChanged"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(cfg, state, matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"eventType":"CurrentProgramSceneChanged"') || InStr(msg, '"eventType": "CurrentProgramSceneChanged"')) {
            if (RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene)) {
                SyncSceneState(cfg, state, UnescapeJsonStr(matchScene[1]))
            }
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                TrayTip("Audio source '" cfg.targetMicName "' was not found in OBS Studio.", "PresenterSync", 2)
            } else if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                PushObsMuteToZoom(cfg, state, isMutedOBS)
                SyncUIState(cfg, state, isMutedOBS)
                BroadcastHostRelayMuteState(cfg, state)
            }
        }
        else if (InStr(msg, '"requestId":"HostClickerMute"') || InStr(msg, '"requestId": "HostClickerMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                ToolTip("PresenterSync: Audio source '" cfg.targetMicName "' not found in OBS")
                SetTimer(ClearObsNetworkToolTip, -2500)
            }
        }
        else if (InStr(msg, '"requestId":"InitRecState"') || InStr(msg, '"requestId": "InitRecState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchActive)) {
                active := (matchActive[1] == "true")
                paused := false
                if (RegExMatch(msg, '"outputPaused"\s*:\s*(true|false)', &matchPaused))
                    paused := (matchPaused[1] == "true")
                durMs := -1
                if (RegExMatch(msg, '"outputDuration"\s*:\s*(\d+)', &matchDur))
                    durMs := Integer(matchDur[1])
                SyncRecState(cfg, state, active ? (paused ? 2 : 1) : 0, durMs)
            }
        }
        else if (InStr(msg, '"requestId":"InitStreamState"') || InStr(msg, '"requestId": "InitStreamState"')
            || InStr(msg, '"requestId":"PollStreamStatus"') || InStr(msg, '"requestId": "PollStreamStatus"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchStrmAct)) {
                active := (matchStrmAct[1] == "true")
                reconn := false
                if (RegExMatch(msg, '"outputReconnecting"\s*:\s*(true|false)', &matchReconn))
                    reconn := (matchReconn[1] == "true")
                cong := 0.0
                if (RegExMatch(msg, '"outputCongestion"\s*:\s*([0-9.]+)', &matchCong))
                    cong := Float(matchCong[1])
                skipped := 0
                if (RegExMatch(msg, '"outputSkippedFrames"\s*:\s*(\d+)', &matchSkip))
                    skipped := Integer(matchSkip[1])
                SyncStreamState(cfg, state, reconn ? 2 : (active ? 1 : 0), cong, skipped, reconn)
            }
        }
        else if (InStr(msg, '"requestId":"InitVCamState"') || InStr(msg, '"requestId": "InitVCamState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchVcAct)) {
                SyncVCamState(cfg, state, matchVcAct[1] == "true")
            }
        }
        else if (InStr(msg, '"requestId":"InitStudioState"') || InStr(msg, '"requestId": "InitStudioState"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(cfg, state, matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"requestId":"InitSceneState"') || InStr(msg, '"requestId": "InitSceneState"')) {
            if (RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene)) {
                SyncSceneState(cfg, state, UnescapeJsonStr(matchScene[1]))
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
    targetWin := zoomState.micHwnd ? ("ahk_id " zoomState.micHwnd) : "ahk_exe Zoom.exe"
    SetKeyDelay -1, 30
    try ControlSend FormatSendKey(cfg.ZoomMuteHotkey),, targetWin
    SetKeyDelay 50, 50
    SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
}

DetectZoomStates(targetSpec := "ahk_exe Zoom.exe") {
    result := {foundWindow: false, hasMic: false, muted: false, micHwnd: 0, hasRec: false, recState: 0, hasChat: false, unreadChat: 0}
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
            if (!result.hasMic && !RegExMatch(n, "i)\b(when joining|on entry|all|participants)\b")) {
                if RegExMatch(n, "i)\bunmute\b.*\baudio\b|^unmute(\b|,|$)") {
                    result.hasMic := true
                    result.muted := true
                    result.micHwnd := hwnd
                } else if RegExMatch(n, "i)\bmute\b.*\baudio\b|^mute(\b|,|$)") {
                    result.hasMic := true
                    result.muted := false
                    result.micHwnd := hwnd
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
        state.zoomRecGraceUntil := 0
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

    if (cfg.AudioRoutingMode == 3 && !state.IsSyncing) {
        if (state.zoomLastMuted != -1 && zoomInfo.muted != state.zoomLastMuted && zoomInfo.muted != state.isMuted) {
            sentObs := false
            if (cfg.EnableWS && state.obsConnected)
                sentObs := SendObsSetInputMute(state.obsWs, cfg.targetMicName, zoomInfo.muted)
            if (!sentObs && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "" && WinExist("ahk_exe obs64.exe")) {
                SetKeyDelay -1, 30
                try ControlSend FormatSendKey(cfg.ObsMuteHotkey),, "ahk_exe obs64.exe"
                SetKeyDelay 50, 50
                sentObs := true
            }
            if (sentObs) {
                state.IsSyncing := true
                SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
            }
        }
    }

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
    }
    state.zoomLastMuted := zoomInfo.muted
}

UpdateZoomMonitorTimer(cfg, state) {
    if (cfg.EnableZoom || cfg.EnableWS)
        SetTimer state.zoomTimerFn, UIConstants.ZOOM_POLL_INTERVAL_MS
    else
        SetTimer state.zoomTimerFn, 0
}
