; ==============================================================================
; Library: RemoteBridgeClient.ahk
; Description: Windows Remote Companion multi-instance CLI, HostCompanionBridge
;              UDP discovery, HTTP /pair client & RFC6455 /ws message helpers.
;              Mirrors Android HostBridgeClient/SessionPairingClient semantics.
; ==============================================================================

ParseRemoteCliArgs(args) {
    out := { configPath: "", instanceName: "", pairingUri: "" }
    if (!IsObject(args))
        return out

    i := 1
    while (i <= args.Length) {
        arg := String(args[i])
        low := StrLower(arg)
        if ((low = "-config" || low = "--config") && i < args.Length) {
            out.configPath := Trim(String(args[i + 1]))
            i += 2
            continue
        }
        if (RegExMatch(arg, "i)^--?config=(.+)$", &mCfg)) {
            out.configPath := Trim(mCfg[1])
            i += 1
            continue
        }
        if ((low = "-instance" || low = "--instance") && i < args.Length) {
            out.instanceName := Trim(String(args[i + 1]))
            i += 2
            continue
        }
        if (RegExMatch(arg, "i)^--?instance=(.+)$", &mInst)) {
            out.instanceName := Trim(mInst[1])
            i += 1
            continue
        }
        if ((low = "-uri" || low = "--uri") && i < args.Length) {
            out.pairingUri := Trim(String(args[i + 1]))
            i += 2
            continue
        }
        if (InStr(low, "presentersync://") = 1) {
            out.pairingUri := arg
        }
        i += 1
    }
    return out
}

SanitizeInstanceFileSlug(name) {
    cleaned := RegExReplace(Trim(String(name)), "[^A-Za-z0-9_-]", "_")
    return (cleaned != "") ? cleaned : "default"
}

GenerateRemoteDeviceId(prefix := "win") {
    buf := Buffer(6, 0)
    ok := false
    try {
        status := DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", buf.Ptr, "UInt", 6, "UInt", 2, "Int") ; BCRYPT_USE_SYSTEM_PREFERRED_RNG
        if (status == 0)
            ok := true
    } catch {
        ok := false
    }
    if (!ok) {
        Loop 6 {
            NumPut("UChar", Random(0, 255), buf, A_Index - 1)
        }
    }
    hex := ""
    Loop 6 {
        hex .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    }
    return prefix "-" hex
}

AcquireRemoteInstanceMutex(instanceName := "") {
    slug := (Trim(instanceName) != "") ? SanitizeInstanceFileSlug(instanceName) : "Default"
    mutexName := "Local\PresenterSync_Remote_" slug
    hMutex := DllCall("kernel32\CreateMutexW", "Ptr", 0, "Int", 1, "WStr", mutexName, "Ptr")
    err := A_LastError
    return {
        handle: hMutex,
        name: mutexName,
        alreadyExists: (hMutex != 0 && err == 183) ; ERROR_ALREADY_EXISTS
    }
}

ReleaseRemoteInstanceMutex(mutexObj) {
    if (IsObject(mutexObj) && mutexObj.HasOwnProp("handle") && mutexObj.handle) {
        try DllCall("kernel32\CloseHandle", "Ptr", mutexObj.handle)
        mutexObj.handle := 0
    }
}

