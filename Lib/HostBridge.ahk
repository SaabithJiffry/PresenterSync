; ==============================================================================
; Module: HostBridge.ahk
; Description: Non-blocking WinSock2 (WSAAsyncSelect) Companion Bridge Server
;              on TCP :4456, UDP Pair :4456, and UDP Discovery :4457.
;              Provides:
;                1) UDP Public Classroom Discovery (PS_DISCOVER_V1 -> public JSON beacon, zero secrets)
;                2) UDP LAN Session Code Discovery (PSYNC_DISCOVER -> PSYNC_OFFER)
;                3) HTTP Session Pairing (POST /pair, GET /health) w/ rate limit
;                4) Direct RFC 6455 WebSocket Bridge (ws://<host>:4456/ws) + sync_resync
;              Zero blocking calls — driven completely by Win32 window messages.
; ==============================================================================

#DllLoad ws2_32.dll

class HostBridgeConstants {
    static DEFAULT_PORT := 4456
    static DEFAULT_DISCOVERY_PORT := 4457
    static DISCOVER_V1_PROTO := "PS_DISCOVER_V1"
    static MAX_BUFFER_BYTES := 65536
    static AUTH_TIMEOUT_MS := 3000
    static KEEP_ALIVE_MS := 20000
    ; v7.0.5 (#11): an authenticated WS client that has sent nothing (not even a
    ; pong to our 20s keep-alive ping) for 55s is a half-open zombie left behind
    ; by a sleeping Smart Board / dropped Wi-Fi. Reap it so the slot and the
    ; device's "connected" state are freed for the reconnecting socket.
    static DEAD_CLIENT_TIMEOUT_MS := 55000
    static PAIR_MAX_FAILS := 5
    static PAIR_LOCKOUT_MS := 30000
    static UDP_COOLDOWN_MS := 200
    static WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
}

GetBridgeFallbackPorts(preferredPort := 4456) {
    pref := HostBridgeConstants.DEFAULT_PORT
    try pref := Integer(preferredPort)
    if (pref < 0 || pref > 65535)
        pref := HostBridgeConstants.DEFAULT_PORT
    ports := [pref]
    seen := Map(pref, true)
    Loop 8 {
        p := 4457 + A_Index
        if (!seen.Has(p)) {
            seen[p] := true
            ports.Push(p)
        }
    }
    return ports
}

EnsureHostUuid(cfg := "") {
    if (IsObject(cfg) && cfg.HasOwnProp("HostUuid") && Trim(cfg.HostUuid) != "")
        return Trim(cfg.HostUuid)
    if (IsSet(GenerateHostUuid))
        uuid := GenerateHostUuid()
    else {
        b := Buffer(16, 0)
        Loop 16
            NumPut("UChar", Random(0, 255), b, A_Index - 1)
        NumPut("UChar", (NumGet(b, 6, "UChar") & 0x0F) | 0x40, b, 6)
        NumPut("UChar", (NumGet(b, 8, "UChar") & 0x3F) | 0x80, b, 8)
        hex := ""
        Loop 16
            hex .= Format("{:02x}", NumGet(b, A_Index - 1, "UChar"))
        uuid := SubStr(hex, 1, 8) "-" SubStr(hex, 9, 4) "-" SubStr(hex, 13, 4) "-" SubStr(hex, 17, 4) "-" SubStr(hex, 21, 12)
    }
    if (IsObject(cfg)) {
        cfg.HostUuid := uuid
        if (cfg.HasMethod("Write"))
            try cfg.Write("Settings", "HostUuid", uuid)
    }
    return uuid
}

_HB_GetEndpointsSignature(endpoints) {
    if (!IsObject(endpoints) || !endpoints.HasOwnProp("ips"))
        return ""
    ipsCopy := []
    for _, ip in endpoints.ips {
        s := Trim(String(ip))
        if (s != "")
            ipsCopy.Push(s)
    }
    if (ipsCopy.Length > 1) {
        i := 2
        while (i <= ipsCopy.Length) {
            key := ipsCopy[i]
            j := i - 1
            while (j >= 1 && StrCompare(ipsCopy[j], key) > 0) {
                ipsCopy[j + 1] := ipsCopy[j]
                j -= 1
            }
            ipsCopy[j + 1] := key
            i += 1
        }
    }
    joined := ""
    for idx, item in ipsCopy
        joined .= (idx > 1 ? "," : "") item
    mdnsVal := endpoints.HasOwnProp("mdns") ? endpoints.mdns : ""
    return mdnsVal "|" joined
}

BuildPublicDiscoveryBeaconJson(cfg, bridgePort := 4456, obsPort := 4455) {
    uuid := EnsureHostUuid(cfg)
    netMode := (IsObject(cfg) && cfg.HasOwnProp("RemoteNetworkMode")) ? cfg.RemoteNetworkMode : "LAN"
    mode := (IsObject(cfg) && cfg.HasOwnProp("AudioRoutingMode")) ? Integer(cfg.AudioRoutingMode) : 0
    return '{"proto":"' HostBridgeConstants.DISCOVER_V1_PROTO '"'
        . ',"hostUuid":"' _HB_JsonEscape(uuid) '"'
        . ',"deviceName":"' _HB_JsonEscape(A_ComputerName) '"'
        . ',"bridgePort":' Integer(bridgePort)
        . ',"obsPort":' Integer(obsPort)
        . ',"networkMode":"' _HB_JsonEscape(netMode) '"'
        . ',"audioRoutingMode":' mode
        . ',"version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '"'
        . '}'
}

global g_HostCompanionBridge := ""

_HB_htons(val) {
    return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF)
}

_HB_MakeSockAddrIn(port, ipUint := 0) {
    buf := Buffer(16, 0)
    NumPut("UShort", 2, buf, 0) ; AF_INET
    NumPut("UShort", _HB_htons(port), buf, 2)
    NumPut("UInt", ipUint, buf, 4)
    return buf
}

_HB_FormatIp(addrBuf) {
    return NumGet(addrBuf, 4, "UChar") "." NumGet(addrBuf, 5, "UChar") "." NumGet(addrBuf, 6, "UChar") "." NumGet(addrBuf, 7, "UChar")
}

