; ==============================================================================
; Library: RemoteBridgeClient.ahk
; Description: Windows Remote Companion multi-instance CLI, HostCompanionBridge
;              UDP discovery, HTTP /pair client & RFC6455 /ws message helpers.
;              Mirrors Android HostBridgeClient/SessionPairingClient semantics.
; ==============================================================================

#DllLoad ws2_32.dll

class RemoteBridgeConstants {
    static PONG_TIMEOUT_MS := 2500
    static WAKE_STALENESS_MS := 25000
}

MarkRemoteRxActivity(state, nowTick := "") {
    if (!IsObject(state))
        return -1
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    state.lastRxTick := t
    state.rxSeq := state.HasOwnProp("rxSeq") ? (Integer(state.rxSeq) + 1) : 1
    return state.lastRxTick
}

ShouldForceWakeReconnect(state, nowTick := "", staleMs := "") {
    if (!IsObject(state))
        return false
    if (!state.HasOwnProp("obsConnected") || !state.obsConnected)
        return true
    if (!state.HasOwnProp("lastRxTick") || state.lastRxTick = "" || Integer(state.lastRxTick) < 0)
        return false
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    limit := (staleMs != "") ? Integer(staleMs) : RemoteBridgeConstants.WAKE_STALENESS_MS
    return (t - Integer(state.lastRxTick)) > limit
}

IsPongWatchdogExpired(state, pingRxSeq, pingRxTick) {
    if (!IsObject(state) || !state.HasOwnProp("obsConnected") || !state.obsConnected)
        return false
    curSeq := state.HasOwnProp("rxSeq") ? Integer(state.rxSeq) : 0
    curRx := (state.HasOwnProp("lastRxTick") && state.lastRxTick != "") ? Integer(state.lastRxTick) : -1
    return (curSeq <= Integer(pingRxSeq) && curRx <= Integer(pingRxTick))
}