_RBC_JsonEscape(str) {
    s := StrReplace(String(str), "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`b", "\b")
    s := StrReplace(s, "`f", "\f")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

_RBC_UrlDecode(str) {
    s := StrReplace(String(str), "+", " ")
    out := ""
    i := 1
    len := StrLen(s)
    while (i <= len) {
        ch := SubStr(s, i, 1)
        if (ch = "%" && i + 2 <= len) {
            hex := SubStr(s, i + 1, 2)
            if RegExMatch(hex, "^[0-9A-Fa-f]{2}$") {
                ; Collect contiguous %XX UTF-8 sequence if multi-byte
                bytes := []
                while (i + 2 <= len && SubStr(s, i, 1) = "%" && RegExMatch(SubStr(s, i + 1, 2), "^[0-9A-Fa-f]{2}$")) {
                    bytes.Push(Integer("0x" SubStr(s, i + 1, 2)))
                    i += 3
                }
                buf := Buffer(bytes.Length + 1, 0)
                for idx, b in bytes
                    NumPut("UChar", b, buf, idx - 1)
                out .= StrGet(buf, bytes.Length, "UTF-8")
                continue
            }
        }
        out .= ch
        i += 1
    }
    return out
}

ParseRemotePairingUri(rawUri) {
    s := Trim(String(rawUri))
    if (!RegExMatch(s, "i)^presentersync://connect/?(?:\?(.*))?$", &m))
        return ""

    params := Map()
    q := (m.Count >= 1) ? m[1] : ""
    if (q != "") {
        for _, pair in StrSplit(q, "&") {
            if (pair = "")
                continue
            eq := InStr(pair, "=")
            if (eq > 0) {
                k := StrLower(Trim(_RBC_UrlDecode(SubStr(pair, 1, eq - 1))))
                v := Trim(_RBC_UrlDecode(SubStr(pair, eq + 1)))
            } else {
                k := StrLower(Trim(_RBC_UrlDecode(pair)))
                v := ""
            }
            if (k != "")
                params[k] := v
        }
    }

    modeRaw := params.Has("mode") ? StrLower(params["mode"]) : "lan"
    hostVal := params.Has("hosts") ? params["hosts"] : (params.Has("host") ? params["host"] : "")
    portVal := params.Has("port") ? params["port"] : "4455"
    bPortVal := params.Has("bridgeport") ? params["bridgeport"] : "4456"
    codeVal := params.Has("code") ? params["code"] : (params.Has("session") ? params["session"] : "")
    inetCode := params.Has("pair") ? params["pair"] : (params.Has("internet") ? params["internet"] : (params.Has("internetcode") ? params["internetcode"] : ""))

    return {
        networkMode: (modeRaw = "internet" || modeRaw = "wan") ? "Internet" : "LAN",
        hostAddress: hostVal,
        hostPort: (IsInteger(portVal) && Integer(portVal) >= 1 && Integer(portVal) <= 65535) ? String(Integer(portVal)) : "4455",
        bridgePort: (IsInteger(bPortVal) && Integer(bPortVal) >= 1 && Integer(bPortVal) <= 65535) ? String(Integer(bPortVal)) : "4456",
        sessionCode: codeVal,
        obsPassword: params.Has("pw") ? params["pw"] : "",
        targetMicName: params.Has("mic") && params["mic"] != "" ? params["mic"] : "Mic/Aux",
        internetPairingCode: inetCode
    }
}

_RBC_JsonGetStr(jsonStr, key) {
    pattern := '"' key '"\s*:\s*"((?:\\.|[^"\\])*)"'
    if (RegExMatch(jsonStr, pattern, &m)) {
        val := m[1]
        val := StrReplace(val, '\"', '"')
        val := StrReplace(val, '\\', '\')
        val := StrReplace(val, '\/', '/')
        val := StrReplace(val, '\n', '`n')
        val := StrReplace(val, '\r', '`r')
        val := StrReplace(val, '\t', '`t')
        return val
    }
    return ""
}

_RBC_JsonGetInt(jsonStr, key, defaultVal := 0) {
    pattern := '"' key '"\s*:\s*(-?\d+)'
    if (RegExMatch(jsonStr, pattern, &m))
        return Integer(m[1])
    return defaultVal
}

_RBC_JsonGetBool(jsonStr, key, defaultVal := false) {
    pattern := '"' key '"\s*:\s*(true|false)'
    if (RegExMatch(jsonStr, pattern, &m))
        return (m[1] = "true")
    return defaultVal
}

_RBC_JsonHasKey(jsonStr, key) {
    return RegExMatch(jsonStr, '"' key '"\s*:') != 0
}

_RBC_JsonGetStrArray(jsonStr, key) {
    out := []
    if (!RegExMatch(jsonStr, '"' key '"\s*:\s*\[([^\]]*)\]', &mArr))
        return out
    inner := mArr[1]
    pos := 1
    while (RegExMatch(inner, '"((?:\\.|[^"\\])*)"', &mItem, pos)) {
        out.Push(StrReplace(mItem[1], '\"', '"'))
        pos := mItem.Pos + mItem.Len
    }
    return out
}

DiscoverHostBridgeUdp(sessionCode, udpPort := 4456, timeoutMs := 450) {
    codeNorm := NormalizePairingCode(sessionCode)
    if (codeNorm = "" || !IsInteger(udpPort) || Integer(udpPort) < 1 || Integer(udpPort) > 65535)
        return ""

    wsaBuf := Buffer(408, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaBuf.Ptr, "Int") != 0)
        return ""

    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "UPtr") ; AF_INET, SOCK_DGRAM, IPPROTO_UDP
    if (sock = -1 || sock = 0xFFFFFFFFFFFFFFFF)
        return ""

    try {
        bBroadcast := Buffer(4, 0)
        NumPut("Int", 1, bBroadcast, 0)
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x0020, "Ptr", bBroadcast.Ptr, "Int", 4, "Int") ; SO_BROADCAST

        nonBlk := Buffer(4, 0)
        NumPut("UInt", 1, nonBlk, 0)
        DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int") ; FIONBIO

        bindAddr := Buffer(16, 0)
        NumPut("Short", 2, bindAddr, 0)
        DllCall("ws2_32\bind", "Ptr", sock, "Ptr", bindAddr.Ptr, "Int", 16, "Int")

        pktStr := "PSYNC_DISCOVER|" codeNorm
        pktBytes := Buffer(StrPut(pktStr, "UTF-8"), 0)
        nBytes := StrPut(pktStr, pktBytes, "UTF-8") - 1

        portNet := DllCall("ws2_32\htons", "UShort", Integer(udpPort), "UShort")
        for _, dstIp in ["255.255.255.255", "127.0.0.1"] {
            dstAddr := Buffer(16, 0)
            NumPut("Short", 2, dstAddr, 0)
            NumPut("UShort", portNet, dstAddr, 2)
            NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", dstIp, "UInt"), dstAddr, 4)
            DllCall("ws2_32\sendto", "Ptr", sock, "Ptr", pktBytes.Ptr, "Int", nBytes, "Int", 0, "Ptr", dstAddr.Ptr, "Int", 16, "Int")
        }

        deadline := A_TickCount + Max(100, timeoutMs)
        rxBuf := Buffer(1024, 0)
        srcAddr := Buffer(16, 0)
        srcLen := Buffer(4, 0)
        while (A_TickCount <= deadline) {
            NumPut("Int", 16, srcLen, 0)
            rx := DllCall("ws2_32\recvfrom", "Ptr", sock, "Ptr", rxBuf.Ptr, "Int", 1023, "Int", 0, "Ptr", srcAddr.Ptr, "Ptr", srcLen.Ptr, "Int")
            if (rx > 0) {
                NumPut("UChar", 0, rxBuf, rx)
                text := StrGet(rxBuf, rx, "UTF-8")
                parts := StrSplit(Trim(text), "|")
                if (parts.Length >= 4 && parts[1] = "PSYNC_OFFER") {
                    ipPtr := DllCall("ws2_32\inet_ntoa", "UInt", NumGet(srcAddr, 4, "UInt"), "Ptr")
                    senderIp := ipPtr ? StrGet(ipPtr, "AStr") : ""
                    return {
                        ok: true,
                        senderIp: senderIp,
                        hostName: parts[2],
                        bridgePort: IsInteger(parts[3]) ? String(Integer(parts[3])) : String(udpPort),
                        obsPort: IsInteger(parts[4]) ? String(Integer(parts[4])) : "4455",
                        version: (parts.Length >= 5) ? parts[5] : "",
                        routingMode: (parts.Length >= 6 && IsInteger(parts[6])) ? Integer(parts[6]) : 1
                    }
                }
            }
            Sleep(25)
        }
    } finally {
        DllCall("ws2_32\closesocket", "Ptr", sock)
    }
    return ""
}