_HB_JsonEscape(str) {
    s := String(str)
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

_HB_JsonExtractStr(jsonStr, key) {
    pattern := '"' key '"\s*:\s*"((?:[^"\\]|\\.)*)"'
    if (RegExMatch(jsonStr, pattern, &m)) {
        val := m[1]
        val := StrReplace(val, '\"', '"')
        val := StrReplace(val, "\\", "\")
        val := StrReplace(val, "\r", "`r")
        val := StrReplace(val, "\n", "`n")
        val := StrReplace(val, "\t", "`t")
        return val
    }
    return ""
}

_HB_JsonExtractBool(jsonStr, key, defaultVal := false) {
    pattern := '"' key '"\s*:\s*(true|false)'
    if (RegExMatch(jsonStr, "i)" pattern, &m))
        return (StrLower(m[1]) = "true")
    return defaultVal
}

_HB_JsonExtractInt(jsonStr, key, defaultVal := 0) {
    pattern := '"' key '"\s*:\s*(-?\d+)'
    if (RegExMatch(jsonStr, pattern, &m))
        return Integer(m[1])
    return defaultVal
}

_HB_UrlDecode(str) {
    out := StrReplace(String(str), "+", " ")
    pos := 1
    while (pos := RegExMatch(out, "%([0-9A-Fa-f]{2})", &m, pos)) {
        ch := Chr(Integer("0x" m[1]))
        out := SubStr(out, 1, pos - 1) ch SubStr(out, pos + 3)
        pos += 1
    }
    return out
}

_HB_ParseQueryParams(pathWithQuery) {
    params := Map()
    qPos := InStr(pathWithQuery, "?")
    if (!qPos)
        return params
    qs := SubStr(pathWithQuery, qPos + 1)
    for pair in StrSplit(qs, "&") {
        if (pair = "")
            continue
        eq := InStr(pair, "=")
        if (eq > 1) {
            k := _HB_UrlDecode(SubStr(pair, 1, eq - 1))
            v := _HB_UrlDecode(SubStr(pair, eq + 1))
            params[k] := v
        }
    }
    return params
}

_HB_StrToUtf8Buf(str, &outLen) {
    outLen := StrPut(str, "UTF-8") - 1
    if (outLen <= 0) {
        outLen := 0
        return Buffer(1, 0)
    }
    buf := Buffer(outLen + 1, 0)
    StrPut(str, buf, "UTF-8")
    return buf
}

_HB_AppendBytes(bufObj, existingLen, srcPtr, addLen, maxAllowed := 65536) {
    newLen := existingLen + addLen
    if (newLen > maxAllowed)
        return -1
    if (bufObj.Size < newLen) {
        newCap := Max(newLen, Max(4096, bufObj.Size * 2))
        if (newCap > maxAllowed)
            newCap := maxAllowed
        newBuf := Buffer(newCap, 0)
        if (existingLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", newBuf.Ptr, "Ptr", bufObj.Ptr, "UPtr", existingLen)
        bufObj := newBuf
    }
    if (addLen > 0)
        DllCall("ntdll\RtlMoveMemory", "Ptr", bufObj.Ptr + existingLen, "Ptr", srcPtr, "UPtr", addLen)
    return { buf: bufObj, len: newLen }
}

_HB_ConsumeBytes(bufObj, existingLen, count) {
    if (count >= existingLen)
        return 0
    rem := existingLen - count
    DllCall("ntdll\RtlMoveMemory", "Ptr", bufObj.Ptr, "Ptr", bufObj.Ptr + count, "UPtr", rem)
    return rem
}

class HostCompanionBridge {
    cfg := ""
    state := ""
    requestedTcpPort := 4456
    requestedUdpPort := 4456
    requestedDiscoverPort := 4457
    boundTcpPort := 0
    boundUdpPort := 0
    boundDiscoverPort := 0
    running := false
    wsaStarted := false
    msgGui := ""
    hwnd := 0
    wmTcp := 0x0551
    wmUdp := 0x0552
    wmDiscover := 0x0553
    tcpListenSock := -1
    udpSock := -1
    discoverSock := -1
    clients := Map()
    pairedDevices := Map()
    validTokens := Map()
    rateLimits := Map()
    tcpMsgFn := ""
    udpMsgFn := ""
    discoverMsgFn := ""
    maintTimerFn := ""
    _tcpEventQueue := []
    _tcpDispatching := false
    cachedEndpoints := ""
    cachedEndpointsTick := 0
    lastEndpointsSig := ""
    lastAdapterCheckTick := 0
    lastWakeRefreshTick := 0
    lastError := ""

    Start(cfg, state, tcpPort := 4456, udpPort := -1, discoverPort := -1) {
        this.Stop()
        this.cfg := cfg
        this.state := state
        this.requestedTcpPort := tcpPort
        this.requestedUdpPort := (udpPort = -1) ? tcpPort : udpPort
        this.requestedDiscoverPort := (discoverPort = -1) ? ((tcpPort = HostBridgeConstants.DEFAULT_PORT) ? HostBridgeConstants.DEFAULT_DISCOVERY_PORT : 0) : discoverPort
        this.lastError := ""

        EnsureHostUuid(cfg)
        if (!cfg.HasOwnProp("SessionPairingCode") || cfg.SessionPairingCode = "") {
            cfg.SessionPairingCode := GenerateSessionPairingCode()
            if (cfg.HasMethod("Write"))
                try cfg.Write("Settings", "SessionPairingCode", cfg.SessionPairingCode)
        }
        this.LoadPairedDevices()

        wsaData := Buffer(408, 0)
        if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int") != 0) {
            this.lastError := "WSAStartup failed"
            return false
        }
        this.wsaStarted := true

        this._tcpEventQueue := []
        this._tcpDispatching := false
        this.cachedEndpoints := GetLocalNetworkEndpoints()
        this.cachedEndpointsTick := A_TickCount
        this.lastEndpointsSig := _HB_GetEndpointsSignature(this.cachedEndpoints)
        this.lastAdapterCheckTick := A_TickCount

        this.msgGui := Gui("-Caption +ToolWindow", "PresenterSync_HostBridgeMsg")
        this.hwnd := this.msgGui.Hwnd

        this.tcpMsgFn := ObjBindMethod(this, "_OnTcpMessage")
        this.udpMsgFn := ObjBindMethod(this, "_OnUdpMessage")
        this.discoverMsgFn := ObjBindMethod(this, "_OnDiscoverMessage")
        ; MaxThreads = 255 guarantees AHK never silently drops edge-triggered WSAAsyncSelect messages
        OnMessage(this.wmTcp, this.tcpMsgFn, 255)
        OnMessage(this.wmUdp, this.udpMsgFn, 255)
        OnMessage(this.wmDiscover, this.discoverMsgFn, 255)

        if (!this._BindListeners(this.requestedTcpPort, this.requestedUdpPort, this.requestedDiscoverPort)) {
            this.Stop()
            return false
        }

        this.running := true
        this.maintTimerFn := ObjBindMethod(this, "_OnMaintenanceTick")
        SetTimer(this.maintTimerFn, 1000)
        return true
    }

    _BindListeners(tcpPort, udpPort, discoverPort) {
        boundOk := false
        for _, candPort in GetBridgeFallbackPorts(tcpPort) {
            if (this._BindTcpListenSocket(candPort)) {
                boundOk := true
                break
            }
        }
        if (!boundOk)
            return false
        if (IsObject(this.state))
            this.state.activeBridgePort := this.boundTcpPort
        if (tcpPort > 0 && this.boundTcpPort != tcpPort && IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Bridge", "PortFallback", "from=" tcpPort " to=" this.boundTcpPort)
        if (udpPort >= 0) {
            targetUdp := (udpPort == tcpPort && this.boundTcpPort != tcpPort) ? this.boundTcpPort : udpPort
            uSock := -1
            uBound := 0
            if (!this._BindUdpSocket(targetUdp, this.wmUdp, &uSock, &uBound) && targetUdp != 0)
                this._BindUdpSocket(0, this.wmUdp, &uSock, &uBound)
            this.udpSock := uSock
            this.boundUdpPort := uBound
        }
        if (discoverPort >= 0) {
            dSock := -1
            dBound := 0
            this._BindUdpSocket(discoverPort, this.wmDiscover, &dSock, &dBound)
            this.discoverSock := dSock
            this.boundDiscoverPort := dBound
        }
        return true
    }

    _BindTcpListenSocket(tcpPort) {
        this.boundTcpPort := 0
        this.tcpListenSock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if (this.tcpListenSock = -1) {
            this.lastError := "TCP socket create failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            return false
        }

        optOn := Buffer(4, 0)
        NumPut("Int", 1, optOn, 0)
        ; SO_EXCLUSIVEADDRUSE (-5) prevents two processes from binding the same port cleanly so fallback 4458..4465 triggers
        DllCall("ws2_32\setsockopt", "Ptr", this.tcpListenSock, "Int", 0xFFFF, "Int", -5, "Ptr", optOn, "Int", 4, "Int")

        tcpAddr := _HB_MakeSockAddrIn(tcpPort, 0)
        if (DllCall("ws2_32\bind", "Ptr", this.tcpListenSock, "Ptr", tcpAddr, "Int", 16, "Int") != 0) {
            this.lastError := "TCP bind port " tcpPort " failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            try DllCall("ws2_32\closesocket", "Ptr", this.tcpListenSock)
            this.tcpListenSock := -1
            return false
        }

        outAddr := Buffer(16, 0)
        outLen := 16
        DllCall("ws2_32\getsockname", "Ptr", this.tcpListenSock, "Ptr", outAddr, "Int*", &outLen, "Int")
        this.boundTcpPort := _HB_htons(NumGet(outAddr, 2, "UShort"))

        if (DllCall("ws2_32\listen", "Ptr", this.tcpListenSock, "Int", 16, "Int") != 0) {
            this.lastError := "TCP listen failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            try DllCall("ws2_32\closesocket", "Ptr", this.tcpListenSock)
            this.tcpListenSock := -1
            this.boundTcpPort := 0
            return false
        }

        ; FD_READ(1) | FD_WRITE(2) | FD_ACCEPT(8) | FD_CLOSE(32) = 0x2B
        if (DllCall("ws2_32\WSAAsyncSelect", "Ptr", this.tcpListenSock, "Ptr", this.hwnd, "UInt", this.wmTcp, "Int", 0x2B, "Int") != 0) {
            this.lastError := "TCP WSAAsyncSelect failed"
            try DllCall("ws2_32\closesocket", "Ptr", this.tcpListenSock)
            this.tcpListenSock := -1
            this.boundTcpPort := 0
            return false
        }
        return true
    }

    _BindUdpSocket(udpPort, wmMsg, &outSock, &outBoundPort) {
        outSock := -1
        outBoundPort := 0
        sock := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "Ptr")
        if (sock = -1)
            return false
        optOn := Buffer(4, 0)
        NumPut("Int", 1, optOn, 0)
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 4, "Ptr", optOn, "Int", 4, "Int")
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x0020, "Ptr", optOn, "Int", 4, "Int")
        udpAddr := _HB_MakeSockAddrIn(udpPort, 0)
        if (DllCall("ws2_32\bind", "Ptr", sock, "Ptr", udpAddr, "Int", 16, "Int") = 0) {
            uOut := Buffer(16, 0)
            uLen := 16
            DllCall("ws2_32\getsockname", "Ptr", sock, "Ptr", uOut, "Int*", &uLen, "Int")
            outBoundPort := _HB_htons(NumGet(uOut, 2, "UShort"))
            DllCall("ws2_32\WSAAsyncSelect", "Ptr", sock, "Ptr", this.hwnd, "UInt", wmMsg, "Int", 1, "Int")
            outSock := sock
            return true
        }
        DllCall("ws2_32\closesocket", "Ptr", sock)
        return false
    }

    RefreshNetworkListeners(reason := "wake") {
        if (!this.running || !this.hwnd)
            return false
        prevTcp := (this.boundTcpPort > 0) ? this.boundTcpPort : this.requestedTcpPort
        prevUdp := (this.boundUdpPort > 0) ? this.boundUdpPort : this.requestedUdpPort
        prevDisc := (this.boundDiscoverPort > 0) ? this.boundDiscoverPort : this.requestedDiscoverPort

        if (this.tcpListenSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.tcpListenSock)
            this.tcpListenSock := -1
        }
        if (this.udpSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.udpSock)
            this.udpSock := -1
        }
        if (this.discoverSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.discoverSock)
            this.discoverSock := -1
        }

        if (!this._BindListeners(prevTcp, prevUdp, prevDisc)) {
            if (!this._BindListeners(this.requestedTcpPort, this.requestedUdpPort, this.requestedDiscoverPort))
                return false
        }
        this.cachedEndpoints := GetLocalNetworkEndpoints()
        this.cachedEndpointsTick := A_TickCount
        this.lastEndpointsSig := _HB_GetEndpointsSignature(this.cachedEndpoints)
        this.lastAdapterCheckTick := A_TickCount
        this.lastWakeRefreshTick := A_TickCount
        this.BroadcastSyncResync(this.cfg, this.state, reason)
        return true
    }

    Stop() {
        this.running := false
        this._tcpEventQueue := []
        this._tcpDispatching := false
        if (this.maintTimerFn) {
            try SetTimer(this.maintTimerFn, 0)
            this.maintTimerFn := ""
        }
        if (this.tcpMsgFn) {
            try OnMessage(this.wmTcp, this.tcpMsgFn, 0)
            this.tcpMsgFn := ""
        }
        if (this.udpMsgFn) {
            try OnMessage(this.wmUdp, this.udpMsgFn, 0)
            this.udpMsgFn := ""
        }
        if (this.discoverMsgFn) {
            try OnMessage(this.wmDiscover, this.discoverMsgFn, 0)
            this.discoverMsgFn := ""
        }

        sockKeys := []
        for k, _ in this.clients
            sockKeys.Push(k)
        for k in sockKeys {
            cli := this.clients[k]
            try DllCall("ws2_32\closesocket", "Ptr", cli.sock)
        }
        this.clients := Map()

        if (this.tcpListenSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.tcpListenSock)
            this.tcpListenSock := -1
        }
        if (this.udpSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.udpSock)
            this.udpSock := -1
        }
        if (this.discoverSock != -1) {
            try DllCall("ws2_32\closesocket", "Ptr", this.discoverSock)
            this.discoverSock := -1
        }
        if (IsObject(this.msgGui)) {
            try this.msgGui.Destroy()
            this.msgGui := ""
        }
        this.hwnd := 0
        this.boundTcpPort := 0
        this.boundUdpPort := 0
        this.boundDiscoverPort := 0
        if (IsObject(this.state) && this.state.HasOwnProp("activeBridgePort"))
            this.state.activeBridgePort := 0
        if (this.wsaStarted) {
            try DllCall("ws2_32\WSACleanup")
            this.wsaStarted := false
        }
    }

    RotateSessionCode(revokePaired := false) {
        newCode := GenerateSessionPairingCode()
        this.cfg.SessionPairingCode := newCode
        if (IsObject(this.cfg) && this.cfg.HasMethod("Write"))
            try this.cfg.Write("Settings", "SessionPairingCode", newCode)
        this.rateLimits := Map()
        if (revokePaired)
            this.RevokeAllDevices()
        return newCode
    }

    _GetIniPath() {
        if (IsObject(this.cfg) && this.cfg.HasOwnProp("ConfigFile") && this.cfg.ConfigFile != "")
            return this.cfg.ConfigFile
        return ""
    }

    LoadPairedDevices() {
        this.pairedDevices := Map()
        this.validTokens := Map()
        iniPath := this._GetIniPath()
        if (iniPath = "" || !FileExist(iniPath))
            return
        rawSection := ""
        try rawSection := IniRead(iniPath, "HostBridgePairedDevices", , "")
        if (rawSection = "")
            return
        for _, line in StrSplit(rawSection, "`n", "`r") {
            trimmed := Trim(line)
            eqPos := InStr(trimmed, "=")
            if (eqPos <= 1)
                continue
            devId := UriDecodeComponent(SubStr(trimmed, 1, eqPos - 1))
            val := SubStr(trimmed, eqPos + 1)
            parsed := _HB_ParsePairedDevice(devId, val)
            if (IsObject(parsed)) {
                this.pairedDevices[parsed.deviceId] := parsed
                if (parsed.token != "")
                    this.validTokens[parsed.token] := parsed.deviceId
            }
        }
    }

    SavePairedDevices() {
        iniPath := this._GetIniPath()
        if (iniPath = "")
            return false
        try IniDelete(iniPath, "HostBridgePairedDevices")
        for devId, d in this.pairedDevices {
            iniKey := UriEncodeComponent(devId)
            if (iniKey = "")
                continue
            try IniWrite(_HB_SerializePairedDevice(d), iniPath, "HostBridgePairedDevices", iniKey)
        }
        return true
    }

    RenamePairedDevice(devId, newName) {
        cleanName := RegExReplace(Trim(String(newName)), "[\r\n\t]", " ")
        cleanName := SubStr(Trim(cleanName), 1, 64)
        if (cleanName = "" || !this.pairedDevices.Has(devId))
            return false
        this.pairedDevices[devId].deviceName := cleanName
        this.pairedDevices[devId].customName := true
        for _, cli in this.clients {
            if (cli.deviceId = devId)
                cli.deviceName := cleanName
        }
        this.SavePairedDevices()
        return true
    }

    UnpairDevice(devId) {
        if (devId = "" || !this.pairedDevices.Has(devId))
            return false
        dev := this.pairedDevices[devId]
        if (dev.HasOwnProp("token") && dev.token != "" && this.validTokens.Has(dev.token))
            this.validTokens.Delete(dev.token)
        staleTokens := []
        for tok, ownerId in this.validTokens {
            if (ownerId = devId)
                staleTokens.Push(tok)
        }
        for tok in staleTokens
            this.validTokens.Delete(tok)
        this.pairedDevices.Delete(devId)

        targets := []
        for _, cli in this.clients {
            if (cli.deviceId = devId)
                targets.Push(cli)
        }
        for cli in targets {
            if (cli.kind = "ws") {
                this._QueueWsFrame(cli, 0x1, '{"type":"auth_error","error":"Device unpaired by host"}')
                cli.closeAfterSend := true
                this._FlushSendQueue(cli)
            } else {
                this._CloseClient(cli)
            }
        }
        this.SavePairedDevices()
        return true
    }

    RevokeAllDevices() {
        targets := []
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated)
                targets.Push(cli)
        }
        this.validTokens := Map()
        this.pairedDevices := Map()
        this.SavePairedDevices()
        for cli in targets {
            this._QueueWsFrame(cli, 0x1, '{"type":"auth_error","error":"Session revoked by host"}')
            cli.closeAfterSend := true
            this._FlushSendQueue(cli)
        }
    }

    GetDeviceList() {
        list := []
        for _, d in this.pairedDevices {
            list.Push({
                deviceId: d.deviceId,
                deviceName: d.deviceName,
                platform: d.platform,
                ip: d.ip,
                transport: d.transport,
                pairedAt: d.pairedAt,
                connected: d.connected,
                customName: d.HasOwnProp("customName") ? d.customName : false
            })
        }
        return list
    }

    GetConnectedClientCount() {
        cnt := 0
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated)
                cnt += 1
        }
        return cnt
    }

    BroadcastMuteState(cfg, state) {
        if (!this.running)
            return 0
        return this._BroadcastJsonToAuthenticated(this._BuildMuteStateJson())
    }

    BroadcastSyncResync(cfg, state, reason := "wake") {
        if (!this.running)
            return 0
        return this._BroadcastJsonToAuthenticated(this._BuildSyncResyncJson(reason))
    }

    BroadcastStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B") {
        if (!this.running)
            return 0
        payload := '{"type":"stage_nudge","message":"' _HB_JsonEscape(message) '","sender":"' _HB_JsonEscape(sender) '","accentHex":"' _HB_JsonEscape(accentHex) '","timestamp":' A_TickCount '}'
        return this._BroadcastJsonToAuthenticated(payload)
    }

    _BroadcastJsonToAuthenticated(payload) {
        sent := 0
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated) {
                this._QueueWsFrame(cli, 0x1, payload)
                sent += 1
            }
        }
        return sent
    }

    BroadcastCloseRemote() {
        if (!this.running)
            return 0
        payload := '{"type":"close_remote","command":"CloseRemote","presenterSyncAction":"CloseRemote","timestamp":' A_TickCount '}'
        return this._BroadcastJsonToAuthenticated(payload)
    }

    _GetRateLimit(ip) {
        if (!this.rateLimits.Has(ip))
            this.rateLimits[ip] := { fails: 0, lockUntil: 0, lastUdpTick: 0, lastV1Tick: 0 }
        return this.rateLimits[ip]
    }

    _IsPairingRateLimited(ip) {
        rl := this._GetRateLimit(ip)
        return (rl.lockUntil > 0 && A_TickCount < rl.lockUntil)
    }

    _RecordPairingFailure(ip) {
        rl := this._GetRateLimit(ip)
        rl.fails += 1
        if (rl.fails >= HostBridgeConstants.PAIR_MAX_FAILS)
            rl.lockUntil := A_TickCount + HostBridgeConstants.PAIR_LOCKOUT_MS
    }

    _ResetPairingFailures(ip) {
        rl := this._GetRateLimit(ip)
        rl.fails := 0
        rl.lockUntil := 0
    }

    _OnMaintenanceTick() {
        if (!this.running)
            return
        now := A_TickCount
        toClose := []
        toReap := []
        for k, cli in this.clients {
            if (cli.kind = "pending" && (now - cli.createdTick) > HostBridgeConstants.AUTH_TIMEOUT_MS) {
                toClose.Push(cli)
            } else if (cli.kind = "ws" && !cli.authenticated && (now - cli.createdTick) > HostBridgeConstants.AUTH_TIMEOUT_MS) {
                toClose.Push(cli)
            } else if (cli.kind = "ws" && cli.authenticated) {
                if ((now - cli.lastRxTick) > HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS) {
                    toReap.Push(cli)
                } else if ((now - cli.lastPingTick) >= HostBridgeConstants.KEEP_ALIVE_MS) {
                    cli.lastPingTick := now
                    this._QueueWsFrame(cli, 0x9, "")
                }
            }
        }
        for cli in toClose
            this._CloseClient(cli)
        for cli in toReap
            this._ReapDeadClient(cli, now)
        if ((now - this.lastAdapterCheckTick) >= 5000) {
            this.lastAdapterCheckTick := now
            latestEps := GetLocalNetworkEndpoints(false)
            latestSig := _HB_GetEndpointsSignature(latestEps)
            if (latestSig != "" && this.lastEndpointsSig != "" && latestSig != this.lastEndpointsSig) {
                this.cachedEndpoints := latestEps
                this.cachedEndpointsTick := now
                this.lastEndpointsSig := latestSig
                this.BroadcastSyncResync(this.cfg, this.state, "adapter_change")
            } else if ((now - this.cachedEndpointsTick) >= 30000) {
                this.cachedEndpoints := latestEps
                this.cachedEndpointsTick := now
            }
        }
    }

    ; v7.0.5 (#11): close a silent authenticated socket (no frame for > DEAD_CLIENT_TIMEOUT_MS).
    _ReapDeadClient(c, now := 0) {
        if (!this.clients.Has(c.key))
            return false
        if (!now)
            now := A_TickCount
        idleMs := now - c.lastRxTick
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Bridge", "ReapDeadClient"
                , "device=" (c.deviceName != "" ? c.deviceName : c.deviceId) " ip=" c.ip " idle=" idleMs "ms")
        ; Best-effort RFC6455 close frame; the peer is most likely gone, so don't wait on it.
        try this._QueueWsFrame(c, 0x8, "")
        this._CloseClient(c)
        return true
    }

    ; v7.0.5 (#11): when a device re-authenticates on a fresh socket, the old socket
    ; (half-open after sleep/Wi-Fi drop) must not linger as a duplicate "connected" client.
    _EvictStaleDeviceSockets(c, devId) {
        if (devId = "")
            return 0
        stale := []
        for _, cOld in this.clients {
            if (cOld.key != c.key && cOld.deviceId = devId)
                stale.Push(cOld)
        }
        for cOld in stale {
            if (IsSet(DiagnosticLogger))
                try DiagnosticLogger.RecordBreadcrumb("Bridge", "EvictStaleDeviceSocket", "device=" devId " oldIp=" cOld.ip " newIp=" c.ip)
            ; Clear identity first so _CloseClient doesn't flip the device to "disconnected"
            ; or log a spurious "Remote Disconnected" timeline event for the replaced socket.
            cOld.deviceId := ""
            cOld.authenticated := false
            if (cOld.kind = "ws")
                try this._QueueWsFrame(cOld, 0x8, "")
            this._CloseClient(cOld)
        }
        return stale.Length
    }

    _IssueSessionToken(devId) {
        hostCode := (IsObject(this.cfg) && this.cfg.HasOwnProp("SessionPairingCode")) ? NormalizePairingCode(this.cfg.SessionPairingCode) : ""
        rnd := GenerateRandomBytes(16)
        rndHex := ""
        Loop 16
            rndHex .= Format("{:02x}", NumGet(rnd, A_Index - 1, "UChar"))
        return HashSHA256_Hex(hostCode ":" devId ":" rndHex ":" A_TickCount)
    }

    _BuildAuthOkJson(c) {
        tokField := (IsObject(c) && c.HasOwnProp("sessionToken") && c.sessionToken != "")
            ? ',"sessionToken":"' _HB_JsonEscape(c.sessionToken) '"'
            : ""
        return '{"type":"auth_ok","hostUuid":"' _HB_JsonEscape(EnsureHostUuid(this.cfg)) '","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '"' tokField '}'
    }

    _OnUdpMessage(wParam, lParam, msg, hwnd) {
        this._HandleUdpSocket(this.udpSock, lParam)
    }

    _OnDiscoverMessage(wParam, lParam, msg, hwnd) {
        this._HandleUdpSocket(this.discoverSock, lParam)
    }

    _HandleUdpSocket(targetSock, lParam) {
        if (!this.running || targetSock = -1)
            return
        ev := lParam & 0xFFFF
        if (ev != 1)
            return

        rxBuf := Buffer(2048, 0)
        fromAddr := Buffer(16, 0)
        Loop {
            fromLen := 16
            n := DllCall("ws2_32\recvfrom", "Ptr", targetSock, "Ptr", rxBuf, "Int", 2048, "Int", 0, "Ptr", fromAddr, "Int*", &fromLen, "Int")
            if (n <= 0)
                break
            NumPut("UChar", 0, rxBuf, Min(n, 2047))
            pkt := Trim(StrGet(rxBuf, "UTF-8"))
            ip := _HB_FormatIp(fromAddr)
            rl := this._GetRateLimit(ip)
            now := A_TickCount
            if (this._IsPairingRateLimited(ip))
                continue

            ; Public classroom discovery v1 (PS_DISCOVER_V1 -> safe zero-secret JSON beacon)
            if (pkt = HostBridgeConstants.DISCOVER_V1_PROTO || SubStr(pkt, 1, StrLen(HostBridgeConstants.DISCOVER_V1_PROTO) + 1) = HostBridgeConstants.DISCOVER_V1_PROTO "|") {
                if ((now - rl.lastV1Tick) < 80)
                    continue
                rl.lastV1Tick := now
                reply := BuildPublicDiscoveryBeaconJson(this.cfg, this.boundTcpPort, 4455)
                rLen := 0
                rBuf := _HB_StrToUtf8Buf(reply, &rLen)
                DllCall("ws2_32\sendto", "Ptr", targetSock, "Ptr", rBuf, "Int", rLen, "Int", 0, "Ptr", fromAddr, "Int", 16, "Int")
                continue
            }

            if ((now - rl.lastUdpTick) < HostBridgeConstants.UDP_COOLDOWN_MS)
                continue
            rl.lastUdpTick := now

            parts := StrSplit(pkt, "|")
            if (parts.Length >= 2 && parts[1] = "PSYNC_DISCOVER") {
                reqCode := NormalizePairingCode(parts[2])
                hostCode := NormalizePairingCode(this.cfg.SessionPairingCode)
                if (reqCode != "" && reqCode == hostCode) {
                    this._ResetPairingFailures(ip)
                    mode := this.cfg.HasOwnProp("AudioRoutingMode") ? this.cfg.AudioRoutingMode : 0
                    reply := "PSYNC_OFFER|" A_ComputerName "|" this.boundTcpPort "|4455|" UIConstants.APP_VERSION "|" mode
                    rLen := 0
                    rBuf := _HB_StrToUtf8Buf(reply, &rLen)
                    DllCall("ws2_32\sendto", "Ptr", targetSock, "Ptr", rBuf, "Int", rLen, "Int", 0, "Ptr", fromAddr, "Int", 16, "Int")
                } else {
                    this._RecordPairingFailure(ip)
                }
            }
        }
    }

    _OnTcpMessage(wParam, lParam, msg, hwnd) {
        if (!this.running)
            return 0
        this._tcpEventQueue.Push({ w: wParam, l: lParam })
        if (this._tcpDispatching)
            return 0
        this._tcpDispatching := true
        try {
            while (this.running && this._tcpEventQueue.Length > 0) {
                evItem := this._tcpEventQueue.RemoveAt(1)
                this._ProcessTcpEvent(evItem.w, evItem.l)
            }
        } finally {
            this._tcpDispatching := false
        }
        return 0
    }

    _ProcessTcpEvent(wParam, lParam) {
        if (!this.running)
            return
        sock := wParam
        ev := lParam & 0xFFFF

        if (sock = this.tcpListenSock) {
            if (ev & 8) { ; FD_ACCEPT
                Loop {
                    peerAddr := Buffer(16, 0)
                    addrLen := 16
                    clientSock := DllCall("ws2_32\accept", "Ptr", this.tcpListenSock, "Ptr", peerAddr, "Int*", &addrLen, "Ptr")
                    if (clientSock = -1)
                        break
                    key := String(clientSock)
                    this.clients[key] := {
                        sock: clientSock,
                        key: key,
                        ip: _HB_FormatIp(peerAddr),
                        kind: "pending",
                        recvBuf: Buffer(4096, 0),
                        recvLen: 0,
                        sendBuf: Buffer(4096, 0),
                        sendLen: 0,
                        closeAfterSend: false,
                        peerClosed: false,
                        authenticated: false,
                        deviceId: "",
                        deviceName: "Smart Board",
                        platform: "Remote",
                        createdTick: A_TickCount,
                        lastRxTick: A_TickCount,
                        lastPingTick: A_TickCount,
                        fragBuf: Buffer(0),
                        fragLen: 0
                    }
                    ; FD_READ(1) | FD_WRITE(2) | FD_CLOSE(32) = 0x23
                    if (DllCall("ws2_32\WSAAsyncSelect", "Ptr", clientSock, "Ptr", this.hwnd, "UInt", this.wmTcp, "Int", 0x23, "Int") != 0) {
                        this.clients.Delete(key)
                        try DllCall("ws2_32\closesocket", "Ptr", clientSock)
                    }
                }
            }
            return
        }

        key := String(sock)
        if (!this.clients.Has(key))
            return
        cli := this.clients[key]

        if (ev & 1) { ; FD_READ
            this._DrainRecv(cli)
            if (this.clients.Has(key))
                this._ProcessClientBuffer(cli)
            if (this.clients.Has(key) && cli.peerClosed && cli.sendLen = 0 && cli.recvLen = 0)
                this._CloseClient(cli)
        }
        if (this.clients.Has(key) && (ev & 2)) { ; FD_WRITE
            this._FlushSendQueue(cli)
        }
        if (this.clients.Has(key) && (ev & 32)) { ; FD_CLOSE
            this._DrainRecv(cli)
            if (this.clients.Has(key))
                this._ProcessClientBuffer(cli)
            if (this.clients.Has(key))
                this._CloseClient(cli)
        }
    }

    _DrainRecv(c) {
        tmp := Buffer(8192, 0)
        Loop {
            n := DllCall("ws2_32\recv", "Ptr", c.sock, "Ptr", tmp, "Int", 8192, "Int", 0, "Int")
            if (n > 0) {
                res := _HB_AppendBytes(c.recvBuf, c.recvLen, tmp.Ptr, n, HostBridgeConstants.MAX_BUFFER_BYTES)
                if (!IsObject(res)) {
                    this._CloseClient(c)
                    return
                }
                c.recvBuf := res.buf
                c.recvLen := res.len
                c.lastRxTick := A_TickCount
            } else if (n = 0) {
                c.peerClosed := true
                return
            } else {
                wsaErr := DllCall("ws2_32\WSAGetLastError", "Int")
                if (wsaErr != 10035) ; WSAEWOULDBLOCK
                    this._CloseClient(c)
                return
            }
        }
    }

    _QueueRawBytes(c, srcPtr, byteLen) {
        if (byteLen <= 0)
            return
        if (c.sendLen = 0) {
            sent := DllCall("ws2_32\send", "Ptr", c.sock, "Ptr", srcPtr, "Int", byteLen, "Int", 0, "Int")
            if (sent = byteLen) {
                if (c.closeAfterSend)
                    this._CloseClient(c)
                return
            }
            offset := (sent > 0) ? sent : 0
            rem := byteLen - offset
            if (sent < 0) {
                wsaErr := DllCall("ws2_32\WSAGetLastError", "Int")
                if (wsaErr != 10035) {
                    this._CloseClient(c)
                    return
                }
            }
            res := _HB_AppendBytes(c.sendBuf, c.sendLen, srcPtr + offset, rem, HostBridgeConstants.MAX_BUFFER_BYTES * 2)
            if (!IsObject(res)) {
                this._CloseClient(c)
                return
            }
            c.sendBuf := res.buf
            c.sendLen := res.len
            return
        }

        res := _HB_AppendBytes(c.sendBuf, c.sendLen, srcPtr, byteLen, HostBridgeConstants.MAX_BUFFER_BYTES * 2)
        if (!IsObject(res)) {
            this._CloseClient(c)
            return
        }
        c.sendBuf := res.buf
        c.sendLen := res.len
        this._FlushSendQueue(c)
    }

    _QueueText(c, str) {
        bLen := 0
        bBuf := _HB_StrToUtf8Buf(str, &bLen)
        if (bLen > 0)
            this._QueueRawBytes(c, bBuf.Ptr, bLen)
    }

    _FlushSendQueue(c) {
        while (c.sendLen > 0) {
            sent := DllCall("ws2_32\send", "Ptr", c.sock, "Ptr", c.sendBuf.Ptr, "Int", c.sendLen, "Int", 0, "Int")
            if (sent > 0) {
                c.sendLen := _HB_ConsumeBytes(c.sendBuf, c.sendLen, sent)
            } else {
                wsaErr := DllCall("ws2_32\WSAGetLastError", "Int")
                if (wsaErr != 10035) {
                    this._CloseClient(c)
                    return
                }
                break
            }
        }
        if (c.sendLen = 0 && c.closeAfterSend)
            this._CloseClient(c)
    }

    _QueueWsFrame(c, opcode, payloadStr) {
        pLen := 0
        pBuf := _HB_StrToUtf8Buf(payloadStr, &pLen)
        hdrLen := (pLen <= 125) ? 2 : 4
        frame := Buffer(hdrLen + pLen, 0)
        NumPut("UChar", 0x80 | (opcode & 0x0F), frame, 0)
        if (pLen <= 125) {
            NumPut("UChar", pLen, frame, 1)
        } else {
            NumPut("UChar", 126, frame, 1)
            NumPut("UChar", (pLen >> 8) & 0xFF, frame, 2)
            NumPut("UChar", pLen & 0xFF, frame, 3)
        }
        if (pLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", frame.Ptr + hdrLen, "Ptr", pBuf.Ptr, "UPtr", pLen)
        this._QueueRawBytes(c, frame.Ptr, hdrLen + pLen)
    }

    _SendHttpResponse(c, statusLine, jsonBody, extraHeaders := "") {
        bLen := 0
        _HB_StrToUtf8Buf(jsonBody, &bLen)
        hdr := "HTTP/1.1 " statusLine "`r`n"
            . "Content-Type: application/json; charset=utf-8`r`n"
            . "Content-Length: " bLen "`r`n"
            . "Connection: close`r`n"
            . extraHeaders
            . "`r`n"
        c.closeAfterSend := true
        this._QueueText(c, hdr . jsonBody)
    }

    _CloseClient(c) {
        key := c.key
        if (!this.clients.Has(key))
            return
        this.clients.Delete(key)
        try DllCall("ws2_32\closesocket", "Ptr", c.sock)
        if (c.deviceId != "" && this.pairedDevices.Has(c.deviceId)) {
            stillConnected := false
            for _, other in this.clients {
                if (other.authenticated && other.deviceId = c.deviceId) {
                    stillConnected := true
                    break
                }
            }
            this.pairedDevices[c.deviceId].connected := stillConnected
            if (!stillConnected && c.authenticated && IsSet(SessionTimeline))
                SessionTimeline.Record("Remote", "Remote Disconnected: " (c.deviceName != "" ? c.deviceName : c.deviceId), this.state, c.platform)
        }
    }

    _FindHttpHeaderEnd(buf, len) {
        if (len < 4)
            return 0
        Loop (len - 3) {
            i := A_Index - 1
            if (NumGet(buf, i, "UChar") = 13 && NumGet(buf, i + 1, "UChar") = 10
                && NumGet(buf, i + 2, "UChar") = 13 && NumGet(buf, i + 3, "UChar") = 10)
                return i + 4
        }
        return 0
    }

    _ProcessClientBuffer(c) {
        if (c.kind = "pending") {
            hdrEnd := this._FindHttpHeaderEnd(c.recvBuf, c.recvLen)
            if (!hdrEnd) {
                if (c.recvLen > 16384)
                    this._SendHttpResponse(c, "400 Bad Request", '{"ok":false,"error":"Headers too large"}')
                return
            }

            hdrBuf := Buffer(hdrEnd + 1, 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", hdrBuf.Ptr, "Ptr", c.recvBuf.Ptr, "UPtr", hdrEnd)
            hdrText := StrGet(hdrBuf, "UTF-8")

            firstCr := InStr(hdrText, "`r`n")
            reqLine := firstCr ? SubStr(hdrText, 1, firstCr - 1) : hdrText
            if (!RegExMatch(reqLine, "^(GET|POST|OPTIONS)\s+(\S+)\s+HTTP/", &mReq)) {
                this._SendHttpResponse(c, "400 Bad Request", '{"ok":false,"error":"Invalid HTTP request"}')
                return
            }
            method := StrUpper(mReq[1])
            rawPath := mReq[2]
            cleanPath := InStr(rawPath, "?") ? SubStr(rawPath, 1, InStr(rawPath, "?") - 1) : rawPath

            if (method = "GET" && cleanPath = "/health") {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                mode := this.cfg.HasOwnProp("AudioRoutingMode") ? this.cfg.AudioRoutingMode : 0
                uuid := EnsureHostUuid(this.cfg)
                body := '{"ok":true,"hostUuid":"' _HB_JsonEscape(uuid) '","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '","bridgePort":' this.boundTcpPort ',"obsPort":4455,"routingMode":' mode '}'
                this._SendHttpResponse(c, "200 OK", body)
                return
            }

            if (method = "GET" && (cleanPath = "/ws" || RegExMatch(hdrText, "i)Upgrade:\s*websocket"))) {
                this._HandleWsUpgrade(c, hdrText, rawPath, hdrEnd)
                return
            }

            if (method = "POST" && cleanPath = "/pair") {
                contentLen := 0
                if (RegExMatch(hdrText, "i)Content-Length:\s*(\d+)", &mLen))
                    contentLen := Integer(mLen[1])
                if (contentLen > 8192) {
                    this._SendHttpResponse(c, "413 Payload Too Large", '{"ok":false,"error":"Payload too large"}')
                    return
                }
                if (c.recvLen < (hdrEnd + contentLen))
                    return ; Wait for rest of HTTP body

                bodyText := ""
                if (contentLen > 0) {
                    bTmp := Buffer(contentLen + 1, 0)
                    DllCall("ntdll\RtlMoveMemory", "Ptr", bTmp.Ptr, "Ptr", c.recvBuf.Ptr + hdrEnd, "UPtr", contentLen)
                    bodyText := StrGet(bTmp, "UTF-8")
                }
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd + contentLen)
                this._HandleHttpPairRequest(c, bodyText)
                return
            }

            c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
            this._SendHttpResponse(c, "404 Not Found", '{"ok":false,"error":"Not found"}')
            return
        }

        if (c.kind = "ws")
            this._DrainWsFrames(c)
    }

    _HandleHttpPairRequest(c, bodyText) {
        if (this._IsPairingRateLimited(c.ip)) {
            this._SendHttpResponse(c, "429 Too Many Requests", '{"ok":false,"error":"Too many invalid pairing attempts. Try again in 30s."}', "Retry-After: 30`r`n")
            return
        }

        reqCode := NormalizePairingCode(_HB_JsonExtractStr(bodyText, "code"))
        devId := _HB_JsonExtractStr(bodyText, "deviceId")
        if (devId = "")
            devId := "device-" c.ip "-" c.sock
        devName := _HB_JsonExtractStr(bodyText, "deviceName")
        if (devName = "")
            devName := "Smart Board"
        plat := _HB_JsonExtractStr(bodyText, "platform")
        if (plat = "")
            plat := "Android"

        hostCode := NormalizePairingCode(this.cfg.SessionPairingCode)
        if (reqCode = "" || reqCode != hostCode) {
            this._RecordPairingFailure(c.ip)
            this._SendHttpResponse(c, "401 Unauthorized", '{"ok":false,"error":"Invalid pairing code"}')
            return
        }

        this._ResetPairingFailures(c.ip)
        if (this.pairedDevices.Has(devId)) {
            oldTok := this.pairedDevices[devId].token
            if (oldTok != "" && this.validTokens.Has(oldTok))
                this.validTokens.Delete(oldTok)
            if (this.pairedDevices[devId].HasOwnProp("customName") && this.pairedDevices[devId].customName && this.pairedDevices[devId].deviceName != "")
                devName := this.pairedDevices[devId].deviceName
        }
        hadCustom := this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("customName") && this.pairedDevices[devId].customName
        sessionToken := this._IssueSessionToken(devId)

        this.validTokens[sessionToken] := devId
        this.pairedDevices[devId] := {
            deviceId: devId,
            deviceName: devName,
            platform: plat,
            ip: c.ip,
            transport: "Paired",
            token: sessionToken,
            pairedAt: FormatTime(, "HH:mm:ss"),
            lastSeenTick: A_TickCount,
            connected: false,
            customName: hadCustom
        }
        this.SavePairedDevices()

        endpoints := IsObject(this.cachedEndpoints) ? this.cachedEndpoints : GetLocalNetworkEndpoints()
        ipsJson := "["
        for idx, ipStr in endpoints.ips
            ipsJson .= (idx > 1 ? "," : "") '"' _HB_JsonEscape(ipStr) '"'
        ipsJson .= "]"

        mode := this.cfg.HasOwnProp("AudioRoutingMode") ? this.cfg.AudioRoutingMode : 0
        confApp := this.cfg.HasOwnProp("ConferencingApp") ? this.cfg.ConferencingApp : "Zoom"
        isMutedStr := (this.state.HasOwnProp("isMuted") && this.state.isMuted) ? "true" : "false"
        obsPw := this.cfg.HasOwnProp("obsPassword") ? this.cfg.obsPassword : ""
        micName := this.cfg.HasOwnProp("targetMicName") ? this.cfg.targetMicName : "Mic/Aux"
        relayCode := this.cfg.HasOwnProp("InternetPairingCode") ? this.cfg.InternetPairingCode : ""

        hostUuid := EnsureHostUuid(this.cfg)
        resp := '{'
            . '"ok":true,'
            . '"hostUuid":"' _HB_JsonEscape(hostUuid) '",'
            . '"hostName":"' _HB_JsonEscape(A_ComputerName) '",'
            . '"version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '",'
            . '"bridgePort":' this.boundTcpPort ','
            . '"obsPort":4455,'
            . '"obsPassword":"' _HB_JsonEscape(obsPw) '",'
            . '"targetMicName":"' _HB_JsonEscape(micName) '",'
            . '"routingMode":' mode ','
            . '"conferencingApp":"' _HB_JsonEscape(confApp) '",'
            . '"isMuted":' isMutedStr ','
            . '"internetPairingCode":"' _HB_JsonEscape(relayCode) '",'
            . '"sessionToken":"' _HB_JsonEscape(sessionToken) '",'
            . '"ips":' ipsJson ','
            . '"mdns":"' _HB_JsonEscape(A_ComputerName ".local") '"'
            . '}'
        this._SendHttpResponse(c, "200 OK", resp)
    }

    _HandleWsUpgrade(c, hdrText, rawPath, hdrEnd) {
        if (!RegExMatch(hdrText, "i)Sec-WebSocket-Key:\s*([^\r\n]+)", &mKey)) {
            this._SendHttpResponse(c, "400 Bad Request", '{"ok":false,"error":"Missing Sec-WebSocket-Key"}')
            return
        }
        secKey := Trim(mKey[1])
        acceptKey := HashSHA1_Base64(secKey . HostBridgeConstants.WS_GUID)

        qParams := _HB_ParseQueryParams(rawPath)
        qToken := qParams.Get("token", "")
        if (qToken = "" && RegExMatch(hdrText, "i)X-PresenterSync-Token:\s*([^\r\n]+)", &mTok))
            qToken := Trim(mTok[1])
        qCode := qParams.Get("code", "")
        qDevId := qParams.Get("deviceId", "")
        qDevName := qParams.Get("deviceName", "")
        qPlat := qParams.Get("platform", "Remote")

        c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
        c.kind := "ws"

        upgradeHdr := "HTTP/1.1 101 Switching Protocols`r`n"
            . "Upgrade: websocket`r`n"
            . "Connection: Upgrade`r`n"
            . "Sec-WebSocket-Accept: " acceptKey "`r`n"
            . "`r`n"
        this._QueueText(c, upgradeHdr)

        if (qToken != "" || qCode != "") {
            if (!this._TryAuthenticateWsClient(c, qToken, qCode, qDevId, qDevName, qPlat)) {
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Unauthorized"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return
            }
            this._QueueWsFrame(c, 0x1, this._BuildAuthOkJson(c))
            this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
        }

        if (c.recvLen > 0)
            this._DrainWsFrames(c)
    }

    _TryAuthenticateWsClient(c, token, code, devId, devName, plat) {
        if (this._IsPairingRateLimited(c.ip))
            return false

        matched := false
        matchedByToken := false
        matchedDevId := ""
        if (token != "" && this.validTokens.Has(token)) {
            matched := true
            matchedByToken := true
            matchedDevId := this.validTokens[token]
        } else if (code != "" && IsObject(this.cfg) && this.cfg.HasOwnProp("SessionPairingCode") && this.cfg.SessionPairingCode != "") {
            if (NormalizePairingCode(code) == NormalizePairingCode(this.cfg.SessionPairingCode)) {
                matched := true
                this._ResetPairingFailures(c.ip)
            } else {
                this._RecordPairingFailure(c.ip)
            }
        }
        if (!matched)
            return false

        finalDevId := (devId != "") ? devId : (matchedDevId != "" ? matchedDevId : ("ws-" c.ip "-" c.sock))
        hadCustom := this.pairedDevices.Has(finalDevId) && this.pairedDevices[finalDevId].HasOwnProp("customName") && this.pairedDevices[finalDevId].customName
        finalName := (hadCustom && this.pairedDevices[finalDevId].deviceName != "") ? this.pairedDevices[finalDevId].deviceName : ((devName != "") ? devName : (this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].deviceName : "Smart Board"))
        finalPlat := (plat != "") ? plat : (this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].platform : "Remote")

        if (matchedByToken) {
            tokToKeep := token
        } else if (this.pairedDevices.Has(finalDevId) && this.pairedDevices[finalDevId].HasOwnProp("token") && this.pairedDevices[finalDevId].token != "") {
            tokToKeep := this.pairedDevices[finalDevId].token
        } else {
            tokToKeep := this._IssueSessionToken(finalDevId)
        }

        c.authenticated := true
        c.deviceId := finalDevId
        c.deviceName := finalName
        c.platform := finalPlat
        c.sessionToken := tokToKeep
        c.lastRxTick := A_TickCount
        this._EvictStaleDeviceSockets(c, finalDevId)

        this.pairedDevices[finalDevId] := {
            deviceId: finalDevId,
            deviceName: finalName,
            platform: finalPlat,
            ip: c.ip,
            transport: "Bridge WS",
            token: tokToKeep,
            pairedAt: (this.pairedDevices.Has(finalDevId) && this.pairedDevices[finalDevId].pairedAt != "") ? this.pairedDevices[finalDevId].pairedAt : FormatTime(, "HH:mm:ss"),
            lastSeenTick: A_TickCount,
            connected: true,
            customName: hadCustom
        }
        if (tokToKeep != "")
            this.validTokens[tokToKeep] := finalDevId
        this.SavePairedDevices()
        return true
    }

    _DrainWsFrames(c) {
        while (c.recvLen >= 2) {
            b0 := NumGet(c.recvBuf, 0, "UChar")
            b1 := NumGet(c.recvBuf, 1, "UChar")
            fin := (b0 & 0x80) != 0
            opcode := b0 & 0x0F
            masked := (b1 & 0x80) != 0
            len7 := b1 & 0x7F

            offset := 2
            payloadLen := len7
            if (len7 = 126) {
                if (c.recvLen < 4)
                    break
                payloadLen := (NumGet(c.recvBuf, 2, "UChar") << 8) | NumGet(c.recvBuf, 3, "UChar")
                offset := 4
            } else if (len7 = 127) {
                if (c.recvLen < 10)
                    break
                hi := (NumGet(c.recvBuf, 2, "UChar") << 24) | (NumGet(c.recvBuf, 3, "UChar") << 16)
                    | (NumGet(c.recvBuf, 4, "UChar") << 8) | NumGet(c.recvBuf, 5, "UChar")
                lo := (NumGet(c.recvBuf, 6, "UChar") << 24) | (NumGet(c.recvBuf, 7, "UChar") << 16)
                    | (NumGet(c.recvBuf, 8, "UChar") << 8) | NumGet(c.recvBuf, 9, "UChar")
                if (hi != 0 || lo > HostBridgeConstants.MAX_BUFFER_BYTES) {
                    this._CloseClient(c)
                    return
                }
                payloadLen := lo
                offset := 10
            }

            if (payloadLen > HostBridgeConstants.MAX_BUFFER_BYTES) {
                this._CloseClient(c)
                return
            }

            maskOff := offset
            if (masked)
                offset += 4
            totalLen := offset + payloadLen
            if (c.recvLen < totalLen)
                break

            payloadBuf := Buffer(Max(1, payloadLen + 1), 0)
            if (payloadLen > 0) {
                if (masked) {
                    m0 := NumGet(c.recvBuf, maskOff, "UChar")
                    m1 := NumGet(c.recvBuf, maskOff + 1, "UChar")
                    m2 := NumGet(c.recvBuf, maskOff + 2, "UChar")
                    m3 := NumGet(c.recvBuf, maskOff + 3, "UChar")
                    masks := [m0, m1, m2, m3]
                    Loop payloadLen {
                        i := A_Index - 1
                        byteVal := NumGet(c.recvBuf, offset + i, "UChar") ^ masks[Mod(i, 4) + 1]
                        NumPut("UChar", byteVal, payloadBuf, i)
                    }
                } else {
                    DllCall("ntdll\RtlMoveMemory", "Ptr", payloadBuf.Ptr, "Ptr", c.recvBuf.Ptr + offset, "UPtr", payloadLen)
                }
            }
            NumPut("UChar", 0, payloadBuf, payloadLen)
            c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, totalLen)
            c.lastRxTick := A_TickCount ; any complete frame (ping/pong/text) proves liveness

            if (opcode = 0x8) { ; Close
                this._QueueWsFrame(c, 0x8, "")
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                if (this.clients.Has(c.key))
                    this._CloseClient(c)
                return
            } else if (opcode = 0x9) { ; Ping -> Pong
                pongTxt := (payloadLen > 0) ? StrGet(payloadBuf, "UTF-8") : ""
                this._QueueWsFrame(c, 0xA, pongTxt)
                continue
            } else if (opcode = 0xA) { ; Pong
                c.lastRxTick := A_TickCount
                continue
            } else if (opcode = 0x1 || opcode = 0x0) {
                if (!fin || opcode = 0x0) {
                    res := _HB_AppendBytes(c.fragBuf, c.fragLen, payloadBuf.Ptr, payloadLen, HostBridgeConstants.MAX_BUFFER_BYTES)
                    if (!IsObject(res)) {
                        this._CloseClient(c)
                        return
                    }
                    c.fragBuf := res.buf
                    c.fragLen := res.len
                    if (fin) {
                        msgBuf := Buffer(c.fragLen + 1, 0)
                        if (c.fragLen > 0)
                            DllCall("ntdll\RtlMoveMemory", "Ptr", msgBuf.Ptr, "Ptr", c.fragBuf.Ptr, "UPtr", c.fragLen)
                        c.fragLen := 0
                        text := StrGet(msgBuf, "UTF-8")
                        this._HandleWsTextMessage(c, text)
                    }
                } else {
                    text := (payloadLen > 0) ? StrGet(payloadBuf, "UTF-8") : ""
                    this._HandleWsTextMessage(c, text)
                }
                if (!this.clients.Has(c.key))
                    return
            }
        }
    }

    _HandleBridgeMessage(c, msg) {
        return this._HandleWsTextMessage(c, msg)
    }

    _HandleWsTextMessage(c, msg) {
        c.lastRxTick := A_TickCount
        msgType := StrLower(_HB_JsonExtractStr(msg, "type"))

        if (!c.authenticated) {
            if (msgType != "auth") {
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Authentication required"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return
            }
            tok := _HB_JsonExtractStr(msg, "token")
            code := _HB_JsonExtractStr(msg, "code")
            devId := _HB_JsonExtractStr(msg, "deviceId")
            devName := _HB_JsonExtractStr(msg, "deviceName")
            plat := _HB_JsonExtractStr(msg, "platform")
            if (!this._TryAuthenticateWsClient(c, tok, code, devId, devName, plat)) {
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Invalid token or pairing code"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return
            }
            this._QueueWsFrame(c, 0x1, this._BuildAuthOkJson(c))
            this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            if (IsSet(SessionTimeline))
                SessionTimeline.Record("Remote", "Remote Joined: " (c.deviceName != "" ? c.deviceName : c.deviceId), this.state, c.platform)
            return
        }

        if (c.deviceId != "" && this.pairedDevices.Has(c.deviceId))
            this.pairedDevices[c.deviceId].lastSeenTick := A_TickCount

        switch (msgType) {
            case "toggle_mute":
                ExecuteHostRemoteToggleMute(this.cfg, this.state)
            case "set_mute":
                targetMuted := _HB_JsonExtractBool(msg, "isMuted", this.state.isMuted)
                ExecuteHostRemoteSetMute(this.cfg, this.state, targetMuted)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "ppt_next":
                ok := ExecuteHostRemotePptCommand(this.cfg, this.state, "next")
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"ppt_next","ok":' (ok ? "true" : "false") '}')
            case "ppt_prev":
                ok := ExecuteHostRemotePptCommand(this.cfg, this.state, "prev")
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"ppt_prev","ok":' (ok ? "true" : "false") '}')
            case "slide_start":
                ok := IsSet(StartPowerPointSlideshow) ? StartPowerPointSlideshow() : false
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"slide_start","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "toggle_record":
                ok := ExecuteHostToggleRecord(this.cfg, this.state)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"toggle_record","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "pause_record":
                ok := ExecuteHostPauseRecord(this.cfg, this.state)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"pause_record","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "split_record":
                ok := ExecuteHostSplitRecord(this.cfg, this.state)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"split_record","ok":' (ok ? "true" : "false") '}')
            case "switch_scene":
                sName := _HB_JsonExtractStr(msg, "sceneName")
                ok := ExecuteHostSwitchScene(this.cfg, this.state, sName)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"switch_scene","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "transition_scene":
                ok := false
                if (IsObject(this.state) && this.state.HasOwnProp("triggerTransitionFn") && IsObject(this.state.triggerTransitionFn))
                    ok := (this.state.triggerTransitionFn.Call() != false)
                else if (IsSet(TriggerObsSceneTransition))
                    ok := TriggerObsSceneTransition(this.cfg, this.state, true)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"transition_scene","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "toggle_standby":
                ok := ExecuteHostToggleStandby(this.cfg, this.state)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"toggle_standby","ok":' (ok ? "true" : "false") '}')
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "timer_start":
                dur := _HB_JsonExtractInt(msg, "durationSec", 0)
                ok := StartHostPresenterTimer(this.cfg, this.state, dur)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"timer_start","ok":' (ok ? "true" : "false") '}')
            case "timer_pause":
                ok := PauseHostPresenterTimer(this.cfg, this.state)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"timer_pause","ok":' (ok ? "true" : "false") '}')
            case "timer_reset":
                dur := _HB_JsonExtractInt(msg, "durationSec", 0)
                ok := ResetHostPresenterTimer(this.cfg, this.state, dur)
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"timer_reset","ok":' (ok ? "true" : "false") '}')
            case "stage_nudge":
                nMsg := _HB_JsonExtractStr(msg, "message")
                nSnd := _HB_JsonExtractStr(msg, "sender")
                nAcc := _HB_JsonExtractStr(msg, "accentHex")
                if (nSnd = "")
                    nSnd := (c.deviceName != "") ? c.deviceName : "Remote"
                ok := BroadcastHostStageNudge(this.cfg, this.state, nMsg, nSnd, nAcc != "" ? nAcc : "F59E0B")
                this._QueueWsFrame(c, 0x1, '{"type":"ack","action":"stage_nudge","ok":' (ok ? "true" : "false") '}')
            case "sync_req":
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "ping":
                isMutedStr := this.state.isMuted ? "true" : "false"
                this._QueueWsFrame(c, 0x1, '{"type":"pong","isMuted":' isMutedStr ',"timestamp":' A_TickCount '}')
            case "unpair":
                this.UnpairDevice(c.deviceId)
        }
    }

    _BuildStateFieldsJson() {
        isMutedStr := (this.state.HasOwnProp("isMuted") && this.state.isMuted) ? "true" : "false"
        mode := this.cfg.HasOwnProp("AudioRoutingMode") ? this.cfg.AudioRoutingMode : 0
        micName := this.cfg.HasOwnProp("targetMicName") ? this.cfg.targetMicName : "Mic/Aux"
        confApp := this.cfg.HasOwnProp("ConferencingApp") ? this.cfg.ConferencingApp : "Zoom"
        recSt := this.state.HasOwnProp("recState") ? Integer(this.state.recState) : 0
        recSec := this.state.HasOwnProp("recElapsedSec") ? Max(0, Integer(this.state.recElapsedSec)) : 0
        obsRecSt := this.state.HasOwnProp("obsRecState") ? Integer(this.state.obsRecState) : 0
        confRecSt := this.state.HasOwnProp("confRecState") ? Integer(this.state.confRecState) : 0
        recSrcTag := this.state.HasOwnProp("recSourceTag") ? String(this.state.recSourceTag) : ""
        meetBgWarnStr := (this.state.HasOwnProp("meetBgTabWarn") && this.state.meetBgTabWarn) ? "true" : "false"
        detConfApp := this.state.HasOwnProp("detectedConfApp") ? String(this.state.detectedConfApp) : ""
        sIdx := this.state.HasOwnProp("slideIndex") ? Integer(this.state.slideIndex) : 0
        sTot := this.state.HasOwnProp("slideTotal") ? Integer(this.state.slideTotal) : 0
        sTitle := this.state.HasOwnProp("slideTitle") ? String(this.state.slideTitle) : ""
        sNotes := this.state.HasOwnProp("slideNotes") ? String(this.state.slideNotes) : ""
        streamWarnStr := ((this.state.HasOwnProp("streamDropWarn") && this.state.streamDropWarn) || (this.state.HasOwnProp("streamState") && this.state.streamState == 2)) ? "true" : "false"
        voiceMutedStr := (this.state.HasOwnProp("voiceWhileMuted") && this.state.voiceWhileMuted) ? "true" : "false"
        osDriftStr := (this.state.HasOwnProp("osMicMutedDrift") && this.state.osMicMutedDrift) ? "true" : "false"
        lowDiskLvl := this.state.HasOwnProp("lowDiskWarnLevel") ? Integer(this.state.lowDiskWarnLevel) : 0
        lowDiskMbVal := this.state.HasOwnProp("lowDiskMb") ? Integer(this.state.lowDiskMb) : -1
        deadMicStr := (this.state.HasOwnProp("deadMicWarn") && this.state.deadMicWarn) ? "true" : "false"
        obsConnStr := (this.state.HasOwnProp("obsConnected") && this.state.obsConnected) ? "true" : "false"
        activeScene := this.state.HasOwnProp("currentSceneName") ? String(this.state.currentSceneName) : "Scene"
        scenesJson := "["
        if (this.state.HasOwnProp("sceneList") && IsObject(this.state.sceneList)) {
            for idx, scName in this.state.sceneList {
                scenesJson .= (idx > 1 ? "," : "") '"' _HB_JsonEscape(scName) '"'
            }
        }
        scenesJson .= "]"
        standbyStr := (this.state.HasOwnProp("isStandby") && this.state.isStandby) ? "true" : "false"
        standbyScene := (this.cfg.HasOwnProp("StandbySceneName") && this.cfg.StandbySceneName != "") ? String(this.cfg.StandbySceneName) : "BRB"
        tState := this.state.HasOwnProp("timerState") ? String(this.state.timerState) : "stopped"
        tRem := this.state.HasOwnProp("timerRemainingSec") ? Integer(this.state.timerRemainingSec) : 600
        tPre := this.state.HasOwnProp("timerPresetSec") ? Integer(this.state.timerPresetSec) : 600
        hostUuid := EnsureHostUuid(this.cfg)
        return '"hostUuid":"' _HB_JsonEscape(hostUuid) '","isMuted":' isMutedStr ',"routingMode":' mode ',"targetMicName":"' _HB_JsonEscape(micName) '","conferencingApp":"' _HB_JsonEscape(confApp) '","detectedConfApp":"' _HB_JsonEscape(detConfApp) '","meetBgTabWarn":' meetBgWarnStr ',"slideIndex":' sIdx ',"slideTotal":' sTot ',"slideTitle":"' _HB_JsonEscape(sTitle) '","slideNotes":"' _HB_JsonEscape(sNotes) '","recState":' recSt ',"obsRecState":' obsRecSt ',"confRecState":' confRecSt ',"recSourceTag":"' _HB_JsonEscape(recSrcTag) '","recSeconds":' recSec ',"obsConnected":' obsConnStr ',"streamDropWarn":' streamWarnStr ',"voiceWhileMuted":' voiceMutedStr ',"osMicMutedDrift":' osDriftStr ',"lowDiskWarnLevel":' lowDiskLvl ',"lowDiskMb":' lowDiskMbVal ',"deadMicWarn":' deadMicStr ',"activeScene":"' _HB_JsonEscape(activeScene) '","scenes":' scenesJson ',"isStandby":' standbyStr ',"standbyScene":"' _HB_JsonEscape(standbyScene) '","timerState":"' _HB_JsonEscape(tState) '","timerRemainingSec":' tRem ',"timerPresetSec":' tPre ',"version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '","timestamp":' A_TickCount
    }

    _BuildMuteStateJson() {
        return '{"type":"mute_state",' this._BuildStateFieldsJson() '}'
    }

    _BuildSyncResyncJson(reason := "wake") {
        return '{"type":"sync_resync","reason":"' _HB_JsonEscape(reason) '",' this._BuildStateFieldsJson() '}'
    }
}