ParseRemoteCliArgs(args) {
    out := { configPath: "", instanceName: "", pairingUri: "", cleanupOldExe: "" }
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
        if ((low = "--cleanup-old-exe" || low = "-cleanup-old-exe") && i < args.Length) {
            out.cleanupOldExe := Trim(String(args[i + 1]))
            i += 2
            continue
        }
        if (RegExMatch(arg, "i)^--?cleanup-old-exe=(.+)$", &mOld)) {
            out.cleanupOldExe := Trim(mOld[1])
            i += 1
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
    bPortVal := params.Has("bp") ? params["bp"] : (params.Has("bridgeport") ? params["bridgeport"] : "4456")
    codeVal := params.Has("code") ? params["code"] : (params.Has("session") ? params["session"] : "")
    inetCode := params.Has("rc") ? params["rc"] : (params.Has("pair") ? params["pair"] : (params.Has("internet") ? params["internet"] : (params.Has("internetcode") ? params["internetcode"] : "")))
    presetVal := params.Has("preset") ? Trim(params["preset"]) : ""
    clhVal := params.Has("clh") ? Trim(params["clh"]) : (params.Has("livehex") ? Trim(params["livehex"]) : "")
    cmhVal := params.Has("cmh") ? Trim(params["cmh"]) : (params.Has("mutedhex") ? Trim(params["mutedhex"]) : "")

    return {
        networkMode: (modeRaw = "internet" || modeRaw = "wan") ? "Internet" : "LAN",
        hostAddress: hostVal,
        hostPort: (IsInteger(portVal) && Integer(portVal) >= 1 && Integer(portVal) <= 65535) ? String(Integer(portVal)) : "4455",
        bridgePort: (IsInteger(bPortVal) && Integer(bPortVal) >= 1 && Integer(bPortVal) <= 65535) ? String(Integer(bPortVal)) : "4456",
        sessionCode: codeVal,
        obsPassword: params.Has("pw") ? params["pw"] : "",
        targetMicName: params.Has("mic") && params["mic"] != "" ? params["mic"] : "Mic/Aux",
        internetPairingCode: inetCode,
        hostUuid: params.Has("uuid") ? Trim(params["uuid"]) : "",
        hudColorPreset: presetVal,
        customLiveHex: clhVal,
        customMutedHex: cmhVal
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
                    senderIp := NumGet(srcAddr, 4, "UChar") "." NumGet(srcAddr, 5, "UChar") "." NumGet(srcAddr, 6, "UChar") "." NumGet(srcAddr, 7, "UChar")
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

ParsePublicDiscoveryBeaconJson(rawJson, senderIp := "") {
    proto := _RBC_JsonGetStr(rawJson, "proto")
    uuid := Trim(_RBC_JsonGetStr(rawJson, "hostUuid"))
    devName := Trim(_RBC_JsonGetStr(rawJson, "deviceName"))
    bPort := _RBC_JsonGetInt(rawJson, "bridgePort", 0)
    oPort := _RBC_JsonGetInt(rawJson, "obsPort", 4455)
    cleanIp := Trim(String(senderIp))
    if (proto != "PS_DISCOVER_V1" || uuid = "" || bPort < 1 || bPort > 65535 || cleanIp = "")
        return ""
    if (devName = "")
        devName := cleanIp
    return {
        ok: true,
        proto: proto,
        hostUuid: uuid,
        deviceName: devName,
        senderIp: cleanIp,
        bridgePort: String(bPort),
        obsPort: String((oPort >= 1 && oPort <= 65535) ? oPort : 4455),
        networkMode: _RBC_JsonGetStr(rawJson, "networkMode"),
        audioRoutingMode: _RBC_JsonGetInt(rawJson, "audioRoutingMode", 1),
        version: _RBC_JsonGetStr(rawJson, "version")
    }
}

DiscoverPublicHostsUdp(discoverPort := 4457, timeoutMs := 650, extraTargets := "") {
    results := []
    if (!IsInteger(discoverPort) || Integer(discoverPort) < 1 || Integer(discoverPort) > 65535)
        return results

    wsaBuf := Buffer(408, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaBuf.Ptr, "Int") != 0)
        return results

    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "UPtr")
    if (sock = -1 || sock = 0xFFFFFFFFFFFFFFFF)
        return results

    seen := Map()
    try {
        bBroadcast := Buffer(4, 0)
        NumPut("Int", 1, bBroadcast, 0)
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x0020, "Ptr", bBroadcast.Ptr, "Int", 4, "Int")

        nonBlk := Buffer(4, 0)
        NumPut("UInt", 1, nonBlk, 0)
        DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int")

        bindAddr := Buffer(16, 0)
        NumPut("Short", 2, bindAddr, 0)
        DllCall("ws2_32\bind", "Ptr", sock, "Ptr", bindAddr.Ptr, "Int", 16, "Int")

        pktStr := "PS_DISCOVER_V1"
        pktBytes := Buffer(StrPut(pktStr, "UTF-8"), 0)
        nBytes := StrPut(pktStr, pktBytes, "UTF-8") - 1

        targets := ["255.255.255.255", "127.0.0.1"]
        if IsObject(extraTargets) {
            for _, t in extraTargets {
                ts := Trim(String(t))
                if (ts != "")
                    targets.Push(ts)
            }
        }
        portNet := DllCall("ws2_32\htons", "UShort", Integer(discoverPort), "UShort")
        for _, dstIp in targets {
            dstAddr := Buffer(16, 0)
            NumPut("Short", 2, dstAddr, 0)
            NumPut("UShort", portNet, dstAddr, 2)
            NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", dstIp, "UInt"), dstAddr, 4)
            DllCall("ws2_32\sendto", "Ptr", sock, "Ptr", pktBytes.Ptr, "Int", nBytes, "Int", 0, "Ptr", dstAddr.Ptr, "Int", 16, "Int")
        }

        deadline := A_TickCount + Max(120, timeoutMs)
        rxBuf := Buffer(2048, 0)
        srcAddr := Buffer(16, 0)
        srcLen := Buffer(4, 0)
        while (A_TickCount <= deadline) {
            NumPut("Int", 16, srcLen, 0)
            rx := DllCall("ws2_32\recvfrom", "Ptr", sock, "Ptr", rxBuf.Ptr, "Int", 2047, "Int", 0, "Ptr", srcAddr.Ptr, "Ptr", srcLen.Ptr, "Int")
            if (rx > 0) {
                NumPut("UChar", 0, rxBuf, rx)
                text := StrGet(rxBuf, rx, "UTF-8")
                senderIp := NumGet(srcAddr, 4, "UChar") "." NumGet(srcAddr, 5, "UChar") "." NumGet(srcAddr, 6, "UChar") "." NumGet(srcAddr, 7, "UChar")
                parsed := ParsePublicDiscoveryBeaconJson(text, senderIp)
                if IsObject(parsed) {
                    key := StrLower(parsed.hostUuid)
                    if (!seen.Has(key)) {
                        seen[key] := true
                        results.Push(parsed)
                    }
                }
            } else {
                Sleep(20)
            }
        }
    } finally {
        DllCall("ws2_32\closesocket", "Ptr", sock)
    }
    return results
}

