; ==============================================================================
; Library: RemoteBridgeClient.ahk
; Description: Windows Remote Companion multi-instance CLI, HostCompanionBridge
;              UDP discovery, HTTP /pair client & RFC6455 /ws message helpers.
;              Mirrors Android HostBridgeClient/SessionPairingClient semantics.
; ==============================================================================

#DllLoad ws2_32.dll
#Include "%A_LineFile%\..\JsonCodec.ahk"
#Include "%A_LineFile%\..\ConfigStore.ahk"

class RemoteBridgeConstants {
    static BRIDGE_CONNECT_TIMEOUT_MS := 1800
    static BRIDGE_REPROMOTE_INTERVAL_MS := 8000
    static BRIDGE_REPROMOTE_REQUIRED_PROBES := 2
    static HEALTH_PROBE_TIMEOUT_MS := 500
    static PONG_TIMEOUT_MS := 2500
    static WAKE_STALENESS_MS := 25000
}

StepBridgeRepromoteHysteresis(state, healthy, requiredProbes := "") {
    if (!IsObject(state))
        return false
    req := (requiredProbes != "" && IsInteger(requiredProbes))
        ? Max(1, Integer(requiredProbes))
        : RemoteBridgeConstants.BRIDGE_REPROMOTE_REQUIRED_PROBES
    if (!healthy) {
        state._repromoteHealthyStreak := 0
        return false
    }
    streak := (state.HasOwnProp("_repromoteHealthyStreak") && IsInteger(state._repromoteHealthyStreak))
        ? (Integer(state._repromoteHealthyStreak) + 1)
        : 1
    if (streak >= req) {
        state._repromoteHealthyStreak := 0
        return true
    }
    state._repromoteHealthyStreak := streak
    return false
}

GetRemoteBridgeSweepPorts(preferredPort := 4456) {
    pref := 4456
    try pref := Integer(preferredPort)
    if (pref < 1 || pref > 65535)
        pref := 4456
    ports := [pref]
    seen := Map(pref, true)
    if (!seen.Has(4456)) {
        seen[4456] := true
        ports.Push(4456)
    }
    Loop 8 {
        p := 4457 + A_Index ; 4458..4465 (skips UDP discovery :4457)
        if (!seen.Has(p)) {
            seen[p] := true
            ports.Push(p)
        }
    }
    return ports
}