StartHostCompanionBridge(cfg, state, tcpPort := 4456, udpPort := -1, discoverPort := -1) {
    global g_HostCompanionBridge
    StopHostCompanionBridge()
    bridge := HostCompanionBridge()
    if (bridge.Start(cfg, state, tcpPort, udpPort, discoverPort)) {
        g_HostCompanionBridge := bridge
        return bridge
    }
    return bridge
}

StopHostCompanionBridge() {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge)) {
        try g_HostCompanionBridge.Stop()
        g_HostCompanionBridge := ""
    }
}

RotateHostSessionPairingCode(cfg, revokeAll := false) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.RotateSessionCode(revokeAll)
    newCode := GenerateSessionPairingCode()
    cfg.SessionPairingCode := newCode
    if (IsObject(cfg) && cfg.HasMethod("Write"))
        try cfg.Write("Settings", "SessionPairingCode", newCode)
    if (revokeAll && IsObject(cfg) && cfg.HasOwnProp("ConfigFile") && cfg.ConfigFile != "")
        try IniDelete(cfg.ConfigFile, "HostBridgePairedDevices")
    return newCode
}

RenameHostPairedDevice(devId, newName) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.RenamePairedDevice(devId, newName)
    return false
}

UnpairHostPairedDevice(devId) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.UnpairDevice(devId)
    return false
}