FollowPairedHostIpShift(cfg, beacons) {
    if (!IsObject(cfg) || !IsObject(beacons) || !cfg.HasOwnProp("PairedHostUuid"))
        return { shifted: false, newIp: "", hostsCsv: "" }
    targetUuid := StrLower(Trim(cfg.PairedHostUuid))
    if (targetUuid = "")
        return { shifted: false, newIp: "", hostsCsv: "" }

    matched := ""
    for _, b in beacons {
        if (IsObject(b) && b.HasOwnProp("hostUuid") && StrLower(Trim(b.hostUuid)) == targetUuid && Trim(b.senderIp) != "") {
            matched := b
            break
        }
    }
    if (!IsObject(matched))
        return { shifted: false, newIp: "", hostsCsv: "" }

    newIp := Trim(matched.senderIp)
    newBPort := (matched.HasOwnProp("bridgePort") && IsInteger(matched.bridgePort)) ? String(Integer(matched.bridgePort)) : (cfg.HasOwnProp("BridgePort") ? cfg.BridgePort : "4456")
    curEps := ParseCandidateEndpoints(cfg.HasOwnProp("HostAddress") ? cfg.HostAddress : "", cfg.HasOwnProp("HostPort") ? cfg.HostPort : "4455")
    curFirstHost := (curEps.Length >= 1) ? Trim(curEps[1].host) : ""
    curBPort := cfg.HasOwnProp("BridgePort") ? String(cfg.BridgePort) : "4456"
    if (StrLower(curFirstHost) == StrLower(newIp) && curBPort == newBPort)
        return { shifted: false, newIp: newIp, hostsCsv: cfg.HostAddress }

    ordered := [newIp]
    seen := Map(StrLower(newIp), true)
    for _, ep in curEps {
        hLow := StrLower(Trim(ep.host))
        if (hLow != "" && !seen.Has(hLow) && ordered.Length < 4) {
            seen[hLow] := true
            ordered.Push(Trim(ep.host))
        }
    }
    csv := ""
    for idx, item in ordered
        csv .= (idx > 1 ? ", " : "") item

    cfg.HostAddress := csv
    cfg.BridgePort := newBPort
    if (cfg.HasMethod("Write")) {
        try cfg.Write("Connection", "HostAddress", csv)
        try cfg.Write("Connection", "BridgePort", newBPort)
    }
    return { shifted: true, newIp: newIp, hostsCsv: csv, bridgePort: newBPort }
}

ProbeHostBridgeHealth(host, bridgePort, expectedUuid := "", timeoutMs := 750) {
    cleanHost := Trim(String(host))
    bPort := (IsInteger(bridgePort) && Integer(bridgePort) >= 1 && Integer(bridgePort) <= 65535) ? String(Integer(bridgePort)) : "4456"
    if (cleanHost = "")
        return { ok: false }
    if (IsLoopbackHost(cleanHost) && !IsLocalTcpPortListening(bPort))
        return { ok: false }
    url := "http://" cleanHost ":" bPort "/health"
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(250, 450, 450, Max(350, timeoutMs))
        whr.Open("GET", url, true)
        whr.Send()
        deadline := A_TickCount + Max(350, timeoutMs)
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
            return { ok: false }
        }
        if (Integer(whr.Status) != 200)
            return { ok: false }
        body := String(whr.ResponseText)
        if (!_RBC_JsonGetBool(body, "ok", false))
            return { ok: false }
        gotUuid := Trim(_RBC_JsonGetStr(body, "hostUuid"))
        if (expectedUuid != "" && gotUuid != "" && StrLower(gotUuid) != StrLower(Trim(expectedUuid)))
            return { ok: false }
        return {
            ok: true,
            host: cleanHost,
            bridgePort: bPort,
            hostUuid: gotUuid,
            hostName: _RBC_JsonGetStr(body, "hostName")
        }
    } catch {
        return { ok: false }
    }
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
                hostUuid: _RBC_JsonGetStr(body, "hostUuid"),
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