HttpPostBridgePair(host, bridgePort, sessionCode, deviceId, deviceName) {
    cleanHost := Trim(String(host))
    bPort := (IsInteger(bridgePort) && Integer(bridgePort) >= 1 && Integer(bridgePort) <= 65535) ? String(Integer(bridgePort)) : "4456"
    if (cleanHost = "")
        return { ok: false, status: 0, error: "Empty host" }

    ; Avoid 2s WinHTTP stall against closed local loopback ports
    if (IsLoopbackHost(cleanHost) && !IsLocalTcpPortListening(bPort))
        return { ok: false, status: 0, error: "Host Bridge not listening on " cleanHost ":" bPort }

    url := "http://" cleanHost ":" bPort "/pair"
    payload := '{"code":"' _RBC_JsonEscape(sessionCode) '","deviceId":"' _RBC_JsonEscape(deviceId) '","deviceName":"' _RBC_JsonEscape(deviceName) '","platform":"Windows"}'

    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(450, 750, 750, 1400)
        whr.Open("POST", url, true)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.Send(payload)
        deadline := A_TickCount + 1800
        ready := false
        while (A_TickCount <= deadline) {
            if (whr.WaitForResponse(0)) {
                ready := true
                break
            }
            Sleep(15)
        }
        if (!ready) {
            try whr.Abort()
            return { ok: false, status: 0, error: "Request timed out (" cleanHost ":" bPort ")" }
        }
        st := Integer(whr.Status)
        body := String(whr.ResponseText)

        if (st == 200 && _RBC_JsonGetBool(body, "ok", false)) {
            ips := _RBC_JsonGetStrArray(body, "ips")
            return {
                ok: true,
                status: 200,
                host: cleanHost,
                hostName: _RBC_JsonGetStr(body, "hostName"),
                bridgePort: String(_RBC_JsonGetInt(body, "bridgePort", Integer(bPort))),
                obsPort: String(_RBC_JsonGetInt(body, "obsPort", 4455)),
                obsPassword: _RBC_JsonGetStr(body, "obsPassword"),
                targetMicName: _RBC_JsonGetStr(body, "targetMicName"),
                internetPairingCode: _RBC_JsonGetStr(body, "internetPairingCode"),
                sessionToken: _RBC_JsonGetStr(body, "sessionToken"),
                isMuted: _RBC_JsonGetBool(body, "isMuted", false),
                ips: ips,
                error: ""
            }
        }
        errMsg := _RBC_JsonGetStr(body, "error")
        return {
            ok: false,
            status: st,
            error: (errMsg != "" ? errMsg : "HTTP " st)
        }
    } catch as exc {
        return { ok: false, status: 0, error: exc.Message }
    }
}