_HB_SerializePairedDevice(dev) {
    customFlag := (dev.HasOwnProp("customName") && dev.customName) ? "1" : "0"
    return "v1|" UriEncodeComponent(dev.deviceName) "|" UriEncodeComponent(dev.platform) "|" UriEncodeComponent(dev.token) "|" UriEncodeComponent(dev.pairedAt) "|" UriEncodeComponent(dev.ip) "|" UriEncodeComponent(dev.transport) "|" customFlag
}

_HB_ParsePairedDevice(devId, rawVal) {
    parts := StrSplit(String(rawVal), "|")
    if (parts.Length < 7 || parts[1] != "v1")
        return ""
    tok := UriDecodeComponent(parts[4])
    if (tok = "" || devId = "")
        return ""
    return {
        deviceId: devId,
        deviceName: UriDecodeComponent(parts[2]),
        platform: UriDecodeComponent(parts[3]),
        token: tok,
        pairedAt: UriDecodeComponent(parts[5]),
        ip: UriDecodeComponent(parts[6]),
        transport: UriDecodeComponent(parts[7]),
        customName: (parts.Length >= 8 && parts[8] = "1"),
        lastSeenTick: 0,
        connected: false
    }
}

UriDecodeComponent(str) {
    str := String(str)
    if (str = "")
        return ""
    bytes := []
    len := StrLen(str)
    i := 1
    while (i <= len) {
        ch := SubStr(str, i, 1)
        if (ch = "%" && i + 2 <= len) {
            hx := SubStr(str, i + 1, 2)
            if (hx ~= "^[0-9A-Fa-f]{2}$") {
                bytes.Push(Integer("0x" hx))
                i += 3
                continue
            }
        }
        needed := StrPut(ch, "UTF-8")
        if (needed > 1) {
            cbuf := Buffer(needed, 0)
            StrPut(ch, cbuf, "UTF-8")
            Loop (needed - 1)
                bytes.Push(NumGet(cbuf, A_Index - 1, "UChar"))
        }
        i += 1
    }
    if (bytes.Length = 0)
        return ""
    outBuf := Buffer(bytes.Length + 1, 0)
    for idx, bv in bytes
        NumPut("UChar", bv, outBuf, idx - 1)
    return StrGet(outBuf, "UTF-8")
}