SweepHostBridgeFallbackPort(host, preferredPort := 4456, expectedUuid := "", timeoutMs := 450, probeFn := "") {
    cleanHost := Trim(String(host))
    if (cleanHost = "")
        return { ok: false, port: "", probe: "" }
    prefNum := 4456
    try prefNum := Integer(preferredPort)
    if (prefNum < 1 || prefNum > 65535)
        prefNum := 4456
    ports := (prefNum >= 4456 && prefNum <= 4465) ? GetRemoteBridgeSweepPorts(prefNum) : [prefNum]
    for _, p in ports {
        res := IsObject(probeFn)
            ? probeFn.Call(cleanHost, p, expectedUuid, timeoutMs)
            : ProbeHostBridgeHealth(cleanHost, p, expectedUuid, timeoutMs)
        if (IsObject(res) && res.HasOwnProp("ok") && res.ok)
            return { ok: true, port: String(p), probe: res }
    }
    return { ok: false, port: "", probe: "" }
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
    return JsonCodec.Escape(str)
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

_RBC_UrlEncode(str) {
    s := String(str)
    if (s = "")
        return ""
    buf := Buffer(StrPut(s, "UTF-8") - 1, 0)
    StrPut(s, buf, "UTF-8")
    out := ""
    Loop buf.Size {
        b := NumGet(buf, A_Index - 1, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E)
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}

ParsePairingUri(rawUri) {
    s := Trim(String(rawUri))
    if (!RegExMatch(s, "i)^presentersync://(pair|connect)/?(?:\?(.*))?$", &m))
        return { ok: false, error: "Invalid pairing URI (expected presentersync://pair or presentersync://connect)" }

    params := Map()
    q := (m.Count >= 2) ? m[2] : ""
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

    hostVal := params.Has("host") ? params["host"] : (params.Has("hosts") ? params["hosts"] : "")
    obsPortRaw := params.Has("obsport") ? params["obsport"] : (params.Has("bp") || params.Has("bridgeport") ? (params.Has("port") ? params["port"] : "4455") : "4455")
    bPortRaw := params.Has("bp") ? params["bp"] : (params.Has("bridgeport") ? params["bridgeport"] : (params.Has("port") ? params["port"] : "4456"))
    codeVal := params.Has("code") ? params["code"] : (params.Has("session") ? params["session"] : "")
    obsPassVal := params.Has("obspass") ? params["obspass"] : (params.Has("pw") ? params["pw"] : "")
    wanVal := params.Has("wan") ? params["wan"] : (params.Has("rc") ? params["rc"] : (params.Has("pair") ? params["pair"] : (params.Has("internet") ? params["internet"] : "")))

    if (hostVal = "" && wanVal = "" && codeVal = "")
        return { ok: false, error: "Pairing URI missing host, session code, or WAN code" }

    bPort := (IsInteger(bPortRaw) && Integer(bPortRaw) >= 1 && Integer(bPortRaw) <= 65535) ? String(Integer(bPortRaw)) : "4456"
    oPort := (IsInteger(obsPortRaw) && Integer(obsPortRaw) >= 1 && Integer(obsPortRaw) <= 65535) ? String(Integer(obsPortRaw)) : "4455"
    return {
        ok: true,
        host: hostVal,
        bridgePort: bPort,
        code: codeVal,
        obsPort: oPort,
        obsPass: obsPassVal,
        wanCode: wanVal
    }
}

_RBC_ParseProfileLine(rawVal) {
    params := Map()
    for _, pair in StrSplit(String(rawVal), "&") {
        eq := InStr(pair, "=")
        if (eq > 0) {
            k := StrLower(Trim(_RBC_UrlDecode(SubStr(pair, 1, eq - 1))))
            v := _RBC_UrlDecode(SubStr(pair, eq + 1))
            if (k != "")
                params[k] := v
        }
    }
    rawCode := params.Has("code") ? params["code"] : ""
    rawWan := params.Has("wan") ? params["wan"] : ""
    rawPw := params.Has("pw") ? params["pw"] : ""
    return {
        host: params.Has("host") ? params["host"] : "",
        bridgePort: params.Has("bp") && IsInteger(params["bp"]) ? String(Integer(params["bp"])) : "4456",
        obsPort: params.Has("obsport") && IsInteger(params["obsport"]) ? String(Integer(params["obsport"])) : "4455",
        code: ConfigStore.UnprotectSecret(rawCode, "HostProfile.code"),
        wanCode: ConfigStore.UnprotectSecret(rawWan, "HostProfile.wanCode"),
        obsPass: ConfigStore.UnprotectSecret(rawPw, "HostProfile.obsPass"),
        networkMode: (params.Has("mode") && StrLower(params["mode"]) = "internet") ? "Internet" : "LAN",
        targetMic: params.Has("mic") ? params["mic"] : "",
        relayBaseUrl: params.Has("relay") ? params["relay"] : ""
    }
}

LoadSavedHostProfiles(cfg) {
    profiles := []
    if (!IsObject(cfg) || !cfg.HasOwnProp("ConfigFile") || cfg.ConfigFile = "" || !FileExist(cfg.ConfigFile))
        return profiles
    rawSec := ""
    try rawSec := IniRead(cfg.ConfigFile, "HostProfiles", , "")
    if (Trim(rawSec) = "")
        return profiles
    for _, line in StrSplit(rawSec, "`n", "`r") {
        eq := InStr(line, "=")
        if (eq <= 1)
            continue
        pName := Trim(SubStr(line, 1, eq - 1))
        pVal := SubStr(line, eq + 1)
        if (pName = "")
            continue
        parsed := _RBC_ParseProfileLine(pVal)
        parsed.name := pName
        profiles.Push(parsed)
    }
    return profiles
}

SaveHostProfile(cfg, profileName, data) {
    clean := Trim(String(profileName))
    clean := RegExReplace(clean, "[\r\n=]", "_")
    if (clean = "" || !IsObject(cfg) || !cfg.HasOwnProp("ConfigFile") || cfg.ConfigFile = "" || !IsObject(data))
        return false
    h := data.HasOwnProp("host") ? String(data.host) : ""
    bp := data.HasOwnProp("bridgePort") && IsInteger(data.bridgePort) ? String(Integer(data.bridgePort)) : "4456"
    op := data.HasOwnProp("obsPort") && IsInteger(data.obsPort) ? String(Integer(data.obsPort)) : "4455"
    cd := ConfigStore.ProtectSecret(data.HasOwnProp("code") ? String(data.code) : "")
    wn := ConfigStore.ProtectSecret(data.HasOwnProp("wanCode") ? String(data.wanCode) : "")
    pw := ConfigStore.ProtectSecret(data.HasOwnProp("obsPass") ? String(data.obsPass) : "")
    md := (data.HasOwnProp("networkMode") && StrLower(String(data.networkMode)) = "internet") ? "Internet" : "LAN"
    mc := data.HasOwnProp("targetMic") ? String(data.targetMic) : ""
    rl := data.HasOwnProp("relayBaseUrl") ? String(data.relayBaseUrl) : ""
    enc := "host=" _RBC_UrlEncode(h) "&bp=" bp "&obsport=" op "&code=" _RBC_UrlEncode(cd) "&wan=" _RBC_UrlEncode(wn) "&pw=" _RBC_UrlEncode(pw) "&mode=" md
    if (mc != "")
        enc .= "&mic=" _RBC_UrlEncode(mc)
    if (rl != "")
        enc .= "&relay=" _RBC_UrlEncode(rl)
    try {
        IniWrite(enc, cfg.ConfigFile, "HostProfiles", clean)
        return true
    } catch {
        return false
    }
}

DeleteHostProfile(cfg, profileName) {
    clean := Trim(String(profileName))
    if (clean = "" || !IsObject(cfg) || !cfg.HasOwnProp("ConfigFile") || cfg.ConfigFile = "")
        return false
    try {
        IniDelete(cfg.ConfigFile, "HostProfiles", clean)
        return true
    } catch {
        return false
    }
}

ApplyHostProfile(cfg, state, profileName) {
    clean := Trim(String(profileName))
    if (clean = "" || !IsObject(cfg))
        return false
    target := ""
    for _, prof in LoadSavedHostProfiles(cfg) {
        if (prof.name = clean) {
            target := prof
            break
        }
    }
    if (!IsObject(target))
        return false
    cfg.HostAddress := target.host
    cfg.BridgePort := Integer(target.bridgePort)
    cfg.HostPort := target.obsPort
    cfg.SessionPairingCode := target.code
    cfg.SessionToken := ""
    cfg.PairedHostUuid := ""
    cfg.InternetPairingCode := target.wanCode
    cfg.ObsPassword := target.obsPass
    cfg.NetworkMode := target.networkMode
    if (target.HasOwnProp("targetMic") && target.targetMic != "" && cfg.HasOwnProp("TargetMicName"))
        cfg.TargetMicName := target.targetMic
    if (target.HasOwnProp("relayBaseUrl") && target.relayBaseUrl != "" && cfg.HasOwnProp("RelayBaseUrl"))
        cfg.RelayBaseUrl := IsSet(NormalizeRelayBaseUrl) ? NormalizeRelayBaseUrl(target.relayBaseUrl) : target.relayBaseUrl
    if (cfg.HasMethod("Write")) {
        cfg.Write("Connection", "HostAddress", cfg.HostAddress)
        cfg.Write("Connection", "BridgePort", cfg.BridgePort)
        cfg.Write("Connection", "HostPort", cfg.HostPort)
        cfg.Write("Connection", "SessionPairingCode", cfg.SessionPairingCode)
        cfg.Write("Connection", "SessionToken", "")
        cfg.Write("Connection", "PairedHostUuid", "")
        cfg.Write("Connection", "InternetPairingCode", cfg.InternetPairingCode)
        cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
        cfg.Write("Connection", "NetworkMode", cfg.NetworkMode)
        if (cfg.HasOwnProp("TargetMicName"))
            cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
        if (cfg.HasOwnProp("RelayBaseUrl"))
            cfg.Write("Connection", "RelayBaseUrl", cfg.RelayBaseUrl)
    }
    if (IsObject(state)) {
        HandleRemotePowerBroadcast(0x7, state)
        if (state.HasMethod("NotifyTrayStatus"))
            try state.NotifyTrayStatus()
    }
    return true
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
    return JsonCodec.GetStr(jsonStr, key, "")
}

_RBC_JsonGetInt(jsonStr, key, defaultVal := 0) {
    return JsonCodec.GetInt(jsonStr, key, defaultVal)
}

_RBC_JsonGetBool(jsonStr, key, defaultVal := false) {
    return JsonCodec.GetBool(jsonStr, key, defaultVal)
}

_RBC_JsonHasKey(jsonStr, key) {
    return JsonCodec.HasKey(jsonStr, key)
}

_RBC_JsonGetStrArray(jsonStr, key) {
    return JsonCodec.GetStrArray(jsonStr, key)
}

_RBC_OpenBroadcastUdpSocket() {
    wsaBuf := Buffer(408, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaBuf.Ptr, "Int") != 0)
        return 0
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "UPtr") ; AF_INET, SOCK_DGRAM, IPPROTO_UDP
    if (sock = -1 || sock = 0xFFFFFFFFFFFFFFFF || sock = 0xFFFFFFFF) {
        try DllCall("ws2_32\WSACleanup")
        return 0
    }
    try {
        bBroadcast := Buffer(4, 0)
        NumPut("Int", 1, bBroadcast, 0)
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x0020, "Ptr", bBroadcast.Ptr, "Int", 4, "Int") ; SO_BROADCAST
        nonBlk := Buffer(4, 0)
        NumPut("UInt", 1, nonBlk, 0)
        DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int") ; FIONBIO
        bindAddr := Buffer(16, 0)
        NumPut("Short", 2, bindAddr, 0)
        if (DllCall("ws2_32\bind", "Ptr", sock, "Ptr", bindAddr.Ptr, "Int", 16, "Int") != 0) {
            _RBC_CloseUdpSocket(sock)
            return 0
        }
        return sock
    } catch {
        _RBC_CloseUdpSocket(sock)
        return 0
    }
}

_RBC_CloseUdpSocket(sock) {
    if (sock != 0 && sock != -1 && sock != 0xFFFFFFFFFFFFFFFF && sock != 0xFFFFFFFF)
        try DllCall("ws2_32\closesocket", "Ptr", sock)
    try DllCall("ws2_32\WSACleanup")
}

_RBC_SendUdpToTargets(sock, udpPort, targets, pktStr) {
    pktBytes := Buffer(StrPut(pktStr, "UTF-8"), 0)
    nBytes := StrPut(pktStr, pktBytes, "UTF-8") - 1
    portNet := DllCall("ws2_32\htons", "UShort", Integer(udpPort), "UShort")
    for _, dstIp in targets {
        dstAddr := Buffer(16, 0)
        NumPut("Short", 2, dstAddr, 0)
        NumPut("UShort", portNet, dstAddr, 2)
        NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", dstIp, "UInt"), dstAddr, 4)
        DllCall("ws2_32\sendto", "Ptr", sock, "Ptr", pktBytes.Ptr, "Int", nBytes, "Int", 0, "Ptr", dstAddr.Ptr, "Int", 16, "Int")
    }
}