BuildRemoteBridgeDeckJson(cfg, actionType) {
    devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    return '{"type":"' _RBC_JsonEscape(actionType) '","deviceId":"' _RBC_JsonEscape(devId) '","source":"tray"}'
}

BuildRemoteBridgeSceneJson(cfg, sceneName) {
    devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    return '{"type":"switch_scene","sceneName":"' _RBC_JsonEscape(sceneName) '","deviceId":"' _RBC_JsonEscape(devId) '","source":"tray"}'
}

BuildRemoteBridgeTimerJson(cfg, action, durationSec := 0) {
    devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    return '{"type":"' _RBC_JsonEscape(action) '","durationSec":' Integer(durationSec) ',"deviceId":"' _RBC_JsonEscape(devId) '","source":"tray"}'
}

BuildRemoteBridgeNudgeJson(cfg, message, sender := "", accentHex := "F59E0B") {
    devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
    snd := (Trim(String(sender)) != "") ? Trim(String(sender)) : GetRemoteDisplayDeviceName(cfg)
    return '{"type":"stage_nudge","message":"' _RBC_JsonEscape(message) '","sender":"' _RBC_JsonEscape(snd) '","accentHex":"' _RBC_JsonEscape(accentHex) '","deviceId":"' _RBC_JsonEscape(devId) '"}'
}