HostBridgeBroadcastMuteState(cfg, state) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastMuteState(cfg, state)
    return 0
}

HostBridgeBroadcastStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B") {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastStageNudge(cfg, state, message, sender, accentHex)
    return 0
}

HostBridgeBroadcastCloseRemote() {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastCloseRemote()
    return 0
}

GetHostBridgeStatusSummary() {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running) {
        return {
            running: true,
            tcpPort: g_HostCompanionBridge.boundTcpPort,
            udpPort: g_HostCompanionBridge.boundUdpPort,
            discoverPort: g_HostCompanionBridge.boundDiscoverPort,
            hostUuid: EnsureHostUuid(g_HostCompanionBridge.cfg),
            connectedCount: g_HostCompanionBridge.GetConnectedClientCount(),
            devices: g_HostCompanionBridge.GetDeviceList()
        }
    }
    return {
        running: false,
        tcpPort: 0,
        udpPort: 0,
        discoverPort: 0,
        hostUuid: "",
        connectedCount: 0,
        devices: []
    }
}

_FormatHostBridgeStatusLine(cfg) {
    st := GetHostBridgeStatusSummary()
    portNum := cfg.HasOwnProp("BridgePort") ? cfg.BridgePort : 4456
    if (st.running)
        return "Bridge Port: " st.tcpPort " (Listening)  |  Paired Devices: " st.devices.Length " (" st.connectedCount " live)"
    return "Bridge Port: " portNum " (Inactive)  |  Paired Devices: 0"
}

