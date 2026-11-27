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
#Include "%A_LineFile%\..\JsonCodec.ahk"
#Include "%A_LineFile%\..\ConfigStore.ahk"
#Include WebRemoteUI.ahk
#Include WebRemoteArcade.ahk

class HostBridgeConstants {
    static PROTOCOL_VERSION := 2
    static DEFAULT_PORT := 4456
    static DEFAULT_DISCOVERY_PORT := 4457
    static DISCOVER_V1_PROTO := "PS_DISCOVER_V1"
    static MAX_BUFFER_BYTES := 65536
    static MAX_HTTP_HEADER_BYTES := 16384
    static MAX_HTTP_BODY_BYTES := 8192
    static MAX_HTTP_SEND_BYTES := 16777216
    static CMD_DEDUP_TTL_MS := 5000
    static CMD_DEDUP_MAX := 256
    static AUTH_TIMEOUT_MS := 3000
    static KEEP_ALIVE_MS := 20000
    ; v7.0.5 (#11): an authenticated WS client that has sent nothing (not even a
    ; pong to our 20s keep-alive ping) for 55s is a half-open zombie left behind
    ; by a sleeping Smart Board / dropped Wi-Fi. Reap it so the slot and the
    ; device's "connected" state are freed for the reconnecting socket.
    static DEAD_CLIENT_TIMEOUT_MS := 55000
    static MAX_CLIENTS := 64
    static PAIR_MAX_FAILS := 5
    static PAIR_LOCKOUT_MS := 30000
    static UDP_COOLDOWN_MS := 200
    static WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    static ROLES := ["Tally-Only", "Presenter", "Director"]
    static PRESENTER_SIGNALS := ["Ready to Start", "Switch to Board Cam", "Mic / Audio Issue", "Need Tech Help", "Advance Slide Please"]
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

IsUsableLanIPv4(ipStr) {
    s := Trim(String(ipStr))
    if (s = "" || !InStr(s, ".") || InStr(s, ":"))
        return false
    if (s = "0.0.0.0" || InStr(s, "127.") == 1 || InStr(s, "169.254.") == 1)
        return false
    return RegExMatch(s, "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") != 0
}

_HB_GetEndpointsSignature(endpoints) {
    if (!IsObject(endpoints) || !endpoints.HasOwnProp("ips"))
        return ""
    ipsCopy := []
    for _, ip in endpoints.ips {
        s := Trim(String(ip))
        if (IsUsableLanIPv4(s))
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

_HB_GetObsWsPort(cfg) {
    return (IsObject(cfg) && cfg.HasOwnProp("ObsWsPort") && Integer(cfg.ObsWsPort) > 0) ? Integer(cfg.ObsWsPort) : 4455
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
    return JsonCodec.Escape(str)
}

_HB_JsonExtractStr(jsonStr, key) {
    return JsonCodec.GetStr(jsonStr, key, "")
}

_HB_JsonExtractBool(jsonStr, key, defaultVal := false) {
    return JsonCodec.GetBool(jsonStr, key, defaultVal)
}

_HB_JsonExtractInt(jsonStr, key, defaultVal := 0) {
    return JsonCodec.GetInt(jsonStr, key, defaultVal)
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
    hostBootId := ""
    stateSeq := 1
    recentCmdIds := Map()

    _GenerateBootId() {
        rnd := Buffer(6, 0)
        ok := false
        try {
            if (DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", rnd.Ptr, "UInt", 6, "UInt", 2, "Int") == 0)
                ok := true
        } catch {
            ok := false
        }
        if (!ok) {
            Loop 6
                NumPut("UChar", Random(0, 255), rnd, A_Index - 1)
        }
        hex := ""
        Loop 6
            hex .= Format("{:02x}", NumGet(rnd, A_Index - 1, "UChar"))
        return hex
    }

    _EnsureBootId() {
        if (this.hostBootId = "")
            this.hostBootId := this._GenerateBootId()
        return this.hostBootId
    }

    Start(cfg, state, tcpPort := 4456, udpPort := -1, discoverPort := -1) {
        this.Stop()
        this.cfg := cfg
        this.state := state
        this.requestedTcpPort := tcpPort
        this.requestedUdpPort := (udpPort = -1) ? tcpPort : udpPort
        this.requestedDiscoverPort := (discoverPort = -1) ? ((tcpPort = HostBridgeConstants.DEFAULT_PORT) ? HostBridgeConstants.DEFAULT_DISCOVERY_PORT : 0) : discoverPort
        this.lastError := ""
        this.hostBootId := this._GenerateBootId()
        this.stateSeq := 1
        this.recentCmdIds := Map()

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
        prevDisc := (this.requestedDiscoverPort > 0) ? this.requestedDiscoverPort : this.boundDiscoverPort

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
        entries := Map()
        for devId, d in this.pairedDevices {
            iniKey := UriEncodeComponent(devId)
            if (iniKey = "")
                continue
            entries[iniKey] := _HB_SerializePairedDevice(d)
        }
        return ConfigStore.AtomicReplaceIniSection(iniPath, "HostBridgePairedDevices", entries)
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

    DisconnectDevice(devId, removePairing := false) {
        if (devId = "")
            return false
        devName := devId
        plat := "Remote"
        if (this.pairedDevices.Has(devId)) {
            dev := this.pairedDevices[devId]
            if (dev.HasOwnProp("deviceName") && dev.deviceName != "")
                devName := dev.deviceName
            if (dev.HasOwnProp("platform") && dev.platform != "")
                plat := dev.platform
            dev.connected := false
            if (removePairing) {
                if (dev.HasOwnProp("token") && dev.token != "" && this.validTokens.Has(dev.token))
                    this.validTokens.Delete(dev.token)
                this.pairedDevices.Delete(devId)
            }
        }
        if (removePairing) {
            staleTokens := []
            for tok, ownerId in this.validTokens {
                if (ownerId = devId)
                    staleTokens.Push(tok)
            }
            for tok in staleTokens
                this.validTokens.Delete(tok)
        }

        targets := []
        for _, cli in this.clients {
            if (cli.deviceId = devId)
                targets.Push(cli)
        }
        for cli in targets {
            if (cli.kind = "ws") {
                this._QueueWsFrame(cli, 0x1, '{"type":"disconnected","protocolVersion":2,"ok":true}')
                cli.closeAfterSend := true
                this._FlushSendQueue(cli)
            } else {
                this._CloseClient(cli)
            }
        }
        if (IsSet(SessionTimeline))
            SessionTimeline.Record("Remote", "Remote Disconnected: " devName, this.state, plat)
        if (removePairing)
            this.SavePairedDevices()
        return true
    }

    UnpairDevice(devId, initiatedByClient := false) {
        if (devId = "" || !this.pairedDevices.Has(devId))
            return false
        dev := this.pairedDevices[devId]
        devName := (dev.HasOwnProp("deviceName") && dev.deviceName != "") ? dev.deviceName : devId
        plat := (dev.HasOwnProp("platform") && dev.platform != "") ? dev.platform : "Remote"
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
                if (initiatedByClient)
                    this._QueueWsFrame(cli, 0x1, '{"type":"disconnected","protocolVersion":2,"unpaired":true,"ok":true}')
                else
                    this._QueueWsFrame(cli, 0x1, '{"type":"auth_error","error":"Device unpaired by host"}')
                cli.closeAfterSend := true
                this._FlushSendQueue(cli)
            } else {
                this._CloseClient(cli)
            }
        }
        if (IsSet(SessionTimeline))
            SessionTimeline.Record("Remote", "Remote Unpaired: " devName, this.state, plat)
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

    static NormalizeRole(role) {
        r := StrLower(Trim(String(role)))
        if (r = "tally-only" || r = "tally" || r = "tally_only")
            return "Tally-Only"
        if (r = "director")
            return "Director"
        return "Presenter"
    }

    static NormalizeTrustTier(tier) {
        t := StrLower(Trim(String(tier)))
        if (t = "pinned room" || t = "pinned" || t = "pinned_room")
            return "Pinned Room"
        return "Ephemeral Guest"
    }

    static GetPermissionsForRole(role) {
        norm := HostCompanionBridge.NormalizeRole(role)
        if (norm = "Tally-Only")
            return ["read_state", "ping", "sync_req"]
        if (norm = "Director")
            return ["read_state", "ping", "sync_req", "mute", "ppt", "timer", "stage_nudge", "record", "scene", "standby", "direct_obs"]
        return ["read_state", "ping", "sync_req", "mute", "ppt", "timer", "stage_nudge", "scene"]
    }

    static CheckVersionSkew(clientVer, clientProto := 2) {
        if (Integer(clientProto) != HostBridgeConstants.PROTOCOL_VERSION)
            return { skewed: true, reason: "Protocol mismatch (client v" clientProto " vs host v" HostBridgeConstants.PROTOCOL_VERSION ")" }
        cParts := StrSplit(LTrim(Trim(String(clientVer)), "vV"), ".")
        hParts := StrSplit(LTrim(Trim(String(UIConstants.APP_VERSION)), "vV"), ".")
        if (cParts.Length >= 2 && hParts.Length >= 2 && (cParts[1] != hParts[1] || cParts[2] != hParts[2]))
            return { skewed: true, reason: "App version skew (client " clientVer " vs host " UIConstants.APP_VERSION ")" }
        return { skewed: false, reason: "" }
    }

    static HasPermissionForCmd(role, msgType) {
        norm := HostCompanionBridge.NormalizeRole(role)
        if (norm = "Director")
            return true
        cmd := StrLower(Trim(String(msgType)))
        if (cmd = "ping" || cmd = "sync_req" || cmd = "disconnect" || cmd = "unpair" || cmd = "reconcile_fallback_state" || cmd = "nudge_ack")
            return true
        if (norm = "Tally-Only")
            return false
        ; Presenter allows mute, ppt, timer, stage_nudge, and live scene control (#1/#3) — blocks record, standby, panic, handoff, session_reset
        return (cmd = "toggle_mute" || cmd = "set_mute"
            || cmd = "ppt_next" || cmd = "ppt_prev" || cmd = "slide_start"
            || cmd = "timer_start" || cmd = "timer_pause" || cmd = "timer_reset"
            || cmd = "stage_nudge" || cmd = "add_bookmark"
            || cmd = "switch_scene" || cmd = "transition_scene" || cmd = "reset_active_scene")
    }

    _SyncClientPolicyFromDevice(devId) {
        if (!this.pairedDevices.Has(devId))
            return
        d := this.pairedDevices[devId]
        for _, cli in this.clients {
            if (cli.deviceId = devId) {
                cli.role := d.HasOwnProp("role") ? HostCompanionBridge.NormalizeRole(d.role) : "Presenter"
                cli.trustTier := d.HasOwnProp("trustTier") ? HostCompanionBridge.NormalizeTrustTier(d.trustTier) : "Ephemeral Guest"
                cli.allowDirectObsFallback := d.HasOwnProp("allowDirectObsFallback") ? !!d.allowDirectObsFallback : false
                cli.inputPaused := d.HasOwnProp("paused") ? !!d.paused : false
                cli.expiresAt := d.HasOwnProp("expiresAt") ? Integer(d.expiresAt) : 0
            }
        }
    }

    _PushPolicyUpdateToDevice(devId, sendRoleSync := false) {
        if (!this.running || devId = "")
            return 0
        useCfg := this.cfg
        wsEnabled := IsObject(useCfg) && useCfg.HasOwnProp("EnableWS") && !!useCfg.EnableWS
        micName := (IsObject(useCfg) && useCfg.HasOwnProp("targetMicName") && Trim(String(useCfg.targetMicName)) != "")
            ? Trim(String(useCfg.targetMicName))
            : "Mic/Aux"
        obsPass := (IsObject(useCfg) && useCfg.HasOwnProp("obsPassword")) ? String(useCfg.obsPassword) : ""
        obsPort := _HB_GetObsWsPort(useCfg)
        sent := 0
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated && cli.deviceId = devId) {
                cliRole := (cli.HasOwnProp("role") && cli.role != "") ? HostCompanionBridge.NormalizeRole(cli.role) : "Presenter"
                allowFb := wsEnabled && ((cliRole = "Director") || (cli.HasOwnProp("allowDirectObsFallback") && !!cli.allowDirectObsFallback))
                cliPass := allowFb ? obsPass : ""
                payload := '{"type":"obs_fallback_update","protocolVersion":' HostBridgeConstants.PROTOCOL_VERSION ',"allowDirectObsFallback":' (allowFb ? "true" : "false") ',"obsFallback":{"port":' obsPort ',"targetMic":"' _HB_JsonEscape(micName) '","password":"' _HB_JsonEscape(cliPass) '","directObsAllowed":' (allowFb ? "true" : "false") '}}'
                this._QueueWsFrame(cli, 0x1, payload)
                if (sendRoleSync) {
                    this.stateSeq += 1
                    this._QueueWsFrame(cli, 0x1, this._BuildSyncResyncJson("role_change", cliRole))
                }
                sent += 1
            }
        }
        return sent
    }

    SetDeviceRole(devId, role) {
        if (!this.pairedDevices.Has(devId))
            return false
        this.pairedDevices[devId].role := HostCompanionBridge.NormalizeRole(role)
        this._SyncClientPolicyFromDevice(devId)
        this.SavePairedDevices()
        this._PushPolicyUpdateToDevice(devId, true)
        return true
    }

    SetDeviceTrustTier(devId, trustTier) {
        if (!this.pairedDevices.Has(devId))
            return false
        this.pairedDevices[devId].trustTier := HostCompanionBridge.NormalizeTrustTier(trustTier)
        this._SyncClientPolicyFromDevice(devId)
        this.SavePairedDevices()
        return true
    }

    SetDeviceDirectObsFallback(devId, allow) {
        if (!this.pairedDevices.Has(devId))
            return false
        this.pairedDevices[devId].allowDirectObsFallback := !!allow
        this._SyncClientPolicyFromDevice(devId)
        this.SavePairedDevices()
        this._PushPolicyUpdateToDevice(devId, false)
        return true
    }

    SetDevicePaused(devId, paused) {
        if (!this.pairedDevices.Has(devId))
            return false
        this.pairedDevices[devId].paused := !!paused
        this._SyncClientPolicyFromDevice(devId)
        this.SavePairedDevices()
        return true
    }

    SetDeviceTtlHours(devId, ttlHours := 0) {
        if (!this.pairedDevices.Has(devId))
            return false
        hrs := Float(ttlHours)
        exp := (hrs > 0) ? (GetCurrentUnixEpoch() + Round(hrs * 3600)) : 0
        this.pairedDevices[devId].expiresAt := exp
        this._SyncClientPolicyFromDevice(devId)
        this.SavePairedDevices()
        return true
    }

    RevokeEphemeralGuests() {
        toRemove := []
        for devId, d in this.pairedDevices {
            tier := d.HasOwnProp("trustTier") ? HostCompanionBridge.NormalizeTrustTier(d.trustTier) : "Ephemeral Guest"
            if (tier != "Pinned Room")
                toRemove.Push(devId)
        }
        for _, devId in toRemove
            this.DisconnectDevice(devId, true)
        return toRemove.Length
    }

    FlashDevicePill(devId, durationMs := 1800) {
        if (devId = "")
            return 0
        sent := 0
        dur := Max(300, Integer(durationMs))
        payload := '{"type":"flash_pill","durationMs":' dur ',"timestamp":' A_TickCount '}'
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated && cli.deviceId = devId) {
                this._QueueWsFrame(cli, 0x1, payload)
                sent += 1
            }
        }
        return sent
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
                customName: d.HasOwnProp("customName") ? d.customName : false,
                role: d.HasOwnProp("role") ? HostCompanionBridge.NormalizeRole(d.role) : "Presenter",
                trustTier: d.HasOwnProp("trustTier") ? HostCompanionBridge.NormalizeTrustTier(d.trustTier) : "Ephemeral Guest",
                allowDirectObsFallback: d.HasOwnProp("allowDirectObsFallback") ? !!d.allowDirectObsFallback : false,
                paused: d.HasOwnProp("paused") ? !!d.paused : false,
                expiresAt: d.HasOwnProp("expiresAt") ? Integer(d.expiresAt) : 0
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
        this.stateSeq += 1
        return this._BroadcastJsonToAuthenticated(this._BuildMuteStateJson())
    }

    BroadcastSyncResync(cfg, state, reason := "wake") {
        if (!this.running)
            return 0
        this.stateSeq += 1
        return this._BroadcastJsonToAuthenticated(this._BuildSyncResyncJson(reason))
    }

    BroadcastObsFallbackUpdate(cfg := "") {
        if (!this.running)
            return 0
        useCfg := IsObject(cfg) ? cfg : this.cfg
        wsEnabled := IsObject(useCfg) && useCfg.HasOwnProp("EnableWS") && !!useCfg.EnableWS
        micName := (IsObject(useCfg) && useCfg.HasOwnProp("targetMicName") && Trim(String(useCfg.targetMicName)) != "")
            ? Trim(String(useCfg.targetMicName))
            : "Mic/Aux"
        obsPass := (IsObject(useCfg) && useCfg.HasOwnProp("obsPassword")) ? String(useCfg.obsPassword) : ""
        obsPort := _HB_GetObsWsPort(useCfg)
        sent := 0
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated) {
                cliRole := (cli.HasOwnProp("role") && cli.role != "") ? HostCompanionBridge.NormalizeRole(cli.role) : "Presenter"
                allowFb := wsEnabled && ((cliRole = "Director") || (cli.HasOwnProp("allowDirectObsFallback") && !!cli.allowDirectObsFallback))
                cliPass := allowFb ? obsPass : ""
                payload := '{"type":"obs_fallback_update","protocolVersion":' HostBridgeConstants.PROTOCOL_VERSION ',"allowDirectObsFallback":' (allowFb ? "true" : "false") ',"obsFallback":{"port":' obsPort ',"targetMic":"' _HB_JsonEscape(micName) '","password":"' _HB_JsonEscape(cliPass) '","directObsAllowed":' (allowFb ? "true" : "false") '}}'
                this._QueueWsFrame(cli, 0x1, payload)
                sent += 1
            }
        }
        return sent
    }

    BroadcastStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B", opts := "") {
        if (!this.HasOwnProp("nudgeStatusMap") || !IsObject(this.nudgeStatusMap))
            this.nudgeStatusMap := Map()
        nudgeId := (IsObject(opts) && opts.HasOwnProp("nudgeId") && opts.nudgeId != "") ? String(opts.nudgeId) : ("ndg-" A_TickCount "-" Random(1000, 9999))
        targetDev := (IsObject(opts) && opts.HasOwnProp("targetDeviceId") && opts.targetDeviceId != "") ? String(opts.targetDeviceId) : "All"
        originDev := (IsObject(opts) && opts.HasOwnProp("originDeviceId")) ? String(opts.originDeviceId) : ""
        urgency := (IsObject(opts) && opts.HasOwnProp("urgency") && opts.urgency != "") ? StrLower(String(opts.urgency)) : "whisper"
        reqAck := (IsObject(opts) && opts.HasOwnProp("requiresAck")) ? !!opts.requiresAck : (urgency != "whisper")
        dir := (IsObject(opts) && opts.HasOwnProp("direction") && opts.direction != "") ? String(opts.direction) : "stage_out"

        payload := '{"type":"stage_nudge","nudgeId":"' _HB_JsonEscape(nudgeId) '","message":"' _HB_JsonEscape(message) '","sender":"' _HB_JsonEscape(sender) '","accentHex":"' _HB_JsonEscape(accentHex) '","targetDeviceId":"' _HB_JsonEscape(targetDev) '","urgency":"' _HB_JsonEscape(urgency) '","requiresAck":' (reqAck ? "true" : "false") ',"direction":"' _HB_JsonEscape(dir) '","timestamp":' A_TickCount '}'
        sent := 0
        if (this.running) {
            for _, cli in this.clients {
                if (cli.kind != "ws" || !cli.authenticated)
                    continue
                if (originDev != "" && cli.deviceId = originDev)
                    continue
                if (targetDev != "" && targetDev != "All" && cli.deviceId != targetDev)
                    continue
                this._QueueWsFrame(cli, 0x1, payload)
                sent += 1
            }
        }
        if (this.nudgeStatusMap.Count >= 64) {
            for oldKey in this.nudgeStatusMap {
                this.nudgeStatusMap.Delete(oldKey)
                break
            }
        }
        this.nudgeStatusMap[nudgeId] := {
            nudgeId: nudgeId,
            message: message,
            sender: sender,
            targetDeviceId: targetDev,
            urgency: urgency,
            requiresAck: reqAck,
            status: (sent > 0 ? "Delivered" : "Sent"),
            ackedBy: [],
            tick: A_TickCount
        }
        return sent
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

    PruneRateLimits(nowTick := "") {
        now := (nowTick != "" && IsInteger(nowTick)) ? Integer(nowTick) : A_TickCount
        staleKeys := []
        for ip, rl in this.rateLimits {
            lastAct := rl.HasOwnProp("lastActivityTick") ? rl.lastActivityTick : Max(rl.lastUdpTick, rl.lastV1Tick)
            if (rl.lockUntil <= now && (lastAct == 0 ? (rl.fails == 0) : ((now - lastAct) > 120000)))
                staleKeys.Push(ip)
        }
        for _, k in staleKeys
            this.rateLimits.Delete(k)
        if (this.rateLimits.Count > 256) {
            for ip in this.rateLimits {
                staleKeys := ip
                this.rateLimits.Delete(ip)
                if (this.rateLimits.Count <= 256)
                    break
            }
        }
    }

    _GetRateLimit(ip) {
        if (!this.rateLimits.Has(ip)) {
            if (this.rateLimits.Count >= 256)
                this.PruneRateLimits()
            this.rateLimits[ip] := { fails: 0, lockUntil: 0, lastUdpTick: 0, lastV1Tick: 0, lastActivityTick: A_TickCount }
        } else {
            this.rateLimits[ip].lastActivityTick := A_TickCount
        }
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
        this.PruneRateLimits(now)
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
        devRole := (IsObject(c) && c.HasOwnProp("role") && c.role != "") ? HostCompanionBridge.NormalizeRole(c.role) : "Presenter"
        devTier := (IsObject(c) && c.HasOwnProp("trustTier") && c.trustTier != "") ? HostCompanionBridge.NormalizeTrustTier(c.trustTier) : "Ephemeral Guest"
        wsAllowed := (IsObject(this.cfg) && (!this.cfg.HasOwnProp("EnableWS") || this.cfg.EnableWS))
        allowObsFb := wsAllowed && ((devRole = "Director") || (IsObject(c) && c.HasOwnProp("allowDirectObsFallback") && !!c.allowDirectObsFallback))
        obsField := ""
        if (IsObject(this.cfg) && this.cfg.HasOwnProp("EnableWS") && this.cfg.EnableWS) {
            micName := (this.cfg.HasOwnProp("targetMicName") && Trim(String(this.cfg.targetMicName)) != "")
                ? Trim(String(this.cfg.targetMicName))
                : "Mic/Aux"
            obsPass := (allowObsFb && this.cfg.HasOwnProp("obsPassword")) ? String(this.cfg.obsPassword) : ""
            obsPort := _HB_GetObsWsPort(this.cfg)
            obsField := ',"obsFallback":{"port":' obsPort ',"targetMic":"' _HB_JsonEscape(micName) '","password":"' _HB_JsonEscape(obsPass) '","directObsAllowed":' (allowObsFb ? "true" : "false") '}'
        }
        perms := HostCompanionBridge.GetPermissionsForRole(devRole)
        permJson := "["
        for idx, p in perms
            permJson .= (idx > 1 ? "," : "") '"' _HB_JsonEscape(p) '"'
        permJson .= "]"
        ver := _HB_JsonEscape(UIConstants.APP_VERSION)
        bootId := _HB_JsonEscape(this._EnsureBootId())
        skewWarn := (IsObject(c) && c.HasOwnProp("versionSkewWarning") && c.versionSkewWarning != "")
            ? ',"versionSkewWarning":"' _HB_JsonEscape(c.versionSkewWarning) '"'
            : ""
        caps := '["protocol_v2","cmd_dedup","set_state","ack_nack","stage_nudge","director_deck","rbac_v1"]'
        return '{"type":"auth_ok","protocolVersion":' HostBridgeConstants.PROTOCOL_VERSION ',"appVersion":"' ver '","hostBootId":"' bootId '","stateSeq":' this.stateSeq ',"role":"' _HB_JsonEscape(devRole) '","trustTier":"' _HB_JsonEscape(devTier) '","allowDirectObsFallback":' (allowObsFb ? "true" : "false") ',"permissions":' permJson ',"capabilities":' caps ',"hostUuid":"' _HB_JsonEscape(EnsureHostUuid(this.cfg)) '","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' ver '"' skewWarn tokField obsField '}'
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
                reply := BuildPublicDiscoveryBeaconJson(this.cfg, this.boundTcpPort, _HB_GetObsWsPort(this.cfg))
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
                    reply := "PSYNC_OFFER|" A_ComputerName "|" this.boundTcpPort "|" _HB_GetObsWsPort(this.cfg) "|" UIConstants.APP_VERSION "|" mode
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
                    if (clientSock = -1 || clientSock = 0xFFFFFFFFFFFFFFFF)
                        break
                    if (this.clients.Count >= HostBridgeConstants.MAX_CLIENTS) {
                        try DllCall("ws2_32\closesocket", "Ptr", clientSock)
                        continue
                    }
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
                        fragLen: 0,
                        fragOpcode: 0,
                        protocolVersion: 1,
                        appVersion: "",
                        capabilities: [],
                        inputPaused: false
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
                    if (c.kind = "ws")
                        this._SendWsCloseAndDisconnect(c, 1009, "Message too big")
                    else
                        this._SendHttpResponse(c, "413 Payload Too Large", '{"ok":false,"error":"Payload too large"}')
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

    _QueueRawBytes(c, srcPtr, byteLen, maxQueueBytes := 0) {
        if (byteLen <= 0)
            return
        limit := (maxQueueBytes > 0) ? maxQueueBytes : (HostBridgeConstants.MAX_BUFFER_BYTES * 2)
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
            res := _HB_AppendBytes(c.sendBuf, c.sendLen, srcPtr + offset, rem, limit)
            if (!IsObject(res)) {
                this._CloseClient(c)
                return
            }
            c.sendBuf := res.buf
            c.sendLen := res.len
            return
        }

        res := _HB_AppendBytes(c.sendBuf, c.sendLen, srcPtr, byteLen, limit)
        if (!IsObject(res)) {
            this._CloseClient(c)
            return
        }
        c.sendBuf := res.buf
        c.sendLen := res.len
        this._FlushSendQueue(c)
    }

    _QueueText(c, str, maxQueueBytes := 0) {
        bLen := 0
        bBuf := _HB_StrToUtf8Buf(str, &bLen)
        if (bLen > 0)
            this._QueueRawBytes(c, bBuf.Ptr, bLen, maxQueueBytes)
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

    _SendWsCloseAndDisconnect(c, closeCode := 1000, reason := "") {
        rLen := 0
        rBuf := (reason != "") ? _HB_StrToUtf8Buf(SubStr(String(reason), 1, 100), &rLen) : Buffer(0)
        pLen := 2 + rLen
        frame := Buffer(2 + pLen, 0)
        NumPut("UChar", 0x88, frame, 0)
        NumPut("UChar", pLen, frame, 1)
        NumPut("UChar", (closeCode >> 8) & 0xFF, frame, 2)
        NumPut("UChar", closeCode & 0xFF, frame, 3)
        if (rLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", frame.Ptr + 4, "Ptr", rBuf.Ptr, "UPtr", rLen)
        c.closeAfterSend := true
        this._QueueRawBytes(c, frame.Ptr, 2 + pLen)
        if (this.clients.Has(c.key))
            this._FlushSendQueue(c)
    }

    _IsAllowedWsOrigin(hdrText) {
        if (!RegExMatch(hdrText, "im)^Origin:\s*([^\r\n]+)", &mOrig))
            return true
        originRaw := Trim(mOrig[1])
        if (originRaw = "" || StrLower(originRaw) = "null")
            return false
        if (!RegExMatch(originRaw, "i)^https?://([^/]+)", &mOrigHost))
            return false
        origHostPort := StrLower(Trim(mOrigHost[1]))

        expectedHost := RegExMatch(hdrText, "im)^Host:\s*([^\r\n]+)", &mHost)
            ? StrLower(Trim(mHost[1]))
            : ("127.0.0.1:" this.boundTcpPort)
        if (origHostPort == expectedHost)
            return true
        origNorm := RegExReplace(origHostPort, "^localhost(?=:|$)", "127.0.0.1")
        expNorm := RegExReplace(expectedHost, "^localhost(?=:|$)", "127.0.0.1")
        return (origNorm == expNorm)
    }

    _CheckAndGetCachedCmdAck(c, cmdId) {
        cleanId := Trim(String(cmdId))
        if (cleanId = "")
            return ""
        now := A_TickCount
        this._PruneRecentCmdIds(now)
        cacheKey := (c.deviceId != "" ? c.deviceId : c.key) ":" cleanId
        if (this.recentCmdIds.Has(cacheKey)) {
            entry := this.recentCmdIds[cacheKey]
            if ((now - entry.tick) <= HostBridgeConstants.CMD_DEDUP_TTL_MS)
                return entry.replyJson
            this.recentCmdIds.Delete(cacheKey)
        }
        return ""
    }

    _StoreCmdDedupReply(c, cmdId, replyJson) {
        cleanId := Trim(String(cmdId))
        if (cleanId = "")
            return
        now := A_TickCount
        this._PruneRecentCmdIds(now)
        cacheKey := (c.deviceId != "" ? c.deviceId : c.key) ":" cleanId
        this.recentCmdIds[cacheKey] := { tick: now, replyJson: replyJson }
    }

    _PruneRecentCmdIds(now := "") {
        t := (now = "") ? A_TickCount : now
        stale := []
        for k, entry in this.recentCmdIds {
            if ((t - entry.tick) > HostBridgeConstants.CMD_DEDUP_TTL_MS)
                stale.Push(k)
        }
        for k in stale
            this.recentCmdIds.Delete(k)
        while (this.recentCmdIds.Count > HostBridgeConstants.CMD_DEDUP_MAX) {
            oldestKey := ""
            oldestTick := t + 1
            for k, entry in this.recentCmdIds {
                if (entry.tick <= oldestTick) {
                    oldestTick := entry.tick
                    oldestKey := k
                }
            }
            if (oldestKey = "")
                break
            this.recentCmdIds.Delete(oldestKey)
        }
    }

    _QueueCmdResult(c, action, ok, cmdId := "", code := "", reason := "") {
        cmdField := (cmdId != "") ? (',"cmdId":"' _HB_JsonEscape(cmdId) '"') : ""
        if (ok) {
            reply := '{"type":"ack","protocolVersion":2,"action":"' _HB_JsonEscape(action) '","ok":true,"stateSeq":' this.stateSeq cmdField '}'
            if (cmdId != "") {
                dedupReply := '{"type":"ack","protocolVersion":2,"action":"' _HB_JsonEscape(action) '","ok":true,"dedup":true,"stateSeq":' this.stateSeq cmdField '}'
                this._StoreCmdDedupReply(c, cmdId, dedupReply)
            }
            this._QueueWsFrame(c, 0x1, reply)
        } else {
            errCode := (code != "") ? code : "command_failed"
            errReason := (reason != "") ? reason : errCode
            nack := '{"type":"nack","protocolVersion":2,"action":"' _HB_JsonEscape(action) '","ok":false,"code":"' _HB_JsonEscape(errCode) '","reason":"' _HB_JsonEscape(errReason) '","stateSeq":' this.stateSeq cmdField '}'
            this._QueueWsFrame(c, 0x1, nack)
        }
    }

    _QueueWsFrame(c, opcode, payloadStr) {
        pLen := 0
        pBuf := _HB_StrToUtf8Buf(payloadStr, &pLen)
        hdrLen := (pLen <= 125) ? 2 : ((pLen <= 65535) ? 4 : 10)
        frame := Buffer(hdrLen + pLen, 0)
        NumPut("UChar", 0x80 | (opcode & 0x0F), frame, 0)
        if (pLen <= 125) {
            NumPut("UChar", pLen, frame, 1)
        } else if (pLen <= 65535) {
            NumPut("UChar", 126, frame, 1)
            NumPut("UChar", (pLen >> 8) & 0xFF, frame, 2)
            NumPut("UChar", pLen & 0xFF, frame, 3)
        } else {
            NumPut("UChar", 127, frame, 1)
            NumPut("UChar", (pLen >> 24) & 0xFF, frame, 6)
            NumPut("UChar", (pLen >> 16) & 0xFF, frame, 7)
            NumPut("UChar", (pLen >> 8) & 0xFF, frame, 8)
            NumPut("UChar", pLen & 0xFF, frame, 9)
        }
        if (pLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", frame.Ptr + hdrLen, "Ptr", pBuf.Ptr, "UPtr", pLen)
        this._QueueRawBytes(c, frame.Ptr, hdrLen + pLen)
    }

    _ResolveLanUpdateArtifact(fileName) {
        if (IsObject(this.cfg) && this.cfg.HasOwnProp("LanUpdateDir") && this.cfg.LanUpdateDir != "") {
            candCfg := RTrim(String(this.cfg.LanUpdateDir), "\/") "\" fileName
            if (FileExist(candCfg))
                return candCfg
        }
        for _, cand in [A_ScriptDir "\" fileName, A_ScriptDir "\dist\" fileName] {
            if (FileExist(cand))
                return cand
        }
        return ""
    }

    _SendHttpResponse(c, statusLine, jsonBody, extraHeaders := "", contentType := "application/json; charset=utf-8") {
        bLen := 0
        _HB_StrToUtf8Buf(jsonBody, &bLen)
        hdr := "HTTP/1.1 " statusLine "`r`n"
            . "Content-Type: " contentType "`r`n"
            . "X-Content-Type-Options: nosniff`r`n"
            . "Content-Length: " bLen "`r`n"
            . "Connection: close`r`n"
            . extraHeaders
            . "`r`n"
        c.closeAfterSend := true
        this._QueueText(c, hdr . jsonBody, HostBridgeConstants.MAX_HTTP_SEND_BYTES)
    }

    _SendHtmlResponse(c, statusLine, htmlBody, extraHeaders := "") {
        bLen := 0
        _HB_StrToUtf8Buf(htmlBody, &bLen)
        hdr := "HTTP/1.1 " statusLine "`r`n"
            . "Content-Type: text/html; charset=utf-8`r`n"
            . "Cache-Control: no-store`r`n"
            . "X-Content-Type-Options: nosniff`r`n"
            . "X-Frame-Options: DENY`r`n"
            . "Content-Length: " bLen "`r`n"
            . "Connection: close`r`n"
            . extraHeaders
            . "`r`n"
        c.closeAfterSend := true
        this._QueueText(c, hdr . htmlBody, HostBridgeConstants.MAX_HTTP_SEND_BYTES)
    }

    _SendJsResponse(c, statusLine, jsBody, extraHeaders := "") {
        bLen := 0
        _HB_StrToUtf8Buf(jsBody, &bLen)
        hdr := "HTTP/1.1 " statusLine "`r`n"
            . "Content-Type: application/javascript; charset=utf-8`r`n"
            . "Cache-Control: no-store`r`n"
            . "X-Content-Type-Options: nosniff`r`n"
            . "Content-Length: " bLen "`r`n"
            . "Connection: close`r`n"
            . extraHeaders
            . "`r`n"
        c.closeAfterSend := true
        this._QueueText(c, hdr . jsBody, HostBridgeConstants.MAX_HTTP_SEND_BYTES)
    }

    _SendBinaryResponse(c, statusLine, contentType, dataBuf, byteLen, extraHeaders := "") {
        hdr := "HTTP/1.1 " statusLine "`r`n"
            . "Content-Type: " contentType "`r`n"
            . "Cache-Control: public, max-age=86400`r`n"
            . "X-Content-Type-Options: nosniff`r`n"
            . "Content-Length: " byteLen "`r`n"
            . "Connection: close`r`n"
            . extraHeaders
            . "`r`n"
        hdrLen := 0
        hdrBuf := _HB_StrToUtf8Buf(hdr, &hdrLen)
        totalLen := hdrLen + Max(0, Integer(byteLen))
        outBuf := Buffer(Max(1, totalLen), 0)
        if (hdrLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", outBuf.Ptr, "Ptr", hdrBuf.Ptr, "UPtr", hdrLen)
        if (byteLen > 0 && IsObject(dataBuf))
            DllCall("ntdll\RtlMoveMemory", "Ptr", outBuf.Ptr + hdrLen, "Ptr", dataBuf.Ptr, "UPtr", byteLen)
        c.closeAfterSend := true
        this._QueueRawBytes(c, outBuf.Ptr, totalLen, HostBridgeConstants.MAX_HTTP_SEND_BYTES)
    }

    _LoadFaviconBytes() {
        static cachedBuf := ""
        static attempted := false
        if (IsObject(cachedBuf) && cachedBuf.Size > 0)
            return cachedBuf
        if (attempted)
            return ""
        attempted := true

        for _, cand in [A_ScriptDir "\assets\PresenterSync.ico", A_LineFile "\..\..\assets\PresenterSync.ico"] {
            if (FileExist(cand)) {
                try {
                    buf := FileRead(cand, "RAW")
                    if (IsObject(buf) && buf.Size > 0) {
                        cachedBuf := buf
                        return cachedBuf
                    }
                }
            }
        }
        if (A_IsCompiled) {
            try {
                hRes := DllCall("FindResourceW", "Ptr", 0, "Str", "FAVICON_ICO", "Ptr", 10, "Ptr")
                if (hRes) {
                    sz := DllCall("SizeofResource", "Ptr", 0, "Ptr", hRes, "UInt")
                    hGlob := DllCall("LoadResource", "Ptr", 0, "Ptr", hRes, "Ptr")
                    pData := hGlob ? DllCall("LockResource", "Ptr", hGlob, "Ptr") : 0
                    if (pData && sz > 0) {
                        buf := Buffer(sz, 0)
                        DllCall("ntdll\RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", pData, "UPtr", sz)
                        cachedBuf := buf
                        return cachedBuf
                    }
                }
            }
        }
        return ""
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
                if (c.recvLen > HostBridgeConstants.MAX_HTTP_HEADER_BYTES)
                    this._SendHttpResponse(c, "413 Payload Too Large", '{"ok":false,"error":"Headers too large"}')
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
                body := '{"ok":true,"hostUuid":"' _HB_JsonEscape(uuid) '","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '","bridgePort":' this.boundTcpPort ',"obsPort":' _HB_GetObsWsPort(this.cfg) ',"routingMode":' mode '}'
                this._SendHttpResponse(c, "200 OK", body)
                return
            }

            if (method = "GET" && (cleanPath = "/ws" || RegExMatch(hdrText, "i)Upgrade:\s*websocket"))) {
                this._HandleWsUpgrade(c, hdrText, rawPath, hdrEnd)
                return
            }

            if (method = "GET" && (cleanPath = "/" || cleanPath = "/remote" || cleanPath = "/remote/")) {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                appVer := IsSet(UIConstants) ? UIConstants.APP_VERSION : ""
                htmlBody := BuildWebRemoteHtml(appVer, this.boundTcpPort)
                this._SendHtmlResponse(c, "200 OK", htmlBody)
                return
            }

            if (method = "GET" && cleanPath = "/favicon.ico") {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                favBuf := this._LoadFaviconBytes()
                if (IsObject(favBuf) && favBuf.Size > 0)
                    this._SendBinaryResponse(c, "200 OK", "image/x-icon", favBuf, favBuf.Size)
                else
                    this._SendBinaryResponse(c, "204 No Content", "image/x-icon", Buffer(0), 0)
                return
            }

            if (method = "GET" && cleanPath = "/manifest.json") {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                manJson := '{"name":"PresenterSync Web Remote","short_name":"PresenterSync","start_url":"/","display":"standalone","background_color":"#090b10","theme_color":"#0f172a"}'
                this._SendHttpResponse(c, "200 OK", manJson)
                return
            }
            if (method = "GET" && (cleanPath = "/update/sha256" || cleanPath = "/update/android")) {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                if (!IsObject(this.cfg) || !this.cfg.HasOwnProp("EnableLanSelfUpdate") || !this.cfg.EnableLanSelfUpdate) {
                    this._SendHttpResponse(c, "403 Forbidden", '{"ok":false,"error":"LAN self-update is disabled"}')
                    return
                }
                artName := (cleanPath = "/update/sha256") ? "SHA256SUMS.txt" : "PresenterSync_Remote.apk"
                targetFile := this._ResolveLanUpdateArtifact(artName)
                if (targetFile = "" || !FileExist(targetFile)) {
                    this._SendHttpResponse(c, "404 Not Found", '{"ok":false,"error":"Artifact not found on host"}')
                    return
                }
                try {
                    if (cleanPath = "/update/sha256") {
                        this._SendHttpResponse(c, "200 OK", FileRead(targetFile, "UTF-8"), "", "text/plain; charset=utf-8")
                    } else {
                        bin := FileRead(targetFile, "RAW")
                        this._SendBinaryResponse(c, "200 OK", "application/vnd.android.package-archive", bin, bin.Size)
                    }
                } catch as readErr {
                    this._SendHttpResponse(c, "500 Internal Server Error", '{"ok":false,"error":"' _HB_JsonEscape(readErr.Message) '"}')
                }
                return
            }
            if (method = "GET" && cleanPath = "/slide-preview.jpg") {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                authTok := ""
                if (RegExMatch(rawPath, "[?&]token=([^&#]+)", &mTok))
                    authTok := UriDecodeComponent(mTok[1])
                if (authTok = "" && RegExMatch(hdrText, "im)^Authorization:\s*Bearer\s+([^\r\n]+)", &mHdr))
                    authTok := Trim(mHdr[1])
                if (authTok = "" || !this.validTokens.Has(authTok)) {
                    this._SendHttpResponse(c, "401 Unauthorized", '{"ok":false,"error":"Valid paired token required"}')
                    return
                }
                if (this.HasOwnProp("cachedSlidePreviewBuf") && IsObject(this.cachedSlidePreviewBuf) && this.cachedSlidePreviewBuf.Size > 0)
                    this._SendBinaryResponse(c, "200 OK", "image/jpeg", this.cachedSlidePreviewBuf, this.cachedSlidePreviewBuf.Size)
                else
                    this._SendHttpResponse(c, "404 Not Found", '{"ok":false,"error":"No cached slide preview"}')
                return
            }
            if (method = "GET" && cleanPath = "/arcade.js") {
                c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
                jsBody := BuildWebRemoteArcadeJs()
                this._SendJsResponse(c, "200 OK", jsBody)
                return
            }

            if (method = "POST" && cleanPath = "/pair") {
                contentLen := 0
                if (RegExMatch(hdrText, "i)Content-Length:\s*(\d+)", &mLen))
                    contentLen := Integer(mLen[1])
                if (contentLen > HostBridgeConstants.MAX_HTTP_BODY_BYTES) {
                    c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
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

        reqObj := JsonCodec.Parse(bodyText)
        reqCode := NormalizePairingCode(IsObject(reqObj) ? JsonCodec.GetStr(reqObj, "code") : _HB_JsonExtractStr(bodyText, "code"))
        devId := IsObject(reqObj) ? JsonCodec.GetStr(reqObj, "deviceId") : _HB_JsonExtractStr(bodyText, "deviceId")
        if (devId = "")
            devId := "device-" c.ip "-" c.sock
        devName := IsObject(reqObj) ? JsonCodec.GetStr(reqObj, "deviceName") : _HB_JsonExtractStr(bodyText, "deviceName")
        if (devName = "")
            devName := "Smart Board"
        plat := IsObject(reqObj) ? JsonCodec.GetStr(reqObj, "platform") : _HB_JsonExtractStr(bodyText, "platform")
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
        prevRole := (this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("role")) ? HostCompanionBridge.NormalizeRole(this.pairedDevices[devId].role) : "Presenter"
        prevTrust := (this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("trustTier")) ? HostCompanionBridge.NormalizeTrustTier(this.pairedDevices[devId].trustTier) : "Ephemeral Guest"
        prevAllowFb := (this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("allowDirectObsFallback")) ? !!this.pairedDevices[devId].allowDirectObsFallback : false
        prevPaused := (this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("paused")) ? !!this.pairedDevices[devId].paused : false
        prevExp := (this.pairedDevices.Has(devId) && this.pairedDevices[devId].HasOwnProp("expiresAt")) ? Integer(this.pairedDevices[devId].expiresAt) : 0
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
            customName: hadCustom,
            role: prevRole,
            trustTier: prevTrust,
            allowDirectObsFallback: prevAllowFb,
            paused: prevPaused,
            expiresAt: prevExp
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
        wsAllowed := (IsObject(this.cfg) && (!this.cfg.HasOwnProp("EnableWS") || this.cfg.EnableWS))
        allowObsFb := wsAllowed && ((prevRole = "Director") || prevAllowFb)
        obsPw := (allowObsFb && this.cfg.HasOwnProp("obsPassword")) ? this.cfg.obsPassword : ""
        obsPortVal := _HB_GetObsWsPort(this.cfg)
        micName := this.cfg.HasOwnProp("targetMicName") ? this.cfg.targetMicName : "Mic/Aux"
        relayCode := this.cfg.HasOwnProp("InternetPairingCode") ? this.cfg.InternetPairingCode : ""

        hostUuid := EnsureHostUuid(this.cfg)
        resp := '{'
            . '"ok":true,'
            . '"hostUuid":"' _HB_JsonEscape(hostUuid) '",'
            . '"hostName":"' _HB_JsonEscape(A_ComputerName) '",'
            . '"version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '",'
            . '"bridgePort":' this.boundTcpPort ','
            . '"obsPort":' obsPortVal ','
            . '"role":"' _HB_JsonEscape(prevRole) '",'
            . '"trustTier":"' _HB_JsonEscape(prevTrust) '",'
            . '"allowDirectObsFallback":' (allowObsFb ? "true" : "false") ','
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
        if (!this._IsAllowedWsOrigin(hdrText)) {
            c.recvLen := _HB_ConsumeBytes(c.recvBuf, c.recvLen, hdrEnd)
            this._SendHttpResponse(c, "403 Forbidden", '{"ok":false,"error":"Cross-origin WebSocket rejected"}')
            return
        }
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
            if (!this._FinalizeWsClientAuth(c, "", qParams))
                return
        }

        if (c.recvLen > 0)
            this._DrainWsFrames(c)
    }

    _FinalizeWsClientAuth(c, msgObj := "", qParams := "") {
        if (c.deviceId != "" && this.pairedDevices.Has(c.deviceId)) {
            d := this.pairedDevices[c.deviceId]
            c.role := d.HasOwnProp("role") ? HostCompanionBridge.NormalizeRole(d.role) : "Presenter"
            c.trustTier := d.HasOwnProp("trustTier") ? HostCompanionBridge.NormalizeTrustTier(d.trustTier) : "Ephemeral Guest"
            c.allowDirectObsFallback := d.HasOwnProp("allowDirectObsFallback") ? !!d.allowDirectObsFallback : false
            c.inputPaused := d.HasOwnProp("paused") ? !!d.paused : false
            c.expiresAt := d.HasOwnProp("expiresAt") ? Integer(d.expiresAt) : 0
            if (c.expiresAt > 0 && GetCurrentUnixEpoch() >= c.expiresAt) {
                c.authenticated := false
                d.connected := false
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Guest access expired"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return false
            }
        }
        if (IsObject(msgObj)) {
            c.protocolVersion := Max(1, JsonCodec.GetInt(msgObj, "protocolVersion", 1))
            c.appVersion := JsonCodec.GetStr(msgObj, "appVersion")
            caps := JsonCodec.GetStrArray(msgObj, "capabilities")
            if (caps.Length > 0)
                c.capabilities := caps
        } else if (IsObject(qParams)) {
            qProto := qParams.Get("protocolVersion", "")
            c.protocolVersion := (qProto != "" && IsInteger(qProto)) ? Max(1, Integer(qProto)) : HostBridgeConstants.PROTOCOL_VERSION
            c.appVersion := qParams.Get("appVersion", "")
        }
        skew := HostCompanionBridge.CheckVersionSkew(c.appVersion, c.protocolVersion)
        c.versionSkewWarning := (IsObject(skew) && skew.HasOwnProp("skewed") && skew.skewed && skew.HasOwnProp("reason")) ? skew.reason : ""
        this._QueueWsFrame(c, 0x1, this._BuildAuthOkJson(c))
        if (IsObject(msgObj) && msgObj.Has("clientFallbackState") && (msgObj["clientFallbackState"] is Map))
            this._ReconcileClientFallbackState(c, msgObj["clientFallbackState"])
        this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
        if (IsSet(SessionTimeline))
            SessionTimeline.Record("Remote", "Remote Joined: " (c.deviceName != "" ? c.deviceName : c.deviceId), this.state, c.platform)
        return true
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
            this._ResetPairingFailures(c.ip)
        } else if (code != "" && IsObject(this.cfg) && this.cfg.HasOwnProp("SessionPairingCode") && this.cfg.SessionPairingCode != "") {
            if (NormalizePairingCode(code) == NormalizePairingCode(this.cfg.SessionPairingCode)) {
                matched := true
                this._ResetPairingFailures(c.ip)
            } else {
                this._RecordPairingFailure(c.ip)
            }
        } else if (token != "") {
            this._RecordPairingFailure(c.ip)
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

        prevDev := this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId] : ""
        pairedAtVal := (IsObject(prevDev) && prevDev.pairedAt != "") ? prevDev.pairedAt : FormatTime(, "HH:mm:ss")
        prevRole := (IsObject(prevDev) && prevDev.HasOwnProp("role")) ? HostCompanionBridge.NormalizeRole(prevDev.role) : "Presenter"
        prevTrust := (IsObject(prevDev) && prevDev.HasOwnProp("trustTier")) ? HostCompanionBridge.NormalizeTrustTier(prevDev.trustTier) : "Ephemeral Guest"
        prevAllowFb := (IsObject(prevDev) && prevDev.HasOwnProp("allowDirectObsFallback")) ? !!prevDev.allowDirectObsFallback : false
        prevPaused := (IsObject(prevDev) && prevDev.HasOwnProp("paused")) ? !!prevDev.paused : false
        prevExp := (IsObject(prevDev) && prevDev.HasOwnProp("expiresAt")) ? Integer(prevDev.expiresAt) : 0
        unchanged := IsObject(prevDev)
            && prevDev.deviceName == finalName
            && prevDev.platform == finalPlat
            && prevDev.ip == c.ip
            && prevDev.transport == "Bridge WS"
            && prevDev.token == tokToKeep
            && ((prevDev.HasOwnProp("customName") && prevDev.customName) == hadCustom)
            && prevDev.pairedAt == pairedAtVal

        c.role := prevRole
        c.trustTier := prevTrust
        c.allowDirectObsFallback := prevAllowFb
        c.inputPaused := prevPaused
        c.expiresAt := prevExp

        this.pairedDevices[finalDevId] := {
            deviceId: finalDevId,
            deviceName: finalName,
            platform: finalPlat,
            ip: c.ip,
            transport: "Bridge WS",
            token: tokToKeep,
            pairedAt: pairedAtVal,
            lastSeenTick: A_TickCount,
            connected: true,
            customName: hadCustom,
            role: prevRole,
            trustTier: prevTrust,
            allowDirectObsFallback: prevAllowFb,
            paused: prevPaused,
            expiresAt: prevExp
        }
        if (tokToKeep != "")
            this.validTokens[tokToKeep] := finalDevId
        if (!unchanged)
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

            if (!masked) {
                this._SendWsCloseAndDisconnect(c, 1002, "Unmasked client frame")
                return
            }

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
                    this._SendWsCloseAndDisconnect(c, 1009, "Message too big")
                    return
                }
                payloadLen := lo
                offset := 10
            }

            if (payloadLen > HostBridgeConstants.MAX_BUFFER_BYTES) {
                this._SendWsCloseAndDisconnect(c, 1009, "Message too big")
                return
            }
            if (opcode >= 0x8 && (!fin || payloadLen > 125)) {
                this._SendWsCloseAndDisconnect(c, 1002, "Invalid control frame")
                return
            }

            maskOff := offset
            offset += 4
            totalLen := offset + payloadLen
            if (c.recvLen < totalLen)
                break

            payloadBuf := Buffer(Max(1, payloadLen + 1), 0)
            if (payloadLen > 0) {
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
            } else if (opcode = 0x0) { ; Continuation
                if (c.fragOpcode = 0) {
                    this._SendWsCloseAndDisconnect(c, 1002, "Unexpected continuation")
                    return
                }
                res := _HB_AppendBytes(c.fragBuf, c.fragLen, payloadBuf.Ptr, payloadLen, HostBridgeConstants.MAX_BUFFER_BYTES)
                if (!IsObject(res)) {
                    this._SendWsCloseAndDisconnect(c, 1009, "Message too big")
                    return
                }
                c.fragBuf := res.buf
                c.fragLen := res.len
                if (fin) {
                    msgBuf := Buffer(c.fragLen + 1, 0)
                    if (c.fragLen > 0)
                        DllCall("ntdll\RtlMoveMemory", "Ptr", msgBuf.Ptr, "Ptr", c.fragBuf.Ptr, "UPtr", c.fragLen)
                    isText := (c.fragOpcode == 0x1)
                    c.fragLen := 0
                    c.fragOpcode := 0
                    if (isText) {
                        text := StrGet(msgBuf, "UTF-8")
                        this._HandleWsTextMessage(c, text)
                    }
                }
                if (!this.clients.Has(c.key))
                    return
            } else if (opcode = 0x1 || opcode = 0x2) { ; Text / Binary
                if (c.fragOpcode != 0) {
                    this._SendWsCloseAndDisconnect(c, 1002, "Interleaved data frame")
                    return
                }
                if (!fin) {
                    c.fragOpcode := opcode
                    c.fragLen := 0
                    res := _HB_AppendBytes(c.fragBuf, c.fragLen, payloadBuf.Ptr, payloadLen, HostBridgeConstants.MAX_BUFFER_BYTES)
                    if (!IsObject(res)) {
                        this._SendWsCloseAndDisconnect(c, 1009, "Message too big")
                        return
                    }
                    c.fragBuf := res.buf
                    c.fragLen := res.len
                } else if (opcode = 0x1) {
                    text := (payloadLen > 0) ? StrGet(payloadBuf, "UTF-8") : ""
                    this._HandleWsTextMessage(c, text)
                    if (!this.clients.Has(c.key))
                        return
                }
            } else {
                this._SendWsCloseAndDisconnect(c, 1002, "Unsupported opcode")
                return
            }
        }
        if (c.recvLen == 0 && c.recvBuf.Size > 16384)
            c.recvBuf := Buffer(4096, 0)
    }

    _HandleBridgeMessage(c, msg) {
        return this._HandleWsTextMessage(c, msg)
    }

    _HandleWsTextMessage(c, msg) {
        c.lastRxTick := A_TickCount
        msgObj := JsonCodec.Parse(msg)
        if !(msgObj is Map)
            return
        msgType := StrLower(JsonCodec.GetStr(msgObj, "type"))

        if (!c.authenticated) {
            if (msgType != "auth") {
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Authentication required"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return
            }
            tok := JsonCodec.GetStr(msgObj, "token")
            code := JsonCodec.GetStr(msgObj, "code")
            devId := JsonCodec.GetStr(msgObj, "deviceId")
            devName := JsonCodec.GetStr(msgObj, "deviceName")
            plat := JsonCodec.GetStr(msgObj, "platform")
            if (!this._TryAuthenticateWsClient(c, tok, code, devId, devName, plat)) {
                this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Invalid token or pairing code"}')
                c.closeAfterSend := true
                this._FlushSendQueue(c)
                return
            }
            this._FinalizeWsClientAuth(c, msgObj)
            return
        }

        if (c.deviceId != "" && this.pairedDevices.Has(c.deviceId))
            this.pairedDevices[c.deviceId].lastSeenTick := A_TickCount

        if (msgType = "ping") {
            isMutedStr := this.state.isMuted ? "true" : "false"
            this._QueueWsFrame(c, 0x1, '{"type":"pong","protocolVersion":2,"isMuted":' isMutedStr ',"stateSeq":' this.stateSeq ',"timestamp":' A_TickCount '}')
            return
        }
        if (msgType = "sync_req") {
            this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            return
        }
        if (msgType = "reconcile_fallback_state") {
            fbObj := (msgObj.Has("clientFallbackState") && (msgObj["clientFallbackState"] is Map)) ? msgObj["clientFallbackState"] : msgObj
            if (this._ReconcileClientFallbackState(c, fbObj))
                this.BroadcastMuteState(this.cfg, this.state)
            else
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            return
        }
        if (msgType = "disconnect") {
            this.DisconnectDevice(c.deviceId, false)
            return
        }
        if (msgType = "unpair") {
            this.UnpairDevice(c.deviceId, true)
            return
        }

        cmdId := JsonCodec.GetStr(msgObj, "cmdId")
        expSeq := JsonCodec.GetInt(msgObj, "expectedStateSeq", 0)
        cRole := (c.HasOwnProp("role") && c.role != "") ? HostCompanionBridge.NormalizeRole(c.role) : "Presenter"
        if (c.HasOwnProp("expiresAt") && Integer(c.expiresAt) > 0 && GetCurrentUnixEpoch() >= Integer(c.expiresAt)) {
            this._QueueWsFrame(c, 0x1, '{"type":"auth_error","error":"Guest access expired"}')
            c.closeAfterSend := true
            this._FlushSendQueue(c)
            return
        }
        if (c.HasOwnProp("inputPaused") && c.inputPaused) {
            this._QueueCmdResult(c, msgType, false, cmdId, "input_paused", "Remote input is temporarily paused by host")
            return
        }
        if (!HostCompanionBridge.HasPermissionForCmd(cRole, msgType)) {
            this._QueueCmdResult(c, msgType, false, cmdId, "forbidden", "Role '" cRole "' lacks permission for " msgType)
            return
        }
        if (expSeq > 0 && expSeq < this.stateSeq) {
            this._QueueCmdResult(c, msgType, false, cmdId, "stale_seq", "Stale stateSeq (" expSeq " < " this.stateSeq ")")
            return
        }
        if (cmdId != "") {
            cachedAck := this._CheckAndGetCachedCmdAck(c, cmdId)
            if (cachedAck != "") {
                this._QueueWsFrame(c, 0x1, cachedAck)
                return
            }
        }

        actorName := (c.HasOwnProp("deviceName") && c.deviceName != "") ? c.deviceName : ((c.HasOwnProp("deviceId") && c.deviceId != "") ? c.deviceId : "Remote")
        switch (msgType) {
            case "toggle_mute":
                if (IsObject(this.state) && this.state.HasOwnProp("panicUnmuteLocked") && this.state.panicUnmuteLocked && this.state.HasOwnProp("isMuted") && this.state.isMuted) {
                    this._QueueCmdResult(c, "toggle_mute", false, cmdId, "panic_locked", "Emergency Panic Lock active")
                    this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
                    return
                }
                if (IsObject(this.state))
                    this.state.lastActionActor := actorName
                ok := ExecuteHostRemoteToggleMute(this.cfg, this.state)
                this._QueueCmdResult(c, "toggle_mute", ok, cmdId, ok ? "" : "obs_offline")
            case "set_mute":
                targetMuted := JsonCodec.GetBool(msgObj, "isMuted", this.state.isMuted)
                if (!targetMuted && IsObject(this.state) && this.state.HasOwnProp("panicUnmuteLocked") && this.state.panicUnmuteLocked) {
                    this._QueueCmdResult(c, "set_mute", false, cmdId, "panic_locked", "Emergency Panic Lock active")
                    this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
                    return
                }
                if (IsObject(this.state))
                    this.state.lastActionActor := actorName
                ok := ExecuteHostRemoteSetMute(this.cfg, this.state, targetMuted)
                this._QueueCmdResult(c, "set_mute", ok, cmdId, ok ? "" : "obs_offline")
            case "ppt_next":
                ok := ExecuteHostRemotePptCommand(this.cfg, this.state, "next")
                this._QueueCmdResult(c, "ppt_next", ok, cmdId)
            case "ppt_prev":
                ok := ExecuteHostRemotePptCommand(this.cfg, this.state, "prev")
                this._QueueCmdResult(c, "ppt_prev", ok, cmdId)
            case "slide_start":
                ok := IsSet(StartPowerPointSlideshow) ? StartPowerPointSlideshow() : false
                this._QueueCmdResult(c, "slide_start", ok, cmdId)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "toggle_record":
                ok := ExecuteHostToggleRecord(this.cfg, this.state)
                this._QueueCmdResult(c, "toggle_record", ok, cmdId, ok ? "" : "obs_offline")
            case "set_record":
                wantRec := JsonCodec.HasKey(msgObj, "recording") ? JsonCodec.GetBool(msgObj, "recording", false)
                    : (JsonCodec.HasKey(msgObj, "active") ? JsonCodec.GetBool(msgObj, "active", false) : JsonCodec.GetBool(msgObj, "isRecording", false))
                confirmed := JsonCodec.GetBool(msgObj, "confirmed", true)
                curRec := (IsObject(this.state) && ((this.state.HasOwnProp("recState") && this.state.recState != 0) || (this.state.HasOwnProp("obsRecState") && this.state.obsRecState != 0)))
                confirmCfg := !IsObject(this.cfg) || !this.cfg.HasOwnProp("ConfirmBeforeStopRecording") || this.cfg.ConfirmBeforeStopRecording
                if (!wantRec && curRec && confirmCfg && !confirmed) {
                    this._QueueCmdResult(c, "set_record", false, cmdId, "confirm_required", "Explicit confirmation required before stopping recording")
                    return
                }
                if (wantRec == curRec)
                    ok := true
                else
                    ok := wantRec ? ExecuteHostStartRecord(this.cfg, this.state) : ExecuteHostStopRecord(this.cfg, this.state)
                this._QueueCmdResult(c, "set_record", ok, cmdId, ok ? "" : "obs_offline")
            case "pause_record":
                ok := ExecuteHostPauseRecord(this.cfg, this.state)
                this._QueueCmdResult(c, "pause_record", ok, cmdId, ok ? "" : "obs_offline")
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "split_record":
                ok := ExecuteHostSplitRecord(this.cfg, this.state)
                this._QueueCmdResult(c, "split_record", ok, cmdId, ok ? "" : "obs_offline")
            case "switch_scene":
                sName := JsonCodec.GetStr(msgObj, "sceneName")
                ok := ExecuteHostSwitchScene(this.cfg, this.state, sName)
                this._QueueCmdResult(c, "switch_scene", ok, cmdId, ok ? "" : ((sName = "") ? "invalid_args" : "obs_offline"))
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "set_preview_scene":
                sName := JsonCodec.GetStr(msgObj, "sceneName")
                ok := ExecuteHostSetPreviewScene(this.cfg, this.state, sName)
                this._QueueCmdResult(c, "set_preview_scene", ok, cmdId, ok ? "" : ((sName = "") ? "invalid_args" : "obs_offline"))
            case "set_scene_item_enabled":
                sName := JsonCodec.GetStr(msgObj, "sceneName")
                itemId := JsonCodec.GetInt(msgObj, "sceneItemId", 0)
                en := JsonCodec.GetBool(msgObj, "enabled", true)
                ok := ExecuteHostSetSceneItemEnabled(this.cfg, this.state, sName, itemId, en)
                this._QueueCmdResult(c, "set_scene_item_enabled", ok, cmdId, ok ? "" : "obs_offline")
            case "set_input_volume":
                inName := JsonCodec.GetStr(msgObj, "inputName")
                volMul := JsonCodec.GetFloat(msgObj, "volumeMul", 1.0)
                ok := ExecuteHostSetInputVolume(this.cfg, this.state, inName, volMul)
                this._QueueCmdResult(c, "set_input_volume", ok, cmdId, ok ? "" : "obs_offline")
            case "audio_handoff":
                hMode := JsonCodec.GetStr(msgObj, "mode")
                ok := ExecuteHostAudioHandoff(this.cfg, this.state, hMode)
                this._QueueCmdResult(c, "audio_handoff", ok, cmdId, ok ? "" : "obs_offline")
            case "save_replay_buffer":
                ok := ExecuteHostSaveReplayBuffer(this.cfg, this.state)
                this._QueueCmdResult(c, "save_replay_buffer", ok, cmdId, ok ? "" : "obs_offline")
            case "add_bookmark":
                lbl := JsonCodec.GetStr(msgObj, "label")
                ok := IsSet(SessionTimeline) ? SessionTimeline.AddBookmark(lbl, this.state, actorName) : false
                this._QueueCmdResult(c, "add_bookmark", ok, cmdId)
            case "session_reset":
                rev := JsonCodec.GetBool(msgObj, "revokeGuests", true)
                ok := ExecuteHostSessionTurnover(this.cfg, this.state, rev)
                this._QueueCmdResult(c, "session_reset", ok, cmdId)
            case "transition_scene":
                ok := false
                if (IsObject(this.state) && this.state.HasOwnProp("triggerTransitionFn") && IsObject(this.state.triggerTransitionFn))
                    ok := (this.state.triggerTransitionFn.Call() != false)
                else if (IsSet(TriggerObsSceneTransition))
                    ok := TriggerObsSceneTransition(this.cfg, this.state, true)
                failCode := (IsObject(this.state) && this.state.HasOwnProp("lastTransitionFailReason") && this.state.lastTransitionFailReason != "")
                    ? this.state.lastTransitionFailReason
                    : "obs_offline"
                this._QueueCmdResult(c, "transition_scene", ok, cmdId, ok ? "" : failCode)
            case "reset_active_scene":
                ok := false
                if (IsObject(this.state) && this.state.HasOwnProp("obsSceneResetFn") && IsObject(this.state.obsSceneResetFn))
                    ok := (this.state.obsSceneResetFn.Call() != false)
                else if (IsSet(ExecuteHostResetActiveScene))
                    ok := ExecuteHostResetActiveScene(this.cfg, this.state)
                failCode := (!ok && IsObject(this.state) && this.state.HasOwnProp("sceneResetInProgress") && this.state.sceneResetInProgress) ? "reset_in_progress" : "obs_offline"
                this._QueueCmdResult(c, "reset_active_scene", ok, cmdId, ok ? "" : failCode)
            case "toggle_standby":
                ok := ExecuteHostToggleStandby(this.cfg, this.state)
                this._QueueCmdResult(c, "toggle_standby", ok, cmdId)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "set_standby":
                wantBrb := JsonCodec.HasKey(msgObj, "isStandby") ? JsonCodec.GetBool(msgObj, "isStandby", false) : JsonCodec.GetBool(msgObj, "enabled", false)
                ok := ExecuteHostToggleStandby(this.cfg, this.state, wantBrb)
                this._QueueCmdResult(c, "set_standby", ok, cmdId)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "emergency_panic":
                wantPanic := JsonCodec.HasKey(msgObj, "active") ? JsonCodec.GetBool(msgObj, "active", true) : ""
                ok := ExecuteHostEmergencyPanic(this.cfg, this.state, wantPanic)
                this._QueueCmdResult(c, "emergency_panic", ok, cmdId)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "clear_panic":
                ok := ExecuteHostEmergencyPanic(this.cfg, this.state, false)
                this._QueueCmdResult(c, "clear_panic", ok, cmdId)
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "timer_start":
                dur := JsonCodec.GetInt(msgObj, "durationSec", 0)
                ok := StartHostPresenterTimer(this.cfg, this.state, dur)
                this._QueueCmdResult(c, "timer_start", ok, cmdId)
            case "timer_pause":
                ok := PauseHostPresenterTimer(this.cfg, this.state)
                this._QueueCmdResult(c, "timer_pause", ok, cmdId)
            case "timer_reset":
                dur := JsonCodec.GetInt(msgObj, "durationSec", 0)
                ok := ResetHostPresenterTimer(this.cfg, this.state, dur)
                this._QueueCmdResult(c, "timer_reset", ok, cmdId)
            case "stage_nudge":
                nMsg := JsonCodec.GetStr(msgObj, "message")
                nSnd := JsonCodec.GetStr(msgObj, "sender")
                nAcc := JsonCodec.GetStr(msgObj, "accentHex")
                nId := JsonCodec.GetStr(msgObj, "nudgeId")
                nTarget := JsonCodec.GetStr(msgObj, "targetDeviceId")
                nUrg := JsonCodec.GetStr(msgObj, "urgency")
                nReqAck := JsonCodec.HasKey(msgObj, "requiresAck") ? JsonCodec.GetBool(msgObj, "requiresAck", false) : false
                nDir := StrLower(JsonCodec.GetStr(msgObj, "direction"))
                if (nSnd = "")
                    nSnd := actorName
                if (nDir = "" && cRole = "Presenter")
                    nDir := "stage_back"
                if (nDir = "stage_back") {
                    ; Presenter -> Primary Controller Inbox only (never echo back to other remotes)
                    if (IsObject(this.state)) {
                        if (!this.state.HasOwnProp("presenterSignals") || !IsObject(this.state.presenterSignals))
                            this.state.presenterSignals := []
                        this.state.presenterSignals.Push({ nudgeId: nId, message: nMsg, sender: nSnd, deviceId: c.deviceId, urgency: (nUrg != "" ? nUrg : "sticky"), tick: A_TickCount })
                        if (this.state.presenterSignals.Length > 32)
                            this.state.presenterSignals.RemoveAt(1)
                    }
                    if (IsSet(ShowStageNudgeBanner) && (!IsObject(this.state) || !this.state.HasOwnProp("suppressNudgeBanners") || !this.state.suppressNudgeBanners))
                        ShowStageNudgeBanner(nMsg, nAcc != "" ? nAcc : "38BDF8", 4500, nSnd " [Stage-Back]")
                    if (IsSet(SessionTimeline))
                        SessionTimeline.Record("Intercom", "Stage-Back Signal from " nSnd ": " nMsg, this.state, c.platform)
                    this._QueueCmdResult(c, "stage_nudge", nMsg != "", cmdId)
                } else {
                    nOpts := { nudgeId: nId, targetDeviceId: (nTarget != "" ? nTarget : "All"), originDeviceId: c.deviceId, urgency: (nUrg != "" ? nUrg : "whisper"), requiresAck: nReqAck, direction: "stage_out" }
                    ok := BroadcastHostStageNudge(this.cfg, this.state, nMsg, nSnd, nAcc != "" ? nAcc : "F59E0B", nOpts)
                    this._QueueCmdResult(c, "stage_nudge", ok, cmdId)
                }
            case "nudge_ack":
                ackId := JsonCodec.GetStr(msgObj, "nudgeId")
                okAck := false
                if (ackId != "" && this.HasOwnProp("nudgeStatusMap") && IsObject(this.nudgeStatusMap) && this.nudgeStatusMap.Has(ackId)) {
                    entry := this.nudgeStatusMap[ackId]
                    entry.status := "Ack'd"
                    entry.ackedBy.Push(actorName)
                    okAck := true
                    if (IsSet(SessionTimeline))
                        SessionTimeline.Record("Intercom", "Cue Ack'd (" ackId ") by " actorName, this.state, c.platform)
                }
                this._QueueCmdResult(c, "nudge_ack", okAck, cmdId, okAck ? "" : "unknown_nudge")
        }
    }

    _ReconcileClientFallbackState(c, fbObj) {
        if (!IsObject(this.state) || !(fbObj is Map))
            return false
        if (!JsonCodec.GetBool(fbObj, "fromDirectObsFallback", false))
            return false
        changed := false

        fbStandby := JsonCodec.GetBool(fbObj, "isStandby", false)
        hostStandby := (this.state.HasOwnProp("isStandby") && this.state.isStandby)
        if (fbStandby && !hostStandby) {
            prevScene := Trim(JsonCodec.GetStr(fbObj, "previousScene"))
            if (prevScene = "")
                prevScene := (this.state.HasOwnProp("currentSceneName") && this.state.currentSceneName != "" && this.state.currentSceneName != "Scene")
                    ? String(this.state.currentSceneName)
                    : "Scene"
            wasMuted := JsonCodec.GetBool(fbObj, "wasMuted", false)
            brbScene := Trim(JsonCodec.GetStr(fbObj, "standbyScene"))
            if (brbScene = "")
                brbScene := (IsObject(this.cfg) && this.cfg.HasOwnProp("StandbySceneName") && this.cfg.StandbySceneName != "") ? String(this.cfg.StandbySceneName) : "BRB"
            this.state.standbySnapshot := {
                muted: wasMuted,
                scene: prevScene,
                recWasActive: (this.state.HasOwnProp("recState") && this.state.recState == 1)
            }
            this.state.isStandby := true
            if (!this.state.HasOwnProp("currentSceneName") || this.state.currentSceneName = "" || this.state.currentSceneName = "Scene")
                this.state.currentSceneName := brbScene
            changed := true
        }

        fbTimerSt := StrLower(Trim(JsonCodec.GetStr(fbObj, "timerState")))
        hostTimerSt := this.state.HasOwnProp("timerState") ? StrLower(Trim(String(this.state.timerState))) : "stopped"
        if ((fbTimerSt = "running" || fbTimerSt = "paused" || fbTimerSt = "overtime") && (hostTimerSt = "stopped" || hostTimerSt = "")) {
            fbRem := JsonCodec.GetInt(fbObj, "timerRemainingSec", 600)
            fbPreset := JsonCodec.GetInt(fbObj, "timerPresetSec", 600)
            this.state.timerState := fbTimerSt
            this.state.timerRemainingSec := fbRem
            this.state.timerPresetSec := (fbPreset > 0) ? fbPreset : 600
            if ((fbTimerSt = "running" || fbTimerSt = "overtime") && this.state.HasOwnProp("presenterTimerFn") && this.state.presenterTimerFn)
                try SetTimer(this.state.presenterTimerFn, 1000)
            changed := true
        }

        if (changed && IsSet(DiagnosticLogger)) {
            devLabel := (IsObject(c) && c.HasOwnProp("deviceId")) ? c.deviceId : "remote"
            try DiagnosticLogger.RecordBreadcrumb("Bridge", "FallbackStateReconciled", "dev=" devLabel " brb=" (this.state.isStandby ? 1 : 0) " tmr=" this.state.timerState)
        }
        return changed
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
        camActStr := (this.state.HasOwnProp("cameraActive") && this.state.cameraActive) ? "true" : "false"
        handsCnt := this.state.HasOwnProp("raisedHandCount") ? Integer(this.state.raisedHandCount) : 0
        shareActStr := (this.state.HasOwnProp("screenShareActive") && this.state.screenShareActive) ? "true" : "false"
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
        recStallStr := (this.state.HasOwnProp("recStallWarn") && this.state.recStallWarn) ? "true" : "false"
        encOverStr := (this.state.HasOwnProp("encoderOverloadWarn") && this.state.encoderOverloadWarn) ? "true" : "false"
        obsCrashStr := (this.state.HasOwnProp("obsCrashedRecWarn") && this.state.obsCrashedRecWarn) ? "true" : "false"
        forgotStopStr := (this.state.HasOwnProp("forgotStopWarn") && this.state.forgotStopWarn) ? "true" : "false"
        obsFps := this.state.HasOwnProp("obsActiveFps") ? Float(this.state.obsActiveFps) : 0.0
        obsRSkip := this.state.HasOwnProp("obsRenderSkipped") ? Integer(this.state.obsRenderSkipped) : 0
        obsOSkip := this.state.HasOwnProp("obsOutputSkipped") ? Integer(this.state.obsOutputSkipped) : 0
        obsAvgMs := this.state.HasOwnProp("obsAvgRenderMs") ? Float(this.state.obsAvgRenderMs) : 0.0
        studioActStr := (this.state.HasOwnProp("studioModeActive") && this.state.studioModeActive) ? "true" : "false"
        prevScene := this.state.HasOwnProp("previewSceneName") ? String(this.state.previewSceneName) : ""
        strmSt := this.state.HasOwnProp("streamState") ? Integer(this.state.streamState) : 0
        strmCong := this.state.HasOwnProp("streamCongestion") ? Round(Float(this.state.streamCongestion), 2) : 0.0
        strmSkip := this.state.HasOwnProp("streamSkippedFrames") ? Integer(this.state.streamSkippedFrames) : 0
        vcamStr := (this.state.HasOwnProp("vcamActive") && this.state.vcamActive) ? "true" : "false"
        unreadCnt := this.state.HasOwnProp("unreadChatCount") ? Integer(this.state.unreadChatCount) : 0
        vPeak := this.state.HasOwnProp("voicePeak") ? Round(Float(this.state.voicePeak), 2) : 0.0
        rawQn := (IsObject(this.cfg) && this.cfg.HasOwnProp("QuickNudgePresets")) ? this.cfg.QuickNudgePresets : "2 min left|Wrap up|Check Mic|Q&A"
        qnList := IsSet(ParseQuickNudgePresets) ? ParseQuickNudgePresets(rawQn, 6) : ["2 min left", "Wrap up", "Check Mic", "Q&A"]
        qnJson := "["
        for idx, qItem in qnList
            qnJson .= (idx > 1 ? "," : "") '"' _HB_JsonEscape(qItem) '"'
        qnJson .= "]"
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
        panicStr := (this.state.HasOwnProp("isPanic") && this.state.isPanic) ? "true" : "false"
        panicLockStr := (this.state.HasOwnProp("panicUnmuteLocked") && this.state.panicUnmuteLocked) ? "true" : "false"
        standbyScene := (this.cfg.HasOwnProp("StandbySceneName") && this.cfg.StandbySceneName != "") ? String(this.cfg.StandbySceneName) : "BRB"
        tState := this.state.HasOwnProp("timerState") ? String(this.state.timerState) : "stopped"
        tRem := this.state.HasOwnProp("timerRemainingSec") ? Integer(this.state.timerRemainingSec) : 600
        tPre := this.state.HasOwnProp("timerPresetSec") ? Integer(this.state.timerPresetSec) : 600
        lastActor := this.state.HasOwnProp("lastActionActor") ? String(this.state.lastActionActor) : ""
        hostUuid := EnsureHostUuid(this.cfg)
        bootId := _HB_JsonEscape(this._EnsureBootId())
        ver := _HB_JsonEscape(UIConstants.APP_VERSION)
        return '"protocolVersion":' HostBridgeConstants.PROTOCOL_VERSION ',"appVersion":"' ver '","hostBootId":"' bootId '","stateSeq":' this.stateSeq ',"hostUuid":"' _HB_JsonEscape(hostUuid) '","isMuted":' isMutedStr ',"lastActionActor":"' _HB_JsonEscape(lastActor) '","routingMode":' mode ',"targetMicName":"' _HB_JsonEscape(micName) '","conferencingApp":"' _HB_JsonEscape(confApp) '","detectedConfApp":"' _HB_JsonEscape(detConfApp) '","meetBgTabWarn":' meetBgWarnStr ',"cameraActive":' camActStr ',"raisedHandCount":' handsCnt ',"screenShareActive":' shareActStr ',"slideIndex":' sIdx ',"slideTotal":' sTot ',"slideTitle":"' _HB_JsonEscape(sTitle) '","slideNotes":"' _HB_JsonEscape(sNotes) '","recState":' recSt ',"obsRecState":' obsRecSt ',"confRecState":' confRecSt ',"recSourceTag":"' _HB_JsonEscape(recSrcTag) '","recSeconds":' recSec ',"obsConnected":' obsConnStr ',"studioModeActive":' studioActStr ',"previewSceneName":"' _HB_JsonEscape(prevScene) '","streamState":' strmSt ',"streamCongestion":' strmCong ',"streamSkippedFrames":' strmSkip ',"vcamActive":' vcamStr ',"unreadChatCount":' unreadCnt ',"voicePeak":' vPeak ',"streamDropWarn":' streamWarnStr ',"voiceWhileMuted":' voiceMutedStr ',"osMicMutedDrift":' osDriftStr ',"lowDiskWarnLevel":' lowDiskLvl ',"lowDiskMb":' lowDiskMbVal ',"deadMicWarn":' deadMicStr ',"recStallWarn":' recStallStr ',"encoderOverloadWarn":' encOverStr ',"obsCrashedRecWarn":' obsCrashStr ',"forgotStopWarn":' forgotStopStr ',"obsStats":{"activeFps":' obsFps ',"renderSkippedFrames":' obsRSkip ',"outputSkippedFrames":' obsOSkip ',"averageFrameRenderTime":' obsAvgMs '},"quickNudges":' qnJson ',"activeScene":"' _HB_JsonEscape(activeScene) '","scenes":' scenesJson ',"isStandby":' standbyStr ',"isPanic":' panicStr ',"panicUnmuteLocked":' panicLockStr ',"standbyScene":"' _HB_JsonEscape(standbyScene) '","timerState":"' _HB_JsonEscape(tState) '","timerRemainingSec":' tRem ',"timerPresetSec":' tPre ',"version":"' ver '","timestamp":' A_TickCount
    }

    _BuildMuteStateJson() {
        return '{"type":"mute_state",' this._BuildStateFieldsJson() '}'
    }

    _BuildSyncResyncJson(reason := "wake", clientRole := "") {
        roleField := (clientRole != "") ? ('"role":"' _HB_JsonEscape(clientRole) '",') : ""
        return '{"type":"sync_resync","reason":"' _HB_JsonEscape(reason) '",' roleField this._BuildStateFieldsJson() '}'
    }

    BroadcastSessionReset() {
        payload := '{"type":"session_reset","timestamp":' A_TickCount '}'
        return this._BroadcastJsonToAuthenticated(payload)
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
        ConfigStore.AtomicReplaceIniSection(cfg.ConfigFile, "HostBridgePairedDevices", Map())
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

FlashHostDevicePill(devId, durationMs := 1800) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.FlashDevicePill(devId, durationMs)
    return 0
}