PairRemoteWithHostBridge(hostsCsv, bridgePort, sessionCode, deviceId, deviceName, enableUdp := true) {
    codeNorm := NormalizePairingCode(sessionCode)
    if (StrLen(codeNorm) < 4)
        return { ok: false, error: "Session Pairing Code must be at least 4 characters (e.g. K7M-9P2)." }

    formattedCode := (StrLen(codeNorm) == 6) ? (SubStr(codeNorm, 1, 3) "-" SubStr(codeNorm, 4, 3)) : Trim(String(sessionCode))
    bPort := (IsInteger(bridgePort) && Integer(bridgePort) >= 1 && Integer(bridgePort) <= 65535) ? String(Integer(bridgePort)) : "4456"

    hostQueue := []
    seen := Map()
    AddUniqueHost(h, pOverride := "") {
        hClean := Trim(String(h))
        if (hClean = "")
            return
        k := StrLower(hClean) ":" (pOverride != "" ? pOverride : bPort)
        if (!seen.Has(k)) {
            seen[k] := true
            hostQueue.Push({ host: hClean, port: (pOverride != "" ? pOverride : bPort) })
        }
    }

    for _, ep in ParseCandidateEndpoints(hostsCsv, bPort) {
        epPort := (ep.port != "4455" && ep.port != "") ? ep.port : bPort
        AddUniqueHost(ep.host, epPort)
    }

    if (enableUdp) {
        udpOffer := DiscoverHostBridgeUdp(formattedCode, Integer(bPort), 450)
        if IsObject(udpOffer) && udpOffer.ok {
            if (udpOffer.senderIp != "")
                AddUniqueHost(udpOffer.senderIp, udpOffer.bridgePort)
            if (udpOffer.hostName != "")
                AddUniqueHost(udpOffer.hostName ".local", udpOffer.bridgePort)
        }
    }

    AddUniqueHost("127.0.0.1", bPort)

    lastErr := "Primary Host Bridge unreachable. Ensure PresenterSync Host is running and firewall allows TCP/UDP " bPort "."
    for _, target in hostQueue {
        res := HttpPostBridgePair(target.host, target.port, formattedCode, deviceId, deviceName)
        if (res.ok) {
            merged := [res.host]
            seenIp := Map(StrLower(res.host), true)
            for _, ip in res.ips {
                if (ip != "" && !seenIp.Has(StrLower(ip))) {
                    seenIp[StrLower(ip)] := true
                    merged.Push(ip)
                }
            }
            for _, ep in ParseCandidateEndpoints(hostsCsv, res.obsPort) {
                if (!seenIp.Has(StrLower(ep.host))) {
                    seenIp[StrLower(ep.host)] := true
                    merged.Push(ep.host)
                }
            }
            csv := ""
            for idx, item in merged
                csv .= (idx > 1 ? ", " : "") item
            res.hostsCsv := csv
            res.sessionCode := formattedCode
            return res
        }
        if (res.status == 401 || res.status == 429) {
            return { ok: false, status: res.status, error: res.error }
        }
        if (res.error != "")
            lastErr := res.error
    }
    return { ok: false, status: 0, error: lastErr }
}