_FormatHostBridgeDeviceText() {
    st := GetHostBridgeStatusSummary()
    if (st.devices.Length = 0)
        return "No Smart Board or mobile remote clients paired yet.`r`nPair using QR code or enter the Session Code above."
    out := ""
    for idx, d in st.devices {
        statusTag := d.connected ? "Connected" : "Paired"
        out .= (idx > 1 ? "`r`n" : "") d.deviceName " (" d.platform " - " d.ip ") • " statusTag " via " d.transport
    }
    return out
}

UriEncodeComponent(str) {
    str := String(str)
    if (str = "")
        return ""
    needed := StrPut(str, "UTF-8")
    buf := Buffer(needed, 0)
    written := StrPut(str, buf, "UTF-8")
    out := ""
    Loop written - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x5F || b = 0x2E || b = 0x7E) {
            out .= Chr(b)
        } else {
            out .= "%" Format("{:02X}", b)
        }
    }
    return out
}

BuildHostPairingUri(cfg, candidateIps := "", bridgePortOverride := 0) {
    global g_HostCompanionBridge
    hosts := []
    seen := Map()
    PushHost(h) {
        clean := Trim(String(h))
        if (clean = "" || seen.Has(clean))
            return
        seen[clean] := true
        hosts.Push(clean)
    }

    if IsObject(candidateIps) {
        for ep in candidateIps
            PushHost(ep)
    } else if (Type(candidateIps) = "String" && candidateIps != "") {
        for part in StrSplit(candidateIps, ",")
            PushHost(part)
    }
    PushHost(A_ComputerName ".local")

    hostStr := ""
    limit := Min(hosts.Length, 4)
    Loop limit {
        hostStr .= (A_Index > 1 ? "," : "") hosts[A_Index]
    }

    obsPort := 4455
    bridgePort := 0
    try bridgePort := Integer(bridgePortOverride)
    if (bridgePort <= 0 && IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running && g_HostCompanionBridge.boundTcpPort > 0)
        bridgePort := Integer(g_HostCompanionBridge.boundTcpPort)
    if (bridgePort <= 0 && IsSet(AppState) && IsObject(AppState) && AppState.HasOwnProp("activeBridgePort") && AppState.activeBridgePort > 0)
        bridgePort := Integer(AppState.activeBridgePort)
    if (bridgePort <= 0)
        bridgePort := (IsObject(cfg) && cfg.HasOwnProp("BridgePort")) ? Integer(cfg.BridgePort) : 4456
    obsPw := (IsObject(cfg) && cfg.HasOwnProp("obsPassword")) ? cfg.obsPassword : ""
    sessCode := (IsObject(cfg) && cfg.HasOwnProp("SessionPairingCode")) ? cfg.SessionPairingCode : ""
    micName := (IsObject(cfg) && cfg.HasOwnProp("targetMicName")) ? cfg.targetMicName : "Mic/Aux"
    netMode := (IsObject(cfg) && cfg.HasOwnProp("RemoteNetworkMode") && cfg.RemoteNetworkMode = "Internet") ? "internet" : "lan"
    rc := (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode")) ? cfg.InternetPairingCode : ""
    uuid := EnsureHostUuid(cfg)
    preset := (IsObject(cfg) && cfg.HasOwnProp("HudColorPreset")) ? cfg.HudColorPreset : "Standard"
    cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
    cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"

    uri := "presentersync://connect?hosts=" UriEncodeComponent(hostStr)
        . "&port=" obsPort
        . "&bp=" bridgePort
        . "&code=" UriEncodeComponent(sessCode)
        . "&mic=" UriEncodeComponent(micName)
        . "&mode=" netMode
    if (uuid != "")
        uri .= "&uuid=" UriEncodeComponent(uuid)
    if (obsPw != "")
        uri .= "&pw=" UriEncodeComponent(obsPw)
    if (rc != "")
        uri .= "&rc=" UriEncodeComponent(rc)
    if (preset != "" && preset != "Standard")
        uri .= "&preset=" UriEncodeComponent(preset)
    if (cLive != "")
        uri .= "&clh=" UriEncodeComponent(cLive)
    if (cMuted != "")
        uri .= "&cmh=" UriEncodeComponent(cMuted)
    return uri
}

RefreshHostNetworkingAfterWake(cfg, state, reason := "wake") {
    global g_HostCompanionBridge
    bridgeRefreshed := false
    syncSent := 0
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running) {
        bridgeRefreshed := g_HostCompanionBridge.RefreshNetworkListeners(reason)
        syncSent := g_HostCompanionBridge.GetConnectedClientCount()
    }
    if (IsObject(cfg) && IsObject(state)) {
        state.lastWakeRefreshTick := A_TickCount
        state.lastWakeReason := reason
        if (IsSet(UpdateHostInternetRelay))
            try UpdateHostInternetRelay(cfg, state)
        if (cfg.HasOwnProp("EnableWS") && cfg.EnableWS && state.HasOwnProp("obsConnected") && !state.obsConnected
            && state.HasOwnProp("obsTimerFn") && state.obsTimerFn != "") {
            try SetTimer(state.obsTimerFn, -200)
        }
        if (IsSet(HostBridgeBroadcastMuteState))
            try HostBridgeBroadcastMuteState(cfg, state)
    }
    return { refreshed: bridgeRefreshed, syncSent: syncSent, reason: reason }
}

HandleHostPowerEvent(cfg, state, wParam, lParam := 0) {
    wp := Integer(wParam)
    if (wp == 4) { ; PBT_APMSUSPEND
        if (IsObject(state))
            state.isSystemSuspending := true
        return "suspend"
    }
    if (wp == 7 || wp == 18) { ; PBT_APMRESUMESUSPEND / PBT_APMRESUMEAUTOMATIC
        if (IsObject(state))
            state.isSystemSuspending := false
        RefreshHostNetworkingAfterWake(cfg, state, wp == 18 ? "power_resume_auto" : "power_resume")
        return "resume"
    }
    return ""
}
