; ==============================================================================
; Module: HostBridge.ahk
; Description: Non-blocking WinSock2 (WSAAsyncSelect) Companion Bridge Server
;              on UDP + TCP port 4456 (configurable/ephemeral for tests).
;              Provides:
;                1) UDP LAN Session Code Discovery (PSYNC_DISCOVER -> PSYNC_OFFER)
;                2) HTTP Session Pairing (POST /pair, GET /health) w/ rate limit
;                3) Direct RFC 6455 WebSocket Bridge (ws://<host>:4456/ws)
;              Zero blocking calls — driven completely by Win32 window messages.
; ==============================================================================

#DllLoad ws2_32.dll

class HostBridgeConstants {
    static DEFAULT_PORT := 4456
    static MAX_BUFFER_BYTES := 65536
    static AUTH_TIMEOUT_MS := 3000
    static KEEP_ALIVE_MS := 20000
    static PAIR_MAX_FAILS := 5
    static PAIR_LOCKOUT_MS := 30000
    static UDP_COOLDOWN_MS := 200
    static WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
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
    boundTcpPort := 0
    boundUdpPort := 0
    running := false
    wsaStarted := false
    msgGui := ""
    hwnd := 0
    wmTcp := 0x0551
    wmUdp := 0x0552
    tcpListenSock := -1
    udpSock := -1
    clients := Map()
    pairedDevices := Map()
    validTokens := Map()
    rateLimits := Map()
    tcpMsgFn := ""
    udpMsgFn := ""
    maintTimerFn := ""
    lastError := ""

    Start(cfg, state, tcpPort := 4456, udpPort := -1) {
        this.Stop()
        this.cfg := cfg
        this.state := state
        this.requestedTcpPort := tcpPort
        this.requestedUdpPort := (udpPort = -1) ? tcpPort : udpPort
        this.lastError := ""

        if (!cfg.HasOwnProp("SessionPairingCode") || cfg.SessionPairingCode = "")
            cfg.SessionPairingCode := GenerateSessionPairingCode()

        wsaData := Buffer(408, 0)
        if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int") != 0) {
            this.lastError := "WSAStartup failed"
            return false
        }
        this.wsaStarted := true

        this.msgGui := Gui("-Caption +ToolWindow", "PresenterSync_HostBridgeMsg")
        this.hwnd := this.msgGui.Hwnd

        this.tcpMsgFn := ObjBindMethod(this, "_OnTcpMessage")
        this.udpMsgFn := ObjBindMethod(this, "_OnUdpMessage")
        OnMessage(this.wmTcp, this.tcpMsgFn)
        OnMessage(this.wmUdp, this.udpMsgFn)

        ; 1) Bind TCP Listener (HTTP /pair + /health + RFC 6455 WS /ws)
        this.tcpListenSock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if (this.tcpListenSock = -1) {
            this.lastError := "TCP socket create failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            this.Stop()
            return false
        }

        optOn := Buffer(4, 0)
        NumPut("Int", 1, optOn, 0)
        DllCall("ws2_32\setsockopt", "Ptr", this.tcpListenSock, "Int", 0xFFFF, "Int", 4, "Ptr", optOn, "Int", 4, "Int")

        tcpAddr := _HB_MakeSockAddrIn(this.requestedTcpPort, 0)
        if (DllCall("ws2_32\bind", "Ptr", this.tcpListenSock, "Ptr", tcpAddr, "Int", 16, "Int") != 0) {
            this.lastError := "TCP bind port " this.requestedTcpPort " failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            this.Stop()
            return false
        }

        outAddr := Buffer(16, 0)
        outLen := 16
        DllCall("ws2_32\getsockname", "Ptr", this.tcpListenSock, "Ptr", outAddr, "Int*", &outLen, "Int")
        this.boundTcpPort := _HB_htons(NumGet(outAddr, 2, "UShort"))

        if (DllCall("ws2_32\listen", "Ptr", this.tcpListenSock, "Int", 16, "Int") != 0) {
            this.lastError := "TCP listen failed: " DllCall("ws2_32\WSAGetLastError", "Int")
            this.Stop()
            return false
        }

        ; FD_READ(1) | FD_WRITE(2) | FD_ACCEPT(8) | FD_CLOSE(32) = 0x2B
        if (DllCall("ws2_32\WSAAsyncSelect", "Ptr", this.tcpListenSock, "Ptr", this.hwnd, "UInt", this.wmTcp, "Int", 0x2B, "Int") != 0) {
            this.lastError := "TCP WSAAsyncSelect failed"
            this.Stop()
            return false
        }

        ; 2) Bind UDP Discovery Socket (best-effort if udpPort >= 0)
        if (this.requestedUdpPort >= 0) {
            this.udpSock := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "Ptr")
            if (this.udpSock != -1) {
                DllCall("ws2_32\setsockopt", "Ptr", this.udpSock, "Int", 0xFFFF, "Int", 4, "Ptr", optOn, "Int", 4, "Int")
                DllCall("ws2_32\setsockopt", "Ptr", this.udpSock, "Int", 0xFFFF, "Int", 0x0020, "Ptr", optOn, "Int", 4, "Int")
                udpAddr := _HB_MakeSockAddrIn(this.requestedUdpPort, 0)
                if (DllCall("ws2_32\bind", "Ptr", this.udpSock, "Ptr", udpAddr, "Int", 16, "Int") = 0) {
                    uOut := Buffer(16, 0)
                    uLen := 16
                    DllCall("ws2_32\getsockname", "Ptr", this.udpSock, "Ptr", uOut, "Int*", &uLen, "Int")
                    this.boundUdpPort := _HB_htons(NumGet(uOut, 2, "UShort"))
                    DllCall("ws2_32\WSAAsyncSelect", "Ptr", this.udpSock, "Ptr", this.hwnd, "UInt", this.wmUdp, "Int", 1, "Int")
                } else {
                    DllCall("ws2_32\closesocket", "Ptr", this.udpSock)
                    this.udpSock := -1
                }
            }
        }

        this.running := true
        this.maintTimerFn := ObjBindMethod(this, "_OnMaintenanceTick")
        SetTimer(this.maintTimerFn, 1000)
        return true
    }

    Stop() {
        this.running := false
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
        if (IsObject(this.msgGui)) {
            try this.msgGui.Destroy()
            this.msgGui := ""
        }
        this.hwnd := 0
        this.boundTcpPort := 0
        this.boundUdpPort := 0
        if (this.wsaStarted) {
            try DllCall("ws2_32\WSACleanup")
            this.wsaStarted := false
        }
    }

    RotateSessionCode() {
        newCode := GenerateSessionPairingCode()
        this.cfg.SessionPairingCode := newCode
        this.rateLimits := Map()
        return newCode
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
                connected: d.connected
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
        payload := this._BuildMuteStateJson()
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
        sent := 0
        for _, cli in this.clients {
            if (cli.kind = "ws" && cli.authenticated) {
                this._QueueWsFrame(cli, 0x1, payload)
                sent += 1
            }
        }
        return sent
    }

    _GetRateLimit(ip) {
        if (!this.rateLimits.Has(ip))
            this.rateLimits[ip] := { fails: 0, lockUntil: 0, lastUdpTick: 0 }
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
        for k, cli in this.clients {
            if (cli.kind = "pending" && (now - cli.createdTick) > HostBridgeConstants.AUTH_TIMEOUT_MS) {
                toClose.Push(cli)
            } else if (cli.kind = "ws" && !cli.authenticated && (now - cli.createdTick) > HostBridgeConstants.AUTH_TIMEOUT_MS) {
                toClose.Push(cli)
            } else if (cli.kind = "ws" && cli.authenticated) {
                if ((now - cli.lastPingTick) >= HostBridgeConstants.KEEP_ALIVE_MS) {
                    cli.lastPingTick := now
                    this._QueueWsFrame(cli, 0x9, "")
                }
            }
        }
        for cli in toClose
            this._CloseClient(cli)
    }

    _OnUdpMessage(wParam, lParam, msg, hwnd) {
        if (!this.running || this.udpSock = -1)
            return
        ev := lParam & 0xFFFF
        if (ev != 1)
            return

        rxBuf := Buffer(2048, 0)
        fromAddr := Buffer(16, 0)
        Loop {
            fromLen := 16
            n := DllCall("ws2_32\recvfrom", "Ptr", this.udpSock, "Ptr", rxBuf, "Int", 2048, "Int", 0, "Ptr", fromAddr, "Int*", &fromLen, "Int")
            if (n <= 0)
                break
            NumPut("UChar", 0, rxBuf, Min(n, 2047))
            pkt := StrGet(rxBuf, "UTF-8")
            ip := _HB_FormatIp(fromAddr)
            rl := this._GetRateLimit(ip)
            now := A_TickCount
            if ((now - rl.lastUdpTick) < HostBridgeConstants.UDP_COOLDOWN_MS)
                continue
            rl.lastUdpTick := now
            if (this._IsPairingRateLimited(ip))
                continue

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
                    DllCall("ws2_32\sendto", "Ptr", this.udpSock, "Ptr", rBuf, "Int", rLen, "Int", 0, "Ptr", fromAddr, "Int", 16, "Int")
                } else {
                    this._RecordPairingFailure(ip)
                }
            }
        }
    }

    _OnTcpMessage(wParam, lParam, msg, hwnd) {
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
                    DllCall("ws2_32\WSAAsyncSelect", "Ptr", clientSock, "Ptr", this.hwnd, "UInt", this.wmTcp, "Int", 0x23, "Int")
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
                body := '{"ok":true,"hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '","bridgePort":' this.boundTcpPort ',"obsPort":4455,"routingMode":' mode '}'
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
        rnd := GenerateRandomBytes(16)
        rndHex := ""
        Loop 16
            rndHex .= Format("{:02x}", NumGet(rnd, A_Index - 1, "UChar"))
        sessionToken := HashSHA256_Hex(hostCode ":" devId ":" rndHex ":" A_TickCount)

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
            connected: false
        }

        endpoints := GetLocalNetworkEndpoints()
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

        resp := '{'
            . '"ok":true,'
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
            this._QueueWsFrame(c, 0x1, '{"type":"auth_ok","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '"}')
            this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
        }

        if (c.recvLen > 0)
            this._DrainWsFrames(c)
    }

    _TryAuthenticateWsClient(c, token, code, devId, devName, plat) {
        if (this._IsPairingRateLimited(c.ip))
            return false

        matched := false
        matchedDevId := ""
        if (token != "" && this.validTokens.Has(token)) {
            matched := true
            matchedDevId := this.validTokens[token]
        } else if (code != "") {
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
        finalName := (devName != "") ? devName : (this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].deviceName : "Smart Board")
        finalPlat := (plat != "") ? plat : (this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].platform : "Remote")

        c.authenticated := true
        c.deviceId := finalDevId
        c.deviceName := finalName
        c.platform := finalPlat

        tokToKeep := (token != "") ? token : (this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].token : "")
        this.pairedDevices[finalDevId] := {
            deviceId: finalDevId,
            deviceName: finalName,
            platform: finalPlat,
            ip: c.ip,
            transport: "Bridge WS",
            token: tokToKeep,
            pairedAt: this.pairedDevices.Has(finalDevId) ? this.pairedDevices[finalDevId].pairedAt : FormatTime(, "HH:mm:ss"),
            lastSeenTick: A_TickCount,
            connected: true
        }
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
            this._QueueWsFrame(c, 0x1, '{"type":"auth_ok","hostName":"' _HB_JsonEscape(A_ComputerName) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '"}')
            this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
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
            case "sync_req":
                this._QueueWsFrame(c, 0x1, this._BuildMuteStateJson())
            case "ping":
                isMutedStr := this.state.isMuted ? "true" : "false"
                this._QueueWsFrame(c, 0x1, '{"type":"pong","isMuted":' isMutedStr ',"timestamp":' A_TickCount '}')
            case "unpair":
                if (c.deviceId != "" && this.pairedDevices.Has(c.deviceId)) {
                    tok := this.pairedDevices[c.deviceId].token
                    if (tok != "" && this.validTokens.Has(tok))
                        this.validTokens.Delete(tok)
                    this.pairedDevices.Delete(c.deviceId)
                }
                this._CloseClient(c)
        }
    }

    _BuildMuteStateJson() {
        isMutedStr := (this.state.HasOwnProp("isMuted") && this.state.isMuted) ? "true" : "false"
        mode := this.cfg.HasOwnProp("AudioRoutingMode") ? this.cfg.AudioRoutingMode : 0
        micName := this.cfg.HasOwnProp("targetMicName") ? this.cfg.targetMicName : "Mic/Aux"
        confApp := this.cfg.HasOwnProp("ConferencingApp") ? this.cfg.ConferencingApp : "Zoom"
        return '{"type":"mute_state","isMuted":' isMutedStr ',"routingMode":' mode ',"targetMicName":"' _HB_JsonEscape(micName) '","conferencingApp":"' _HB_JsonEscape(confApp) '","version":"' _HB_JsonEscape(UIConstants.APP_VERSION) '","timestamp":' A_TickCount '}'
    }
}