BuildRemoteLanCandidateQueue(cfg) {
    queue := []
    hostStr := (cfg.HasOwnProp("HostAddress")) ? Trim(cfg.HostAddress) : ""
    obsPort := (cfg.HasOwnProp("HostPort") && IsInteger(cfg.HostPort)) ? String(Integer(cfg.HostPort)) : "4455"
    bPort := (cfg.HasOwnProp("BridgePort") && IsInteger(cfg.BridgePort) && Integer(cfg.BridgePort) >= 1 && Integer(cfg.BridgePort) <= 65535) ? String(Integer(cfg.BridgePort)) : "4456"

    endpoints := ParseCandidateEndpoints(hostStr, obsPort)
    hasBridgePairing := (cfg.HasOwnProp("SessionPairingCode") && Trim(cfg.SessionPairingCode) != "")
        || (cfg.HasOwnProp("SessionToken") && Trim(cfg.SessionToken) != "")

    if (hasBridgePairing) {
        bridgeHosts := []
        if (endpoints.Length > 0) {
            for _, ep in endpoints
                bridgeHosts.Push(ep.host)
        } else {
            bridgeHosts.Push("127.0.0.1")
        }
        seenB := Map()
        for _, bh in bridgeHosts {
            kl := StrLower(bh) ":" bPort
            if (seenB.Has(kl))
                continue
            seenB[kl] := true
            queue.Push({
                host: bh,
                port: bPort,
                scheme: "ws",
                path: "/ws",
                url: "ws://" bh ":" bPort "/ws",
                raw: bh ":" bPort " (Bridge)",
                isBridge: true
            })
        }
    }

    for _, ep in endpoints {
        queue.Push({
            host: ep.host,
            port: ep.port,
            scheme: ep.HasOwnProp("scheme") ? ep.scheme : "ws",
            path: "",
            url: "ws://" ep.host ":" ep.port,
            raw: ep.raw,
            isBridge: false
        })
    }
    return queue
}

GetRemoteDisplayDeviceName(cfg) {
    inst := (cfg.HasOwnProp("InstanceName")) ? Trim(cfg.InstanceName) : ""
    if (inst != "" && StrLower(inst) != StrLower(A_ComputerName))
        return A_ComputerName " (" inst ")"
    return A_ComputerName
}