ParseHostBridgeWsEvent(rawText) {
    t := _RBC_JsonGetStr(rawText, "type")
    if (t = "")
        return ""
    reasonStr := _RBC_JsonGetStr(rawText, "reason")
    if (reasonStr = "")
        reasonStr := _RBC_JsonGetStr(rawText, "error")
    return {
        kind: t,
        hasMuted: _RBC_JsonHasKey(rawText, "isMuted"),
        isMuted: _RBC_JsonGetBool(rawText, "isMuted", false),
        routingMode: _RBC_JsonGetInt(rawText, "routingMode", 1),
        targetMicName: _RBC_JsonGetStr(rawText, "targetMicName"),
        recState: _RBC_JsonGetInt(rawText, "recState", 0),
        recSeconds: _RBC_JsonGetInt(rawText, "recSeconds", 0),
        streamDropWarn: _RBC_JsonGetBool(rawText, "streamDropWarn", false),
        voiceWhileMuted: _RBC_JsonGetBool(rawText, "voiceWhileMuted", false),
        activeScene: _RBC_JsonGetStr(rawText, "activeScene"),
        scenes: _RBC_JsonGetStrArray(rawText, "scenes"),
        isStandby: _RBC_JsonGetBool(rawText, "isStandby", false),
        standbyScene: _RBC_JsonGetStr(rawText, "standbyScene"),
        timerState: _RBC_JsonGetStr(rawText, "timerState"),
        timerRemainingSec: _RBC_JsonGetInt(rawText, "timerRemainingSec", 600),
        timerPresetSec: _RBC_JsonGetInt(rawText, "timerPresetSec", 600),
        message: _RBC_JsonGetStr(rawText, "message"),
        sender: _RBC_JsonGetStr(rawText, "sender"),
        accentHex: _RBC_JsonGetStr(rawText, "accentHex"),
        hostUuid: _RBC_JsonGetStr(rawText, "hostUuid"),
        hostName: _RBC_JsonGetStr(rawText, "hostName"),
        sessionToken: _RBC_JsonGetStr(rawText, "sessionToken"),
        reason: reasonStr,
        action: _RBC_JsonGetStr(rawText, "action"),
        ok: _RBC_JsonGetBool(rawText, "ok", false)
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
    if (pairRes.HasOwnProp("hostUuid") && pairRes.hostUuid != "")
        cfg.PairedHostUuid := pairRes.hostUuid
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
    if (cfg.HasOwnProp("PairedHostUuid"))
        cfg.Write("Connection", "PairedHostUuid", cfg.PairedHostUuid)
    cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
    cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
    cfg.Write("Connection", "DeviceId", cfg.DeviceId)
    if (cfg.HasOwnProp("InstanceName") && cfg.InstanceName != "")
        cfg.Write("Connection", "InstanceName", cfg.InstanceName)
    cfg.WriteBool("Settings", "FirstRun", cfg.FirstRun)
}

GetDefaultRemoteShortcutFilename(instanceName := "") {
    clean := Trim(String(instanceName))
    if (clean = "")
        return "PresenterSync Remote.lnk"
    return "PresenterSync Remote (" SanitizeInstanceFileSlug(clean) ").lnk"
}

BuildRemoteShortcutLaunchSpec(instanceName := "", configPath := "") {
    inst := RegExReplace(Trim(String(instanceName)), '["\r\n\t]', "")
    cfgP := RegExReplace(Trim(String(configPath)), '["\r\n\t]', "")
    targetExe := A_IsCompiled ? A_ScriptFullPath : A_AhkPath

    args := ""
    if (!A_IsCompiled)
        args .= '"' A_ScriptFullPath '" '
    if (inst != "")
        args .= '-Instance "' inst '" '
    if (cfgP != "")
        args .= '-Config "' cfgP '" '

    iconPath := ""
    if (A_IsCompiled) {
        iconPath := A_ScriptFullPath
    } else if FileExist(A_ScriptDir "\assets\PresenterSyncRemote.ico") {
        iconPath := A_ScriptDir "\assets\PresenterSyncRemote.ico"
    } else if FileExist(A_ScriptDir "\..\assets\PresenterSyncRemote.ico") {
        iconPath := A_ScriptDir "\..\assets\PresenterSyncRemote.ico"
    }

    return {
        target: targetExe,
        args: Trim(args),
        workingDir: A_ScriptDir,
        icon: iconPath,
        instanceName: inst,
        configPath: cfgP
    }
}

CreateRemoteInstanceDesktopShortcut(cfg, instanceName := "", targetDir := "", shortcutName := "", includeConfigPath := false) {
    inst := Trim(String(instanceName))
    if (inst = "" && IsObject(cfg) && cfg.HasOwnProp("InstanceName"))
        inst := Trim(String(cfg.InstanceName))

    outDir := (Trim(String(targetDir)) != "") ? RTrim(Trim(String(targetDir)), "\/") : A_Desktop
    rawName := Trim(String(shortcutName))
    if (rawName != "") {
        lnkBase := RegExReplace(rawName, '[\\/:*?"<>|\r\n\t]', "_")
        lnkBase := RegExReplace(lnkBase, "i)\.lnk$", "")
    } else {
        lnkBase := RegExReplace(GetDefaultRemoteShortcutFilename(inst), "i)\.lnk$", "")
    }
    if (lnkBase = "")
        lnkBase := "PresenterSync Remote"
    outPath := outDir "\" lnkBase ".lnk"

    cfgPathArg := (includeConfigPath && IsObject(cfg) && cfg.HasOwnProp("ConfigFile")) ? cfg.ConfigFile : ""
    spec := BuildRemoteShortcutLaunchSpec(inst, cfgPathArg)
    desc := "PresenterSync Remote" (inst != "" ? " [" inst "]" : "") " Companion"

    try {
        if (outDir != "" && !DirExist(outDir))
            DirCreate(outDir)
        FileCreateShortcut(spec.target, outPath, spec.workingDir, spec.args, desc, spec.icon)
    } catch as e {
        return {ok: false, lnkPath: outPath, target: spec.target, args: spec.args, workingDir: spec.workingDir, desc: desc, icon: spec.icon, instanceName: inst, error: e.Message}
    }

    return {
        ok: (FileExist(outPath) != ""),
        lnkPath: outPath,
        target: spec.target,
        args: spec.args,
        workingDir: spec.workingDir,
        desc: desc,
        icon: spec.icon,
        instanceName: inst,
        error: (FileExist(outPath) != "") ? "" : "Shortcut file was not created."
    }
}