SetHostDeviceRole(devId, role) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.SetDeviceRole(devId, role)
    return false
}

SetHostDeviceTrustTier(devId, trustTier) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.SetDeviceTrustTier(devId, trustTier)
    return false
}

SetHostDeviceDirectObsFallback(devId, allow) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.SetDeviceDirectObsFallback(devId, allow)
    return false
}

SetHostDevicePaused(devId, paused) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.SetDevicePaused(devId, paused)
    return false
}

RevokeHostEphemeralGuests() {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.RevokeEphemeralGuests()
    return 0
}

_HB_SerializePairedDevice(dev) {
    customFlag := (dev.HasOwnProp("customName") && dev.customName) ? "1" : "0"
    roleStr := dev.HasOwnProp("role") ? HostCompanionBridge.NormalizeRole(dev.role) : "Presenter"
    tierStr := dev.HasOwnProp("trustTier") ? HostCompanionBridge.NormalizeTrustTier(dev.trustTier) : "Ephemeral Guest"
    obsFbFlag := (dev.HasOwnProp("allowDirectObsFallback") && dev.allowDirectObsFallback) ? "1" : "0"
    pausedFlag := (dev.HasOwnProp("paused") && dev.paused) ? "1" : "0"
    expEpoch := dev.HasOwnProp("expiresAt") ? Integer(dev.expiresAt) : 0
    tokProtected := ConfigStore.ProtectSecret(dev.token)
    return "v1|" UriEncodeComponent(dev.deviceName) "|" UriEncodeComponent(dev.platform) "|" UriEncodeComponent(tokProtected) "|" UriEncodeComponent(dev.pairedAt) "|" UriEncodeComponent(dev.ip) "|" UriEncodeComponent(dev.transport) "|" customFlag "|" UriEncodeComponent(roleStr) "|" UriEncodeComponent(tierStr) "|" obsFbFlag "|" pausedFlag "|" expEpoch
}