BuildRemoteBridgeAuthJson(cfg) {
    devId := (cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    tok := cfg.HasOwnProp("SessionToken") ? Trim(cfg.SessionToken) : ""
    code := cfg.HasOwnProp("SessionPairingCode") ? Trim(cfg.SessionPairingCode) : ""
    devName := GetRemoteDisplayDeviceName(cfg)
    return '{"type":"auth","token":"' _RBC_JsonEscape(tok) '","code":"' _RBC_JsonEscape(code) '","deviceId":"' _RBC_JsonEscape(devId) '","deviceName":"' _RBC_JsonEscape(devName) '","platform":"Windows"}'
}

BuildRemoteBridgeToggleJson(cfg) {
    devId := (cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    return '{"type":"toggle_mute","deviceId":"' _RBC_JsonEscape(devId) '","source":"clicker"}'
}

BuildRemoteBridgeSetMuteJson(cfg, targetMuted) {
    devId := (cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    return '{"type":"set_mute","isMuted":' (targetMuted ? "true" : "false") ',"deviceId":"' _RBC_JsonEscape(devId) '","source":"hud"}'
}

BuildRemoteBridgePingJson() {
    return '{"type":"ping"}'
}

ParseHostBridgeWsEvent(rawText) {
    t := _RBC_JsonGetStr(rawText, "type")
    if (t = "")
        return ""
    return {
        kind: t,
        hasMuted: _RBC_JsonHasKey(rawText, "isMuted"),
        isMuted: _RBC_JsonGetBool(rawText, "isMuted", false),
        routingMode: _RBC_JsonGetInt(rawText, "routingMode", 1),
        targetMicName: _RBC_JsonGetStr(rawText, "targetMicName"),
        hostName: _RBC_JsonGetStr(rawText, "hostName"),
        reason: _RBC_JsonGetStr(rawText, "reason")
    }
}

ApplyBridgePairResultToConfig(cfg, pairRes) {
    if (!IsObject(cfg) || !IsObject(pairRes) || !pairRes.ok)
        return false
    if (pairRes.HasOwnProp("hostsCsv") && pairRes.hostsCsv != "")
        cfg.HostAddress := pairRes.hostsCsv
    if (pairRes.HasOwnProp("bridgePort") && pairRes.bridgePort != "")
        cfg.BridgePort := pairRes.bridgePort
    if (pairRes.HasOwnProp("obsPort") && pairRes.obsPort != "")
        cfg.HostPort := pairRes.obsPort
    if (pairRes.HasOwnProp("sessionCode") && pairRes.sessionCode != "")
        cfg.SessionPairingCode := pairRes.sessionCode
    if (pairRes.HasOwnProp("sessionToken") && pairRes.sessionToken != "")
        cfg.SessionToken := pairRes.sessionToken
    if (pairRes.HasOwnProp("obsPassword") && pairRes.obsPassword != "")
        cfg.ObsPassword := pairRes.obsPassword
    if (pairRes.HasOwnProp("targetMicName") && pairRes.targetMicName != "")
        cfg.TargetMicName := pairRes.targetMicName
    if (pairRes.HasOwnProp("internetPairingCode") && pairRes.internetPairingCode != "")
        cfg.InternetPairingCode := pairRes.internetPairingCode
    return true
}

SaveRemoteConnectionSettingsToIni(cfg) {
    if (!IsObject(cfg))
        return
    cfg.Write("Connection", "NetworkMode", cfg.NetworkMode)
    cfg.Write("Connection", "InternetPairingCode", cfg.InternetPairingCode)
    cfg.Write("Connection", "HostAddress", cfg.HostAddress)
    cfg.Write("Connection", "HostPort", cfg.HostPort)
    cfg.Write("Connection", "BridgePort", cfg.BridgePort)
    cfg.Write("Connection", "SessionPairingCode", cfg.SessionPairingCode)
    cfg.Write("Connection", "SessionToken", cfg.SessionToken)
    cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
    cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
    cfg.Write("Connection", "DeviceId", cfg.DeviceId)
    if (cfg.HasOwnProp("InstanceName") && cfg.InstanceName != "")
        cfg.Write("Connection", "InstanceName", cfg.InstanceName)
    cfg.WriteBool("Settings", "FirstRun", cfg.FirstRun)
}