_RBC_FormatSockAddrIp(srcAddr) {
    return NumGet(srcAddr, 4, "UChar") "." NumGet(srcAddr, 5, "UChar") "." NumGet(srcAddr, 6, "UChar") "." NumGet(srcAddr, 7, "UChar")
}

DiscoverHostBridgeUdp(sessionCode, udpPort := 4456, timeoutMs := 450) {
    codeNorm := NormalizePairingCode(sessionCode)
    if (codeNorm = "" || !IsInteger(udpPort) || Integer(udpPort) < 1 || Integer(udpPort) > 65535)
        return ""

    sock := _RBC_OpenBroadcastUdpSocket()
    if (!sock)
        return ""

    try {
        _RBC_SendUdpToTargets(sock, udpPort, ["255.255.255.255", "127.0.0.1"], "PSYNC_DISCOVER|" codeNorm)
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
                    return {
                        ok: true,
                        senderIp: _RBC_FormatSockAddrIp(srcAddr),
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
        _RBC_CloseUdpSocket(sock)
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

    sock := _RBC_OpenBroadcastUdpSocket()
    if (!sock)
        return results

    seen := Map()
    try {
        targets := ["255.255.255.255", "127.0.0.1"]
        if IsObject(extraTargets) {
            for _, t in extraTargets {
                ts := Trim(String(t))
                if (ts != "")
                    targets.Push(ts)
            }
        }
        _RBC_SendUdpToTargets(sock, discoverPort, targets, "PS_DISCOVER_V1")

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
                parsed := ParsePublicDiscoveryBeaconJson(text, _RBC_FormatSockAddrIp(srcAddr))
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
        _RBC_CloseUdpSocket(sock)
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
        if (hLow != "" && !seen.Has(hLow) && ordered.Length < 12) {
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
    whr := ""
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
        if (IsObject(whr))
            try whr.Abort()
        return { ok: false }
    } finally {
        whr := ""
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

    whr := ""
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
                allowDirectObsFallback: _RBC_JsonGetBool(body, "allowDirectObsFallback", false),
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
        if (IsObject(whr))
            try whr.Abort()
        return { ok: false, status: 0, error: exc.Message }
    } finally {
        whr := ""
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

    allowDirectObs := !cfg.HasOwnProp("DirectObsFallbackAllowed") || cfg.DirectObsFallbackAllowed
    if (!hasBridgePairing || allowDirectObs) {
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
    }
    return queue
}

GetRemoteDisplayDeviceName(cfg) {
    inst := (cfg.HasOwnProp("InstanceName")) ? Trim(cfg.InstanceName) : ""
    if (inst != "" && StrLower(inst) != StrLower(A_ComputerName))
        return A_ComputerName " (" inst ")"
    return A_ComputerName
}

_RBC_GetDeviceId(cfg) {
    return (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? cfg.DeviceId : "win-default"
}

CloseRemoteSocketRef(ws, state := "", deferred := false) {
    if (IsObject(state) && state.HasOwnProp("obsWs") && state.obsWs == ws)
        state.obsWs := ""
    if (!IsObject(ws))
        return
    try ws._psClosed := true
    if (deferred && IsSet(SafeCloseWebSocketDeferred))
        SafeCloseWebSocketDeferred(ws)
    else
        try ws.shutdown()
}

CloseRemoteWebSocket(state, deferred := false) {
    if (!IsObject(state) || !state.HasOwnProp("obsWs"))
        return
    ws := state.obsWs
    state.obsWs := ""
    if (!IsObject(ws))
        return
    CloseRemoteSocketRef(ws, state, deferred)
}

CancelRemotePongWatchdog(state) {
    if (IsObject(state) && state.HasOwnProp("_pongWatchdogTimerFn") && IsObject(state._pongWatchdogTimerFn)) {
        try SetTimer(state._pongWatchdogTimerFn, 0)
        state._pongWatchdogTimerFn := ""
        return true
    }
    return false
}

CancelRemoteBridgeHandshakeWatchdog(state) {
    if (IsObject(state) && state.HasOwnProp("_bridgeHandshakeTimerFn") && IsObject(state._bridgeHandshakeTimerFn)) {
        try SetTimer(state._bridgeHandshakeTimerFn, 0)
        state._bridgeHandshakeTimerFn := ""
        return true
    }
    return false
}

StopRemoteSessionTimers(state, stopReconnect := false) {
    if (!IsObject(state))
        return 0
    stopped := 0
    if (stopReconnect && state.HasOwnProp("reconnectTimerFn") && IsObject(state.reconnectTimerFn)) {
        try SetTimer(state.reconnectTimerFn, 0)
        stopped += 1
    }
    if (state.HasOwnProp("heartbeatTimerFn") && IsObject(state.heartbeatTimerFn)) {
        try SetTimer(state.heartbeatTimerFn, 0)
        stopped += 1
    }
    if (CancelRemotePongWatchdog(state))
        stopped += 1
    if (CancelRemoteBridgeHandshakeWatchdog(state))
        stopped += 1
    for _, timerProp in ["lanRepromoteTimerFn", "presenterTickFn", "recTickFn", "breathTimerFn"] {
        if (state.HasOwnProp(timerProp) && IsObject(state.%timerProp%)) {
            try SetTimer(state.%timerProp%, 0)
            stopped += 1
        }
    }
    return stopped
}

StopAllRemoteTimers(state) {
    if (!IsObject(state))
        return 0
    static timerProps := [
        "dragTimerFn", "breathTimerFn", "_muteAnimTimerFn", "autoDodgeTimerFn", "idleDimTimerFn",
        "reconnectTimerFn", "heartbeatTimerFn", "lanRepromoteTimerFn",
        "presenterTickFn", "recTickFn", "rebuildTrayFn"
    ]
    stopped := 0
    for _, prop in timerProps {
        if (state.HasOwnProp(prop) && IsObject(state.%prop%)) {
            try SetTimer(state.%prop%, 0)
            stopped += 1
        }
    }
    if (CancelRemotePongWatchdog(state))
        stopped += 1
    if (CancelRemoteBridgeHandshakeWatchdog(state))
        stopped += 1
    return stopped
}

ResetRemoteConnectionTelemetry(state, resetFallback := false) {
    if (!IsObject(state))
        return
    state.obsConnected := false
    state.usingBridge := false
    state.usingDirectObsFallback := false
    if (resetFallback)
        state.usingRelayFallback := false
    state.activeHost := ""
    state.recState := 0
    state.recSeconds := 0
    state.streamDropWarn := false
    state.voiceWhileMuted := false
    state.osMicMutedDrift := false
    state.lowDiskWarnLevel := 0
    state.lowDiskMb := -1
    state.deadMicWarn := false
    state.meetBgTabWarn := false
    state.isStandby := false
    state.timerState := "stopped"
    state.scenes := []
    state.quickNudges := []
    state.slideIndex := 0
    state.slideTotal := 0
    state.slideTitle := ""
    state.slideNotes := ""
    state.hostBootId := ""
    state.lastStateSeq := 0
}

IsRemoteDirectObsReady(cfg, state) {
    if (IsSet(IsRemoteUsingDirectObsChannel) && IsRemoteUsingDirectObsChannel(cfg, state))
        return true
    return IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback && state.HasOwnProp("obsConnected") && state.obsConnected && IsObject(state.obsWs)
}

_RBC_PersistRemoteMute(cfg, state, targetMuted) {
    val := !!targetMuted
    if (IsObject(state))
        state.isMuted := val
    if (IsObject(cfg) && cfg.HasOwnProp("IsMuted")) {
        cfg.IsMuted := val
        if (cfg.HasMethod("WriteBool"))
            try cfg.WriteBool("Settings", "IsMuted", val)
    }
}

_RBC_NotifyRemoteStateUi(state, preferRebuildTray := false) {
    if (!IsObject(state))
        return
    if (preferRebuildTray && state.HasOwnProp("rebuildTrayFn") && IsObject(state.rebuildTrayFn)) {
        try state.rebuildTrayFn.Call()
    } else if (state.HasMethod("NotifyTrayStatus")) {
        state.NotifyTrayStatus()
    }
}

CommitRemoteSceneChange(state, newScene, notify := true) {
    if (!IsObject(state))
        return
    clean := Trim(String(newScene))
    if (clean = "")
        return
    curSc := state.HasOwnProp("activeScene") ? Trim(String(state.activeScene))
        : (state.HasOwnProp("currentSceneName") ? Trim(String(state.currentSceneName)) : "")
    if (curSc != "" && curSc != "Scene" && curSc != clean)
        state.previousProgramScene := curSc
    state.activeScene := clean
    if (state.HasOwnProp("currentSceneName"))
        state.currentSceneName := clean
    if (notify)
        _RBC_NotifyRemoteStateUi(state, false)
}

_RBC_NextCmdId(cfg) {
    static cmdSeq := 0
    cmdSeq += 1
    return _RBC_GetDeviceId(cfg) "-" cmdSeq
}

BuildRemoteFallbackStateJson(state) {
    if (!IsObject(state))
        return ""
    isStb := (state.HasOwnProp("isStandby") && state.isStandby) ? true : false
    tmrSt := state.HasOwnProp("timerState") ? StrLower(Trim(String(state.timerState))) : "stopped"
    hasTmr := (tmrSt = "running" || tmrSt = "paused" || tmrSt = "overtime")
    if (!isStb && !hasTmr)
        return ""
    prevScene := ""
    wasMuted := false
    if (state.HasOwnProp("standbySnapshot") && IsObject(state.standbySnapshot)) {
        if (state.standbySnapshot.HasOwnProp("scene"))
            prevScene := String(state.standbySnapshot.scene)
        if (state.standbySnapshot.HasOwnProp("muted"))
            wasMuted := !!state.standbySnapshot.muted
    }
    if (prevScene = "" && state.HasOwnProp("previousProgramScene"))
        prevScene := String(state.previousProgramScene)
    brbScene := (state.HasOwnProp("standbyScene") && state.standbyScene != "") ? String(state.standbyScene) : "BRB"
    tRem := state.HasOwnProp("timerRemainingSec") ? Integer(state.timerRemainingSec) : 600
    tPre := (state.HasOwnProp("timerPresetSec") && Integer(state.timerPresetSec) > 0) ? Integer(state.timerPresetSec) : 600
    return '{"fromDirectObsFallback":true,"isStandby":' (isStb ? "true" : "false") ',"standbyScene":"' _RBC_JsonEscape(brbScene) '","previousScene":"' _RBC_JsonEscape(prevScene) '","wasMuted":' (wasMuted ? "true" : "false") ',"timerState":"' _RBC_JsonEscape(tmrSt) '","timerRemainingSec":' tRem ',"timerPresetSec":' tPre '}'
}

BuildRemoteBridgeSyncReqJson(cfg := "") {
    devId := IsObject(cfg) ? _RBC_GetDeviceId(cfg) : "win-remote"
    return '{"type":"sync_req","deviceId":"' _RBC_JsonEscape(devId) '"}'
}

BuildRemoteBridgeAuthJson(cfg, fallbackStateJson := "") {
    devId := _RBC_GetDeviceId(cfg)
    tok := cfg.HasOwnProp("SessionToken") ? Trim(cfg.SessionToken) : ""
    code := cfg.HasOwnProp("SessionPairingCode") ? Trim(cfg.SessionPairingCode) : ""
    devName := GetRemoteDisplayDeviceName(cfg)
    ver := (IsSet(UIConstants) && UIConstants.HasOwnProp("APP_VERSION")) ? UIConstants.APP_VERSION : ""
    caps := '["protocol_v2","cmd_dedup","set_state","ack_nack"]'
    fbField := (Trim(String(fallbackStateJson)) != "") ? (',"clientFallbackState":' fallbackStateJson) : ""
    return '{"type":"auth","protocolVersion":2,"appVersion":"' _RBC_JsonEscape(ver) '","capabilities":' caps ',"token":"' _RBC_JsonEscape(tok) '","code":"' _RBC_JsonEscape(code) '","deviceId":"' _RBC_JsonEscape(devId) '","deviceName":"' _RBC_JsonEscape(devName) '","platform":"Windows"' fbField '}'
}

BuildRemoteBridgeToggleJson(cfg) {
    return '{"type":"toggle_mute","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"clicker"}'
}

BuildRemoteBridgeSetMuteJson(cfg, targetMuted) {
    return '{"type":"set_mute","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","isMuted":' (targetMuted ? "true" : "false") ',"deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"hud"}'
}

BuildRemoteBridgeSetRecordJson(cfg, recording, confirmed := true) {
    return '{"type":"set_record","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","recording":' (recording ? "true" : "false") ',"confirmed":' (confirmed ? "true" : "false") ',"deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"tray"}'
}

BuildRemoteBridgeSetStandbyJson(cfg, isStandby) {
    return '{"type":"set_standby","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","isStandby":' (isStandby ? "true" : "false") ',"deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"tray"}'
}

BuildRemoteBridgeDisconnectJson(cfg) {
    return '{"type":"disconnect","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"remote"}'
}

BuildRemoteBridgeUnpairJson(cfg) {
    return '{"type":"unpair","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"remote"}'
}

BuildRemoteBridgePingJson() {
    return '{"type":"ping"}'
}

BuildRemoteBridgeDeckJson(cfg, actionType) {
    return '{"type":"' _RBC_JsonEscape(actionType) '","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"tray"}'
}

BuildRemoteBridgeSceneJson(cfg, sceneName) {
    return '{"type":"switch_scene","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","sceneName":"' _RBC_JsonEscape(sceneName) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"tray"}'
}

BuildRemoteBridgeTimerJson(cfg, action, durationSec := 0) {
    return '{"type":"' _RBC_JsonEscape(action) '","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","durationSec":' Integer(durationSec) ',"deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '","source":"tray"}'
}

BuildRemoteBridgeNudgeJson(cfg, message, sender := "", accentHex := "F59E0B") {
    snd := (Trim(String(sender)) != "") ? Trim(String(sender)) : GetRemoteDisplayDeviceName(cfg)
    return '{"type":"stage_nudge","cmdId":"' _RBC_JsonEscape(_RBC_NextCmdId(cfg)) '","message":"' _RBC_JsonEscape(message) '","sender":"' _RBC_JsonEscape(snd) '","accentHex":"' _RBC_JsonEscape(accentHex) '","deviceId":"' _RBC_JsonEscape(_RBC_GetDeviceId(cfg)) '"}'
}

ParseHostBridgeWsEvent(rawText) {
    obj := JsonCodec.Parse(rawText)
    if !(obj is Map)
        return ""
    t := JsonCodec.GetStr(obj, "type")
    if (t = "")
        return ""
    reasonStr := JsonCodec.GetStr(obj, "reason")
    if (reasonStr = "")
        reasonStr := JsonCodec.GetStr(obj, "error")
    obsFbMap := (obj.Has("obsFallback") && (obj["obsFallback"] is Map)) ? obj["obsFallback"] : ""
    return {
        kind: t,
        protocolVersion: JsonCodec.GetInt(obj, "protocolVersion", 1),
        appVersion: JsonCodec.GetStr(obj, "appVersion"),
        hostBootId: JsonCodec.GetStr(obj, "hostBootId"),
        stateSeq: JsonCodec.GetInt(obj, "stateSeq", 0),
        cmdId: JsonCodec.GetStr(obj, "cmdId"),
        code: JsonCodec.GetStr(obj, "code"),
        dedup: JsonCodec.GetBool(obj, "dedup", false),
        hasObsFallback: IsObject(obsFbMap),
        obsFallbackPort: IsObject(obsFbMap) ? JsonCodec.GetInt(obsFbMap, "port", 4455) : 0,
        obsFallbackMic: IsObject(obsFbMap) ? JsonCodec.GetStr(obsFbMap, "targetMic") : "",
        obsFallbackPassword: IsObject(obsFbMap) ? JsonCodec.GetStr(obsFbMap, "password") : "",
        obsFallbackDirectObsAllowed: IsObject(obsFbMap) ? JsonCodec.GetBool(obsFbMap, "directObsAllowed", true) : true,
        hasMuted: JsonCodec.HasKey(obj, "isMuted"),
        isMuted: JsonCodec.GetBool(obj, "isMuted", false),
        routingMode: JsonCodec.GetInt(obj, "routingMode", 1),
        targetMicName: JsonCodec.GetStr(obj, "targetMicName"),
        conferencingApp: JsonCodec.GetStr(obj, "conferencingApp"),
        detectedConfApp: JsonCodec.GetStr(obj, "detectedConfApp"),
        meetBgTabWarn: JsonCodec.GetBool(obj, "meetBgTabWarn", false),
        slideIndex: JsonCodec.GetInt(obj, "slideIndex", 0),
        slideTotal: JsonCodec.GetInt(obj, "slideTotal", 0),
        slideTitle: JsonCodec.GetStr(obj, "slideTitle"),
        slideNotes: JsonCodec.GetStr(obj, "slideNotes"),
        recState: JsonCodec.GetInt(obj, "recState", 0),
        obsRecState: JsonCodec.GetInt(obj, "obsRecState", 0),
        confRecState: JsonCodec.GetInt(obj, "confRecState", 0),
        recSourceTag: JsonCodec.GetStr(obj, "recSourceTag"),
        recSeconds: JsonCodec.GetInt(obj, "recSeconds", 0),
        obsConnected: JsonCodec.GetBool(obj, "obsConnected", false),
        streamDropWarn: JsonCodec.GetBool(obj, "streamDropWarn", false),
        voiceWhileMuted: JsonCodec.GetBool(obj, "voiceWhileMuted", false),
        osMicMutedDrift: JsonCodec.GetBool(obj, "osMicMutedDrift", false),
        lowDiskWarnLevel: JsonCodec.GetInt(obj, "lowDiskWarnLevel", 0),
        lowDiskMb: JsonCodec.GetInt(obj, "lowDiskMb", -1),
        deadMicWarn: JsonCodec.GetBool(obj, "deadMicWarn", false),
        quickNudges: JsonCodec.GetStrArray(obj, "quickNudges"),
        activeScene: JsonCodec.GetStr(obj, "activeScene"),
        scenes: JsonCodec.GetStrArray(obj, "scenes"),
        isStandby: JsonCodec.GetBool(obj, "isStandby", false),
        standbyScene: JsonCodec.GetStr(obj, "standbyScene"),
        timerState: JsonCodec.GetStr(obj, "timerState"),
        timerRemainingSec: JsonCodec.GetInt(obj, "timerRemainingSec", 600),
        timerPresetSec: JsonCodec.GetInt(obj, "timerPresetSec", 600),
        message: JsonCodec.GetStr(obj, "message"),
        sender: JsonCodec.GetStr(obj, "sender"),
        accentHex: JsonCodec.GetStr(obj, "accentHex"),
        hostUuid: JsonCodec.GetStr(obj, "hostUuid"),
        hostName: JsonCodec.GetStr(obj, "hostName"),
        sessionToken: JsonCodec.GetStr(obj, "sessionToken"),
        reason: reasonStr,
        action: JsonCodec.GetStr(obj, "action"),
        ok: JsonCodec.GetBool(obj, "ok", false)
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
    cfg.ObsPassword := pairRes.HasOwnProp("obsPassword") ? pairRes.obsPassword : ""
    cfg.DirectObsFallbackAllowed := pairRes.HasOwnProp("allowDirectObsFallback") ? !!pairRes.allowDirectObsFallback : false
    if (pairRes.HasOwnProp("targetMicName") && pairRes.targetMicName != "")
        cfg.TargetMicName := pairRes.targetMicName
    if (pairRes.HasOwnProp("internetPairingCode") && pairRes.internetPairingCode != "")
        cfg.InternetPairingCode := pairRes.internetPairingCode
    if (pairRes.HasOwnProp("hostUuid") && pairRes.hostUuid != "")
        cfg.PairedHostUuid := pairRes.hostUuid
    return true
}

_ApplyRemoteObsFallbackCreds(cfg, ev) {
    if (!IsObject(cfg) || !IsObject(ev) || !ev.HasOwnProp("hasObsFallback") || !ev.hasObsFallback)
        return false
    changed := false
    if (ev.HasOwnProp("obsFallbackPort") && Integer(ev.obsFallbackPort) >= 1 && Integer(ev.obsFallbackPort) <= 65535) {
        newPort := String(Integer(ev.obsFallbackPort))
        if (cfg.HostPort != newPort) {
            cfg.HostPort := newPort
            if (cfg.HasMethod("Write"))
                try cfg.Write("Connection", "HostPort", newPort)
            changed := true
        }
    }
    if (ev.HasOwnProp("obsFallbackMic") && Trim(ev.obsFallbackMic) != "") {
        newMic := Trim(ev.obsFallbackMic)
        if (cfg.TargetMicName != newMic) {
            cfg.TargetMicName := newMic
            if (cfg.HasMethod("Write"))
                try cfg.Write("Connection", "TargetMicName", newMic)
            changed := true
        }
    }
    if (ev.HasOwnProp("obsFallbackPassword") && cfg.ObsPassword != ev.obsFallbackPassword) {
        cfg.ObsPassword := ev.obsFallbackPassword
        if (cfg.HasMethod("Write"))
            try cfg.Write("Connection", "ObsPassword", ev.obsFallbackPassword)
        changed := true
    }
    if (ev.HasOwnProp("obsFallbackDirectObsAllowed")) {
        nextAllowed := !!ev.obsFallbackDirectObsAllowed
        if (!cfg.HasOwnProp("DirectObsFallbackAllowed") || cfg.DirectObsFallbackAllowed != nextAllowed) {
            cfg.DirectObsFallbackAllowed := nextAllowed
            if (cfg.HasMethod("WriteBool"))
                try cfg.WriteBool("Connection", "DirectObsFallbackAllowed", nextAllowed)
            changed := true
        }
    }
    return changed
}

SaveRemoteConnectionSettingsToIni(cfg) {
    if (!IsObject(cfg))
        return
    cfg.Write("Connection", "NetworkMode", cfg.NetworkMode)
    cfg.Write("Connection", "InternetPairingCode", cfg.InternetPairingCode)
    if (cfg.HasOwnProp("RelayBaseUrl"))
        cfg.Write("Connection", "RelayBaseUrl", IsSet(NormalizeRelayBaseUrl) ? NormalizeRelayBaseUrl(cfg.RelayBaseUrl) : cfg.RelayBaseUrl)
    if (cfg.HasOwnProp("EnableRelayEncryption"))
        cfg.WriteBool("Connection", "EnableRelayEncryption", !!cfg.EnableRelayEncryption)
    cfg.Write("Connection", "HostAddress", cfg.HostAddress)
    cfg.Write("Connection", "HostPort", cfg.HostPort)
    cfg.Write("Connection", "BridgePort", cfg.BridgePort)
    cfg.Write("Connection", "SessionPairingCode", cfg.SessionPairingCode)
    cfg.Write("Connection", "SessionToken", cfg.SessionToken)
    if (cfg.HasOwnProp("PairedHostUuid"))
        cfg.Write("Connection", "PairedHostUuid", cfg.PairedHostUuid)
    cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
    if (cfg.HasOwnProp("DirectObsFallbackAllowed"))
        cfg.WriteBool("Connection", "DirectObsFallbackAllowed", !!cfg.DirectObsFallbackAllowed)
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

AnchorRemoteRecClock(state, recSeconds, nowTick := "") {
    if (!IsObject(state))
        return
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    sec := Max(0, Integer(recSeconds))
    state.recSeconds := sec
    state._recAnchorSec := sec
    state._recAnchorTick := t
}

AnchorRemotePresenterClock(state, remSec, nowTick := "") {
    if (!IsObject(state))
        return
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    sec := Integer(remSec)
    state.timerRemainingSec := sec
    state._timerAnchorRemSec := sec
    state._timerAnchorTick := t
}

UpdateRemoteLocalRecTimer(state) {
    if (!IsObject(state))
        return
    if (state.HasOwnProp("recTickFn") && IsObject(state.recTickFn)) {
        if (state.HasOwnProp("recState") && state.recState == 1) {
            if (!state.HasOwnProp("_recAnchorTick") || state._recAnchorTick <= 0)
                AnchorRemoteRecClock(state, state.HasOwnProp("recSeconds") ? state.recSeconds : 0)
            SetTimer state.recTickFn, 1000
        } else {
            state._recAnchorTick := 0
            SetTimer state.recTickFn, 0
        }
    }
}

RemoteLocalRecTick(cfg, state, nowTick := "") {
    if (!IsObject(state) || !state.HasOwnProp("recState") || state.recState != 1) {
        if (IsObject(state) && state.HasOwnProp("recTickFn") && IsObject(state.recTickFn))
            SetTimer state.recTickFn, 0
        return false
    }
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    if (state.HasOwnProp("_recAnchorTick") && state._recAnchorTick > 0) {
        elapsedSec := Max(0, (t - Integer(state._recAnchorTick) + 80) // 1000)
        state.recSeconds := Max(0, Integer(state._recAnchorSec) + elapsedSec)
    } else {
        state.recSeconds := (state.HasOwnProp("recSeconds") ? Integer(state.recSeconds) : 0) + 1
    }
    if (state.HasMethod("NotifyTrayStatus"))
        state.NotifyTrayStatus()
    return true
}

RemoteTimerTick(cfg, state, nowTick := "") {
    if (!IsObject(state) || !state.HasOwnProp("timerState") || (state.timerState != "running" && state.timerState != "overtime")) {
        if (IsObject(state) && state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
            SetTimer state.presenterTickFn, 0
        return false
    }
    prevRem := state.HasOwnProp("timerRemainingSec") ? Integer(state.timerRemainingSec) : 0
    t := (nowTick != "") ? Integer(nowTick) : A_TickCount
    if (state.HasOwnProp("_timerAnchorTick") && state._timerAnchorTick > 0) {
        elapsedSec := Max(0, (t - Integer(state._timerAnchorTick) + 80) // 1000)
        state.timerRemainingSec := Integer(state._timerAnchorRemSec) - elapsedSec
    } else {
        state.timerRemainingSec := prevRem - 1
    }
    newRem := state.timerRemainingSec
    if (prevRem > 0 && newRem <= 0 && state.timerState = "running") {
        state.timerState := "overtime"
        if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
            ShowStageNudgeBanner("Time Up — Overtime (" FormatCountdownClock(newRem) ")", "EF4444", 4500, "Timer")
    } else if (newRem <= 0 && state.timerState = "running") {
        state.timerState := "overtime"
    } else if (prevRem > 120 && newRem <= 120) {
        if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
            ShowStageNudgeBanner("2:00 Remaining", "F59E0B", 4500, "Timer")
    }
    if (state.HasMethod("NotifyTrayStatus"))
        state.NotifyTrayStatus()
    return true
}

ExecuteRemoteLocalTimerCommand(cfg, state, action, durationSec := 0) {
    if (!IsObject(state))
        return false
    actLow := StrLower(Trim(String(action)))
    if (actLow = "timer_start") {
        if (Integer(durationSec) > 0) {
            state.timerPresetSec := Integer(durationSec)
            state.timerRemainingSec := Integer(durationSec)
        } else if (!state.HasOwnProp("timerState") || state.timerState = "stopped") {
            preset := (state.HasOwnProp("timerPresetSec") && Integer(state.timerPresetSec) > 0) ? Integer(state.timerPresetSec) : 600
            state.timerPresetSec := preset
            state.timerRemainingSec := preset
        }
        state.timerState := (state.timerRemainingSec <= 0) ? "overtime" : "running"
        AnchorRemotePresenterClock(state, state.timerRemainingSec)
        if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
            SetTimer state.presenterTickFn, 1000
    } else if (actLow = "timer_pause") {
        cur := state.HasOwnProp("timerState") ? state.timerState : "stopped"
        if (cur = "stopped")
            return ExecuteRemoteLocalTimerCommand(cfg, state, "timer_start", 0)
        if (cur = "running" || cur = "overtime") {
            state.timerState := "paused"
            state._timerAnchorTick := 0
            if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
                SetTimer state.presenterTickFn, 0
        } else if (cur = "paused") {
            state.timerState := (state.timerRemainingSec <= 0) ? "overtime" : "running"
            AnchorRemotePresenterClock(state, state.timerRemainingSec)
            if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
                SetTimer state.presenterTickFn, 1000
        }
    } else if (actLow = "timer_reset") {
        state._timerAnchorTick := 0
        if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
            SetTimer state.presenterTickFn, 0
        preset := (Integer(durationSec) > 0) ? Integer(durationSec) : ((state.HasOwnProp("timerPresetSec") && Integer(state.timerPresetSec) > 0) ? Integer(state.timerPresetSec) : 600)
        state.timerPresetSec := preset
        state.timerRemainingSec := preset
        state.timerState := "stopped"
    } else {
        return false
    }
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("Timer", "RemoteLocalTimer", actLow " | rem=" state.timerRemainingSec)
    _RBC_NotifyRemoteStateUi(state, true)
    return true
}

ExecuteRemoteLocalStandbyToggle(cfg, state, enterStandby := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    curStandby := state.HasOwnProp("isStandby") ? !!state.isStandby : false
    wantStandby := (enterStandby == "") ? !curStandby : !!enterStandby
    if (wantStandby == curStandby)
        return true

    brbScene := (state.HasOwnProp("standbyScene") && Trim(state.standbyScene) != "") ? Trim(state.standbyScene) : "BRB"
    micName := (cfg.HasOwnProp("TargetMicName") && Trim(cfg.TargetMicName) != "") ? Trim(cfg.TargetMicName)
        : ((cfg.HasOwnProp("targetMicName") && Trim(cfg.targetMicName) != "") ? Trim(cfg.targetMicName) : "Mic/Aux")

    if (wantStandby) {
        prevSc := state.HasOwnProp("activeScene") ? String(state.activeScene)
            : (state.HasOwnProp("currentSceneName") ? String(state.currentSceneName) : "Scene")
        state.standbySnapshot := {
            scene: prevSc,
            muted: (state.HasOwnProp("isMuted") ? !!state.isMuted : false)
        }
        if (!state.isMuted) {
            if (IsObject(state.obsWs))
                SendObsRequest(state.obsWs, "SetInputMute", "RemoteClickerSetMute", '{"inputName":"' EscapeJsonStr(micName) '","inputMuted":true}')
            _RBC_PersistRemoteMute(cfg, state, true)
        }
        if (IsObject(state.obsWs))
            SendObsRequest(state.obsWs, "SetCurrentProgramScene", "RemoteStandbyScene", '{"sceneName":"' EscapeJsonStr(brbScene) '"}')
        CommitRemoteSceneChange(state, brbScene, false)
        state.isStandby := true
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Director", "RemoteLocalStandbyEnter", "scene=" brbScene " | prev=" prevSc)
    } else {
        snap := state.HasOwnProp("standbySnapshot") ? state.standbySnapshot : ""
        state.isStandby := false
        state.standbySnapshot := ""
        if (IsObject(snap)) {
            if (snap.HasOwnProp("scene") && snap.scene != "" && snap.scene != "Scene") {
                if (IsObject(state.obsWs))
                    SendObsRequest(state.obsWs, "SetCurrentProgramScene", "RemoteStandbyRestoreScene", '{"sceneName":"' EscapeJsonStr(snap.scene) '"}')
                CommitRemoteSceneChange(state, snap.scene, false)
            }
            if (snap.HasOwnProp("muted")) {
                if (IsObject(state.obsWs))
                    SendObsRequest(state.obsWs, "SetInputMute", "RemoteClickerSetMute", '{"inputName":"' EscapeJsonStr(micName) '","inputMuted":' (snap.muted ? "true" : "false") '}')
                _RBC_PersistRemoteMute(cfg, state, snap.muted)
            }
        }
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Director", "RemoteLocalStandbyExit", "scene=" state.activeScene)
    }
    _RBC_NotifyRemoteStateUi(state, true)
    return true
}

ExecuteRemoteDirectObsTransition(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("obsConnected") || !state.obsConnected || !IsObject(state.obsWs))
        return false
    if (state.HasOwnProp("studioModeActive") && state.studioModeActive)
        return SendObsRequest(state.obsWs, "TriggerStudioModeTransition", "RemoteSceneTransition")
    prevSc := state.HasOwnProp("previewScene") ? Trim(state.previewScene)
        : (state.HasOwnProp("previewSceneName") ? Trim(state.previewSceneName) : "")
    curSc := state.HasOwnProp("activeScene") ? Trim(state.activeScene)
        : (state.HasOwnProp("currentSceneName") ? Trim(state.currentSceneName) : "")
    prevProg := state.HasOwnProp("previousProgramScene") ? Trim(state.previousProgramScene) : ""
    targetSc := (prevSc != "" && prevSc != curSc) ? prevSc : prevProg
    if (targetSc = "" && state.HasOwnProp("scenes") && IsObject(state.scenes) && state.scenes.Length >= 2) {
        curIdx := 0
        for idx, scName in state.scenes {
            if (scName == curSc) {
                curIdx := idx
                break
            }
        }
        nextIdx := (curIdx > 0) ? (Mod(curIdx, state.scenes.Length) + 1) : 1
        cand := state.scenes[nextIdx]
        if (cand == curSc && state.scenes.Length >= 2)
            cand := state.scenes[(Mod(nextIdx, state.scenes.Length) + 1)]
        if (cand != "" && cand != curSc)
            targetSc := cand
    }
    if (targetSc != "") {
        ok := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "RemoteSceneTransition", '{"sceneName":"' EscapeJsonStr(targetSc) '"}')
        if (ok)
            CommitRemoteSceneChange(state, targetSc, true)
        return ok
    }
    return false
}

FormatRemoteDirectObsStatus(activeHost) {
    hostTxt := Trim(String(activeHost))
    return "● Fallback: DIRECT OBS :4455" (hostTxt != "" ? (" (" hostTxt ")") : "")
}

TryConfirmRemoteStopRecording(cfg, state, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return true
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("stopRecConfirmUntil"))
        state.stopRecConfirmUntil := 0
    confirmEnabled := !cfg.HasOwnProp("ConfirmBeforeStopRecording") || cfg.ConfirmBeforeStopRecording
    isRecording := (state.HasOwnProp("recState") && state.recState != 0)
    if (!confirmEnabled || !isRecording) {
        state.stopRecConfirmUntil := 0
        return true
    }
    if (nowTick >= state.stopRecConfirmUntil) {
        winMs := IsSet(UIConstants) ? UIConstants.STOP_RECORD_CONFIRM_WINDOW_MS : 3000
        state.stopRecConfirmUntil := nowTick + winMs
        if (!IsSet(g_IsTestMode) || !g_IsTestMode) {
            try TrayTip("Click Start/Stop Recording again within 3s to STOP recording", "PresenterSync Remote", 0x2)
        }
        return false
    }
    state.stopRecConfirmUntil := 0
    return true
}

GetRemoteConnectionModeLabel(state) {
    if (!IsObject(state) || !state.obsConnected)
        return "Disconnected"
    if (state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback)
        return "Direct OBS :4455"
    if (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback)
        return "WAN Relay"
    if (state.HasOwnProp("usingBridge") && state.usingBridge)
        return "Host Bridge :4456"
    return "OBS :4455"
}

BuildRemotePillBadgeText(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return ""
    if (cfg.HasOwnProp("ShowPillMiniBadges") && !cfg.ShowPillMiniBadges)
        return ""
    parts := []
    if (state.HasOwnProp("timerState") && (state.timerState = "running" || state.timerState = "paused" || state.timerState = "overtime")) {
        rem := state.HasOwnProp("timerRemainingSec") ? Integer(state.timerRemainingSec) : 0
        isOt := (state.timerState = "overtime" || rem < 0)
        absSec := Abs(rem)
        parts.Push((isOt ? "-" : "") Format("{:02d}:{:02d}", absSec // 60, Mod(absSec, 60)))
    }
    if (state.HasOwnProp("isStandby") && state.isStandby)
        parts.Push("BRB")
    if ((state.HasOwnProp("recState") && state.recState == 1) || (state.HasOwnProp("obsRecState") && state.obsRecState == 1))
        parts.Push("REC")
    out := ""
    for idx, p in parts
        out .= (idx > 1 ? " " : "") p
    return out
}

GetRemotePillAlertBorderArgb(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return 0
    if (cfg.HasOwnProp("ShowPillMiniBadges") && !cfg.ShowPillMiniBadges)
        return 0
    if (state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted && state.HasOwnProp("isMuted") && state.isMuted)
        return 0xFFF59E0B
    return 0
}

ClampRemotePositionToBounds(x, y, w, h, monLeft, monTop, monRight, monBottom) {
    maxX := Max(monLeft, monRight - Max(1, w))
    maxY := Max(monTop, monBottom - Max(1, h))
    cx := Max(monLeft, Min(Integer(x), maxX))
    cy := Max(monTop, Min(Integer(y), maxY))
    return { x: cx, y: cy }
}

HandleRemotePowerBroadcast(wParam, state, reconnectFn := "") {
    wp := Integer(wParam)
    if (wp == 0x4) { ; PBT_APMSUSPEND
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Power", "PowerSuspend", "PBT_APMSUSPEND")
        if (IsObject(state)) {
            state.isSystemSuspending := true
            state.lastSuspendTick := A_TickCount
        }
        return "suspend"
    }
    if (wp == 0x7 || wp == 0x12) { ; PBT_APMRESUMESUSPEND / PBT_APMRESUMEAUTOMATIC
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Power", "PowerResume", wp == 0x12 ? "PBT_APMRESUMEAUTOMATIC" : "PBT_APMRESUMESUSPEND")
        if (IsObject(state)) {
            state.isSystemSuspending := false
            state.lastRxTick := 0
            state.reconnecting := false
            CloseRemoteWebSocket(state, false)
            if (state.HasOwnProp("obsConnected"))
                state.obsConnected := false
        }
        if (IsObject(reconnectFn)) {
            reconnectFn.Call(state)
        } else if (IsObject(state) && state.HasOwnProp("reconnectTimerFn") && IsObject(state.reconnectTimerFn)) {
            SetTimer(state.reconnectTimerFn, -50)
        }
        return "resume"
    }
    return ""
}

HandleRemoteWtsSessionChange(wParam, cfg, state, verifyFn := "") {
    wp := Integer(wParam)
    if (wp == 0x7) { ; WTS_SESSION_LOCK
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Power", "SessionLock", "WTS_SESSION_LOCK")
        if (IsObject(state))
            state.isSessionLocked := true
        return "lock"
    }
    if (wp == 0x8) { ; WTS_SESSION_UNLOCK
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Power", "SessionUnlock", "WTS_SESSION_UNLOCK")
        if (IsObject(state)) {
            state.isSessionLocked := false
            if (IsObject(verifyFn))
                verifyFn.Call()
            else if (state.HasOwnProp("reconnectTimerFn") && IsObject(state.reconnectTimerFn))
                SetTimer(state.reconnectTimerFn, -50)
        }
        return "unlock"
    }
    return ""
}

ResolveHostIpv4(host) {
    clean := Trim(String(host))
    if (clean = "")
        return 0
    if (StrLower(clean) = "localhost")
        clean := "127.0.0.1"
    if (clean != "255.255.255.255") {
        directIp := DllCall("ws2_32\inet_addr", "AStr", clean, "UInt")
        if (directIp != 0xFFFFFFFF)
            return directIp
    }
    wsaBuf := Buffer(408, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaBuf.Ptr, "Int") != 0)
        return 0
    ipOut := 0
    pRes := 0
    try {
        hints := Buffer(A_PtrSize == 8 ? 48 : 32, 0)
        NumPut("Int", 2, hints, 4)  ; AF_INET
        NumPut("Int", 1, hints, 8)  ; SOCK_STREAM
        NumPut("Int", 6, hints, 12) ; IPPROTO_TCP
        if (DllCall("ws2_32\GetAddrInfoW", "WStr", clean, "Ptr", 0, "Ptr", hints.Ptr, "Ptr*", &pRes, "Int") == 0 && pRes) {
            saPtr := NumGet(pRes, A_PtrSize == 8 ? 32 : 24, "Ptr")
            if (saPtr)
                ipOut := NumGet(saPtr, 4, "UInt")
        }
    } finally {
        if (pRes)
            try DllCall("ws2_32\FreeAddrInfoW", "Ptr", pRes)
        try DllCall("ws2_32\WSACleanup")
    }
    return ipOut
}

ProbeRemoteTcpPort(host, port, timeoutMs := 750) {
    cleanHost := Trim(String(host))
    pNum := IsInteger(port) ? Integer(port) : 0
    if (cleanHost = "" || pNum < 1 || pNum > 65535)
        return false
    if (IsLoopbackHost(cleanHost))
        return IsLocalTcpPortListening(pNum)
    ipNum := ResolveHostIpv4(cleanHost)
    if (ipNum == 0 || ipNum == 0xFFFFFFFF)
        return false
    wsaBuf := Buffer(408, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaBuf.Ptr, "Int") != 0)
        return false
    sock := -1
    ok := false
    try {
        sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "UPtr") ; AF_INET, SOCK_STREAM, IPPROTO_TCP
        if (sock = -1 || sock = 0xFFFFFFFFFFFFFFFF || sock = 0xFFFFFFFF)
            return false
        nonBlk := Buffer(4, 0)
        NumPut("UInt", 1, nonBlk, 0)
        DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int")
        sa := Buffer(16, 0)
        NumPut("UShort", 2, sa, 0)
        NumPut("UShort", DllCall("ws2_32\htons", "UShort", pNum, "UShort"), sa, 2)
        NumPut("UInt", ipNum, sa, 4)
        DllCall("ws2_32\connect", "Ptr", sock, "Ptr", sa.Ptr, "Int", 16, "Int")
        fdWrite := Buffer(8 + A_PtrSize * 2, 0)
        NumPut("UInt", 1, fdWrite, 0)
        NumPut("Ptr", sock, fdWrite, A_PtrSize)
        tv := Buffer(8, 0)
        sec := timeoutMs // 1000
        usec := Mod(timeoutMs, 1000) * 1000
        NumPut("Int", sec, tv, 0)
        NumPut("Int", usec, tv, 4)
        sel := DllCall("ws2_32\select", "Int", 0, "Ptr", 0, "Ptr", fdWrite.Ptr, "Ptr", 0, "Ptr", tv.Ptr, "Int")
        if (sel > 0) {
            errVal := Buffer(4, 0)
            errLen := Buffer(4, 0)
            NumPut("Int", 4, errLen, 0)
            if (DllCall("ws2_32\getsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x1007, "Ptr", errVal.Ptr, "Ptr", errLen.Ptr, "Int") == 0)
                ok := (NumGet(errVal, 0, "Int") == 0)
        }
    } finally {
        if (sock != 0 && sock != -1 && sock != 0xFFFFFFFFFFFFFFFF && sock != 0xFFFFFFFF)
            try DllCall("ws2_32\closesocket", "Ptr", sock)
        try DllCall("ws2_32\WSACleanup")
    }
    return ok
}

ProbeRemoteDualEndpoints(host, bridgePort := 4456, obsPort := 4455, probeFn := "") {
    cleanHost := Trim(String(host))
    bPort := (IsInteger(bridgePort) && Integer(bridgePort) >= 1 && Integer(bridgePort) <= 65535) ? Integer(bridgePort) : 4456
    oPort := (IsInteger(obsPort) && Integer(obsPort) >= 1 && Integer(obsPort) <= 65535) ? Integer(obsPort) : 4455
    bridgeOk := false
    obsOk := false
    if (IsObject(probeFn)) {
        res := probeFn.Call(cleanHost, bPort, oPort)
        if (IsObject(res)) {
            bridgeOk := res.HasOwnProp("bridgeOk") ? !!res.bridgeOk : false
            obsOk := res.HasOwnProp("obsOk") ? !!res.obsOk : false
        }
    } else if (cleanHost != "") {
        bRes := ProbeHostBridgeHealth(cleanHost, bPort, "", 800)
        bridgeOk := (IsObject(bRes) && bRes.HasOwnProp("ok")) ? !!bRes.ok : false
        obsOk := ProbeRemoteTcpPort(cleanHost, oPort, 800)
    }
    bridgeDetail := "Host Bridge (:" bPort "): " (bridgeOk ? "OK" : "UNREACHABLE")
    obsDetail := "Direct OBS (:" oPort "): " (obsOk ? "OK" : "UNREACHABLE")
    return {
        bridgeOk: bridgeOk,
        bridgeDetail: bridgeDetail,
        obsOk: obsOk,
        obsDetail: obsDetail,
        summary: bridgeDetail " | " obsDetail
    }
}

ComputePositionRatio(x, y, monLeft, monTop, monRight, monBottom) {
    monW := Max(1, Number(monRight) - Number(monLeft))
    monH := Max(1, Number(monBottom) - Number(monTop))
    xr := Max(0.0, Min(1.0, (Number(x) - Number(monLeft)) / monW))
    yr := Max(0.0, Min(1.0, (Number(y) - Number(monTop)) / monH))
    return {xRatio: Round(xr, 6), yRatio: Round(yr, 6)}
}

ResolvePositionFromRatio(xRatio, yRatio, w, h, monLeft, monTop, monRight, monBottom) {
    monW := Max(1, Number(monRight) - Number(monLeft))
    monH := Max(1, Number(monBottom) - Number(monTop))
    xr := Max(0.0, Min(1.0, Number(xRatio)))
    yr := Max(0.0, Min(1.0, Number(yRatio)))
    rawX := Round(Number(monLeft) + (xr * monW))
    rawY := Round(Number(monTop) + (yr * monH))
    return ClampRemotePositionToBounds(rawX, rawY, w, h, monLeft, monTop, monRight, monBottom)
}