_HB_ParsePairedDevice(devId, rawVal) {
    parts := StrSplit(String(rawVal), "|")
    if (parts.Length < 7 || parts[1] != "v1")
        return ""
    tok := ConfigStore.UnprotectSecret(UriDecodeComponent(parts[4]), "HostBridgePairedDevice." devId)
    if (tok = "" || devId = "")
        return ""
    roleStr := (parts.Length >= 9 && parts[9] != "") ? HostCompanionBridge.NormalizeRole(UriDecodeComponent(parts[9])) : "Presenter"
    tierStr := (parts.Length >= 10 && parts[10] != "") ? HostCompanionBridge.NormalizeTrustTier(UriDecodeComponent(parts[10])) : "Ephemeral Guest"
    obsFb := (parts.Length >= 11 && parts[11] = "1")
    paused := (parts.Length >= 12 && parts[12] = "1")
    expEpoch := 0
    if (parts.Length >= 13 && IsInteger(parts[13]))
        expEpoch := Integer(parts[13])
    return {
        deviceId: devId,
        deviceName: UriDecodeComponent(parts[2]),
        platform: UriDecodeComponent(parts[3]),
        token: tok,
        pairedAt: UriDecodeComponent(parts[5]),
        ip: UriDecodeComponent(parts[6]),
        transport: UriDecodeComponent(parts[7]),
        customName: (parts.Length >= 8 && parts[8] = "1"),
        role: roleStr,
        trustTier: tierStr,
        allowDirectObsFallback: obsFb,
        paused: paused,
        expiresAt: expEpoch,
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

HostBridgeBroadcastObsFallback(cfg := "") {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastObsFallbackUpdate(cfg)
    return 0
}

HostBridgeBroadcastStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B", opts := "") {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastStageNudge(cfg, state, message, sender, accentHex, opts)
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

    nonVirt := []
    virt := []
    if IsObject(candidateIps) {
        for ep in candidateIps {
            if (IsObject(ep) && ep.HasOwnProp("ip")) {
                if (ep.HasOwnProp("isVirtual") && ep.isVirtual)
                    virt.Push(ep.ip)
                else
                    nonVirt.Push(ep.ip)
            } else {
                nonVirt.Push(ep)
            }
        }
    } else if (Type(candidateIps) = "String" && candidateIps != "") {
        for part in StrSplit(candidateIps, ",")
            nonVirt.Push(part)
    } else if (IsSet(GetLocalNetworkEndpoints)) {
        try {
            eps := GetLocalNetworkEndpoints(false)
            if (IsObject(eps) && eps.HasOwnProp("details")) {
                for ep in eps.details {
                    if (ep.HasOwnProp("isVirtual") && ep.isVirtual)
                        virt.Push(ep.ip)
                    else
                        nonVirt.Push(ep.ip)
                }
            }
        }
    }
    for ep in nonVirt {
        if (hosts.Length >= 4)
            break
        PushHost(ep)
    }
    for ep in virt {
        if (hosts.Length >= 4)
            break
        PushHost(ep)
    }
    PushHost(A_ComputerName ".local")

    hostStr := ""
    limit := Min(hosts.Length, 5)
    Loop limit {
        hostStr .= (A_Index > 1 ? "," : "") hosts[A_Index]
    }

    obsPort := _HB_GetObsWsPort(cfg)
    bridgePort := 0
    try bridgePort := Integer(bridgePortOverride)
    if (bridgePort <= 0 && IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running && g_HostCompanionBridge.boundTcpPort > 0)
        bridgePort := Integer(g_HostCompanionBridge.boundTcpPort)
    if (bridgePort <= 0 && IsSet(AppState) && IsObject(AppState) && AppState.HasOwnProp("activeBridgePort") && AppState.activeBridgePort > 0)
        bridgePort := Integer(AppState.activeBridgePort)
    if (bridgePort <= 0)
        bridgePort := (IsObject(cfg) && cfg.HasOwnProp("BridgePort")) ? Integer(cfg.BridgePort) : 4456
    sessCode := (IsObject(cfg) && cfg.HasOwnProp("SessionPairingCode")) ? Trim(String(cfg.SessionPairingCode)) : ""
    micName := (IsObject(cfg) && cfg.HasOwnProp("targetMicName")) ? Trim(String(cfg.targetMicName)) : "Mic/Aux"
    netMode := (IsObject(cfg) && ((cfg.HasOwnProp("RemoteNetworkMode") && StrLower(cfg.RemoteNetworkMode) = "internet") || (cfg.HasOwnProp("NetworkMode") && StrLower(cfg.NetworkMode) = "internet"))) ? "internet" : "lan"
    rc := (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode")) ? Trim(String(cfg.InternetPairingCode)) : ""
    relayBase := IsSet(GetEffectiveRelayBaseUrl) ? GetEffectiveRelayBaseUrl(cfg) : ((IsObject(cfg) && cfg.HasOwnProp("RelayBaseUrl")) ? Trim(String(cfg.RelayBaseUrl)) : "https://ntfy.sh")
    hasObsPw := (IsObject(cfg) && cfg.HasOwnProp("obsPassword") && cfg.obsPassword != "")
    uuid := EnsureHostUuid(cfg)
    preset := (IsObject(cfg) && cfg.HasOwnProp("HudColorPreset")) ? cfg.HudColorPreset : "Standard"
    cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
    cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"

    uri := "presentersync://connect?hosts=" UriEncodeComponent(hostStr)
        . "&code=" UriEncodeComponent(sessCode)
        . "&mode=" netMode
    if (obsPort != 4455)
        uri .= "&port=" obsPort
    if (bridgePort != 4456)
        uri .= "&bp=" bridgePort
    if (micName != "" && micName != "Mic/Aux")
        uri .= "&mic=" UriEncodeComponent(micName)
    if (rc != "")
        uri .= "&rc=" UriEncodeComponent(rc)
    if (relayBase != "" && StrLower(RTrim(relayBase, "/")) != "https://ntfy.sh")
        uri .= "&relay=" UriEncodeComponent(relayBase)
    if (hasObsPw)
        uri .= "&rpw=1"
    if (uuid != "")
        uri .= "&uuid=" UriEncodeComponent(uuid)
    if (preset != "" && preset != "Standard")
        uri .= "&preset=" UriEncodeComponent(preset)
    if (cLive != "" && StrUpper(cLive) != "107C10")
        uri .= "&clh=" UriEncodeComponent(cLive)
    if (cMuted != "" && StrUpper(cMuted) != "C42B1C")
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