StartHostCompanionBridge(cfg, state, tcpPort := 4456, udpPort := -1) {
    global g_HostCompanionBridge
    StopHostCompanionBridge()
    bridge := HostCompanionBridge()
    if (bridge.Start(cfg, state, tcpPort, udpPort)) {
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

RotateHostSessionPairingCode(cfg) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.RotateSessionCode()
    newCode := GenerateSessionPairingCode()
    cfg.SessionPairingCode := newCode
    return newCode
}

HostBridgeBroadcastMuteState(cfg, state) {
    global g_HostCompanionBridge
    if (IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running)
        return g_HostCompanionBridge.BroadcastMuteState(cfg, state)
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
            connectedCount: g_HostCompanionBridge.GetConnectedClientCount(),
            devices: g_HostCompanionBridge.GetDeviceList()
        }
    }
    return {
        running: false,
        tcpPort: 0,
        udpPort: 0,
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

BuildHostPairingUri(cfg, candidateIps := "") {
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
    bridgePort := (IsObject(cfg) && cfg.HasOwnProp("BridgePort")) ? cfg.BridgePort : 4456
    obsPw := (IsObject(cfg) && cfg.HasOwnProp("obsPassword")) ? cfg.obsPassword : ""
    sessCode := (IsObject(cfg) && cfg.HasOwnProp("SessionPairingCode")) ? cfg.SessionPairingCode : ""
    micName := (IsObject(cfg) && cfg.HasOwnProp("targetMicName")) ? cfg.targetMicName : "Mic/Aux"
    netMode := (IsObject(cfg) && cfg.HasOwnProp("RemoteNetworkMode") && cfg.RemoteNetworkMode = "Internet") ? "internet" : "lan"
    rc := (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode")) ? cfg.InternetPairingCode : ""

    uri := "presentersync://connect?hosts=" UriEncodeComponent(hostStr)
        . "&port=" obsPort
        . "&bp=" bridgePort
        . "&code=" UriEncodeComponent(sessCode)
        . "&mic=" UriEncodeComponent(micName)
        . "&mode=" netMode
    if (obsPw != "")
        uri .= "&pw=" UriEncodeComponent(obsPw)
    if (rc != "")
        uri .= "&rc=" UriEncodeComponent(rc)
    return uri
}
