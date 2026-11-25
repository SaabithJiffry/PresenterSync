; ==============================================================================
; Test Suite: test_v920_protocol_v2.ahk
; Description: Verifies M2.1 shared JsonCodec structural parser/serializer,
;              strict RFC 6455 framing (masking, continuation, Ping interleave,
;              1002/1009 Close codes), HTTP 413 & Cross-Origin 403 /ws checks,
;              Protocol v2 envelope (protocolVersion/stateSeq/hostBootId/cmdId),
;              5s idempotent cmdId deduplication, set_record/set_standby/nack,
;              and disconnect vs unpair lifecycle.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\JsonCodec.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

passed := 0
failed := 0

AssertTrue(cond, label, detail := "") {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label (detail != "" ? " [" detail "]" : "") "`n", "*")
    }
}

; ==============================================================================
; 1. JsonCodec structural edge cases (no regex flaws)
; ==============================================================================
vtabStr := "Line1" Chr(11) "Line2"
escVtab := JsonCodec.Escape(vtabStr)
AssertTrue(escVtab == "Line1\u000bLine2", "JsonCodec.Escape escapes <0x20 vertical tab as \\u000b")

; Surrogate pair U+1F600 (😀) & literal backslash before n (C:\new)
surrogateParsed := JsonCodec.Parse('{"path":"C:\\new","emoji":"\ud83d\ude00","raw":"\u0026"}')
AssertTrue(IsObject(surrogateParsed) && surrogateParsed["path"] == "C:\new" && surrogateParsed["emoji"] == Chr(0x1F600) && surrogateParsed["raw"] == "&",
    "JsonCodec.Parse preserves \\\\n Windows paths, UTF-16 surrogate pairs, and \\u0026")

; Scene names containing brackets ], quotes \", and nested substring key trap
evilJson := '{"payload":{"type":"evil_nested","isMuted":false,"scenes":["Wrong"]},"scenes":["Main [1]","Cam \"A\" [2]","Break"],"type":"mute_state","isMuted":true}'
AssertTrue(JsonCodec.GetStr(evilJson, "type") == "mute_state", "JsonCodec.GetStr reads top-level key and ignores nested substring trap")
AssertTrue(JsonCodec.GetBool(evilJson, "isMuted", false) == true, "JsonCodec.GetBool reads top-level bool cleanly")
scArr := JsonCodec.GetStrArray(evilJson, "scenes")
AssertTrue(scArr.Length == 3 && scArr[1] == "Main [1]" && scArr[2] == 'Cam "A" [2]' && scArr[3] == "Break",
    "JsonCodec.GetStrArray handles embedded ] and escaped quotes without truncation", "len=" scArr.Length)

; Depth guard rejects excessive nesting
deepJson := ""
Loop 40
    deepJson .= "["
Loop 40
    deepJson .= "]"
deepErr := ""
AssertTrue(JsonCodec.Parse(deepJson, &deepErr, 32) == "" && InStr(deepErr, "depth") > 0, "JsonCodec.Parse enforces maxDepth=32")

; Stringify round-trip
stMap := Map("a", "hi`n`r" Chr(11), "b", 42, "c", JsonCodec.Bool(true), "d", ["x]", "y"])
rt := JsonCodec.Parse(JsonCodec.Stringify(stMap))
AssertTrue(IsObject(rt) && rt["b"] == 42 && rt["c"] == true && rt["d"][1] == "x]", "JsonCodec.Stringify/Parse round-trip")

; ==============================================================================
; 2. Raw non-blocking WinSock2 helpers for HTTP 413, Origin 403 & RFC 6455 frames
; ==============================================================================
RawTcpConnect(port) {
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    nonBlk := Buffer(4, 0)
    NumPut("UInt", 1, nonBlk, 0)
    DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int")
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", ((port & 0xFF) << 8) | ((port >> 8) & 0xFF), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)
    DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr.Ptr, "Int", 16, "Int")
    return sock
}

RawSendStr(sock, str) {
    bLen := StrPut(str, "UTF-8") - 1
    buf := Buffer(Max(1, bLen + 1), 0)
    StrPut(str, buf, "UTF-8")
    sent := 0
    deadline := A_TickCount + 2000
    while (sent < bLen && A_TickCount < deadline) {
        n := DllCall("ws2_32\send", "Ptr", sock, "Ptr", buf.Ptr + sent, "Int", bLen - sent, "Int", 0, "Int")
        if (n > 0)
            sent += n
        else
            Sleep 10
    }
    return sent == bLen
}

RawRecvBytes(sock, timeoutMs := 1500) {
    out := []
    rx := Buffer(8192, 0)
    deadline := A_TickCount + timeoutMs
    gotAny := false
    quietUntil := 0
    while (A_TickCount < deadline) {
        n := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", rx.Ptr, "Int", 8192, "Int", 0, "Int")
        if (n > 0) {
            gotAny := true
            quietUntil := A_TickCount + 80
            Loop n
                out.Push(NumGet(rx, A_Index - 1, "UChar"))
        } else if (n == 0) {
            break
        } else if (gotAny && A_TickCount >= quietUntil) {
            break
        } else {
            Sleep 10
        }
    }
    return out
}

BytesToAscii(arr) {
    s := ""
    for _, b in arr
        s .= (b >= 32 && b <= 126) || b == 13 || b == 10 ? Chr(b) : " "
    return s
}

BuildClientWsFrame(opcode, fin, masked, textPayload := "", declaredLenOverride := -1) {
    pLen := StrPut(textPayload, "UTF-8") - 1
    pBuf := Buffer(Max(1, pLen + 1), 0)
    if (pLen > 0)
        StrPut(textPayload, pBuf, "UTF-8")
    wireLen := (declaredLenOverride >= 0) ? declaredLenOverride : pLen
    hdrLen := 2 + (wireLen > 65535 ? 8 : (wireLen > 125 ? 2 : 0)) + (masked ? 4 : 0)
    frame := Buffer(hdrLen + pLen, 0)
    NumPut("UChar", (fin ? 0x80 : 0) | (opcode & 0x0F), frame, 0)
    mBit := masked ? 0x80 : 0
    off := 2
    if (wireLen <= 125) {
        NumPut("UChar", mBit | wireLen, frame, 1)
    } else if (wireLen <= 65535) {
        NumPut("UChar", mBit | 126, frame, 1)
        NumPut("UChar", (wireLen >> 8) & 0xFF, frame, 2)
        NumPut("UChar", wireLen & 0xFF, frame, 3)
        off := 4
    } else {
        NumPut("UChar", mBit | 127, frame, 1)
        NumPut("UChar", (wireLen >> 24) & 0xFF, frame, 6)
        NumPut("UChar", (wireLen >> 16) & 0xFF, frame, 7)
        NumPut("UChar", (wireLen >> 8) & 0xFF, frame, 8)
        NumPut("UChar", wireLen & 0xFF, frame, 9)
        off := 10
    }
    masks := [0x21, 0x43, 0x65, 0x87]
    if (masked) {
        Loop 4
            NumPut("UChar", masks[A_Index], frame, off + A_Index - 1)
        off += 4
    }
    Loop pLen {
        i := A_Index - 1
        b := NumGet(pBuf, i, "UChar")
        if (masked)
            b := b ^ masks[Mod(i, 4) + 1]
        NumPut("UChar", b, frame, off + i)
    }
    return frame
}

SendRawBuf(sock, buf) {
    total := buf.Size
    sent := 0
    deadline := A_TickCount + 2000
    while (sent < total && A_TickCount < deadline) {
        n := DllCall("ws2_32\send", "Ptr", sock, "Ptr", buf.Ptr + sent, "Int", total - sent, "Int", 0, "Int")
        if (n > 0)
            sent += n
        else
            Sleep 10
    }
    return sent == total
}

ExtractCloseCodesFromBytes(arr) {
    codes := []
    i := 1
    while (i + 3 <= arr.Length) {
        b0 := arr[i]
        b1 := arr[i + 1]
        op := b0 & 0x0F
        len := b1 & 0x7F
        hdr := 2
        if (len == 126 && i + 3 <= arr.Length) {
            len := (arr[i + 2] << 8) | arr[i + 3]
            hdr := 4
        }
        if (op == 0x8 && len >= 2 && (i + hdr + 1 <= arr.Length)) {
            codes.Push((arr[i + hdr] << 8) | arr[i + hdr + 1])
            break
        }
        i += hdr + len
    }
    return codes
}

; Start live loopback HostCompanionBridge
tmpIni := A_Temp "\ps_v920_proto_" A_TickCount ".ini"
try FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.SessionPairingCode := "PRO-920"
cfg.EnableWS := false
cfg.EnableRemoteConnections := true
cfg.AudioRoutingMode := 2
cfg.ConfirmBeforeStopRecording := true
cfg.StandbySceneName := "BRB"
cfg.obsPassword := ""

st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.obsConnected := false
st.isMuted := false
st.currentSceneName := "Main"
st.sceneList := ["Main", "Slides [2]", "BRB"]
st.obsSceneSwitchFn := (sc) => true

bridge := StartHostCompanionBridge(cfg, st, 0, 0, 0)
AssertTrue(IsObject(bridge) && bridge.running, "HostCompanionBridge started on loopback for Protocol v2 test")
bPort := bridge.boundTcpPort

; Test A: HTTP 413 on oversized POST /pair (> 8192)
s413 := RawTcpConnect(bPort)
RawSendStr(s413, "POST /pair HTTP/1.1`r`nHost: 127.0.0.1:" bPort "`r`nContent-Length: 9001`r`n`r`n{}")
resp413 := BytesToAscii(RawRecvBytes(s413, 1200))
try DllCall("ws2_32\closesocket", "Ptr", s413)
AssertTrue(InStr(resp413, "413 Payload Too Large") > 0, "POST /pair > 8KB returns HTTP 413", resp413)

; Test B: Cross-Origin /ws upgrade rejected with 403 Forbidden
sEvilOrig := RawTcpConnect(bPort)
RawSendStr(sEvilOrig, "GET /ws HTTP/1.1`r`nHost: 127.0.0.1:" bPort "`r`nOrigin: https://evil.example.com`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
resp403 := BytesToAscii(RawRecvBytes(sEvilOrig, 1200))
try DllCall("ws2_32\closesocket", "Ptr", sEvilOrig)
AssertTrue(InStr(resp403, "403 Forbidden") > 0, "Cross-origin /ws upgrade returns HTTP 403", resp403)

; Test C: Same-Origin /ws succeeds + unmasked client frame triggers RFC 6455 Close 1002
sUnmask := RawTcpConnect(bPort)
RawSendStr(sUnmask, "GET /ws HTTP/1.1`r`nHost: localhost:" bPort "`r`nOrigin: http://127.0.0.1:" bPort "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
resp101 := BytesToAscii(RawRecvBytes(sUnmask, 800))
AssertTrue(InStr(resp101, "101 Switching Protocols") > 0, "Loopback localhost/127.0.0.1 Origin allowed on /ws")
SendRawBuf(sUnmask, BuildClientWsFrame(0x1, true, false, '{"type":"ping"}'))
closeBytes1002 := RawRecvBytes(sUnmask, 1200)
try DllCall("ws2_32\closesocket", "Ptr", sUnmask)
codes1002 := ExtractCloseCodesFromBytes(closeBytes1002)
AssertTrue(codes1002.Length >= 1 && codes1002[1] == 1002, "Unmasked client WS frame closes with RFC 6455 code 1002")

; Test D: Oversized WS frame length triggers RFC 6455 Close 1009
sBig := RawTcpConnect(bPort)
RawSendStr(sBig, "GET /ws HTTP/1.1`r`nHost: 127.0.0.1:" bPort "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
RawRecvBytes(sBig, 600)
SendRawBuf(sBig, BuildClientWsFrame(0x1, true, true, "", 70000))
closeBytes1009 := RawRecvBytes(sBig, 1200)
try DllCall("ws2_32\closesocket", "Ptr", sBig)
codes1009 := ExtractCloseCodesFromBytes(closeBytes1009)
AssertTrue(codes1009.Length >= 1 && codes1009[1] == 1009, "Oversized WS frame closes with RFC 6455 code 1009")

; Test E: Fragmented WS text + Ping interleave + Protocol v2 auth, cmdId dedup, set_record/nack, disconnect vs unpair
sV2 := RawTcpConnect(bPort)
RawSendStr(sV2, "GET /ws HTTP/1.1`r`nHost: 127.0.0.1:" bPort "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
RawRecvBytes(sV2, 600)

authMsg := '{"type":"auth","protocolVersion":2,"appVersion":"9.2.0","capabilities":["protocol_v2"],"code":"PRO-920","deviceId":"v2-dev-1","deviceName":"ProtoV2","platform":"Windows"}'
mid := StrLen(authMsg) // 2
p1 := SubStr(authMsg, 1, mid)
p2 := SubStr(authMsg, mid + 1)
SendRawBuf(sV2, BuildClientWsFrame(0x1, false, true, p1))
SendRawBuf(sV2, BuildClientWsFrame(0x9, true, true, "hb"))
SendRawBuf(sV2, BuildClientWsFrame(0x0, true, true, p2))
authResp := BytesToAscii(RawRecvBytes(sV2, 1200))
AssertTrue(InStr(authResp, '"type":"auth_ok"') && InStr(authResp, '"protocolVersion":2') && InStr(authResp, '"hostBootId":"') && InStr(authResp, '"stateSeq":'),
    "Fragmented auth + Ping interleave authenticates with Protocol v2 auth_ok envelope", authResp)
g_HostCompanionBridge.SetDeviceRole("v2-dev-1", "Director")

; cmdId idempotency (toggle_mute twice with same cmdId -> st.isMuted flips ONCE, second returns cached dedup ack)
muteBefore := st.isMuted
togCmd := '{"type":"toggle_mute","cmdId":"dup-cmd-1","deviceId":"v2-dev-1","source":"test"}'
SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, togCmd))
rCmd1 := BytesToAscii(RawRecvBytes(sV2, 1000))
muteAfterFirst := st.isMuted
SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, togCmd))
rCmd2 := BytesToAscii(RawRecvBytes(sV2, 1000))
AssertTrue(muteAfterFirst == !muteBefore && st.isMuted == muteAfterFirst && InStr(rCmd1, '"type":"ack"') && InStr(rCmd2, '"dedup":true'),
    "cmdId 5s deduplication executes toggle_mute once and returns cached dedup ack", "after1=" muteAfterFirst " after2=" st.isMuted " r2=" rCmd2)

; Explicit set_record + nack confirm_required + nack stale_seq + set_standby
SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"set_record","cmdId":"rec-1","recording":true}'))
RawRecvBytes(sV2, 700)
AssertTrue(st.recState == 1, "set_record recording=true starts recording")

SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"set_record","cmdId":"rec-2","recording":false,"confirmed":false}'))
rNackConf := BytesToAscii(RawRecvBytes(sV2, 1000))
AssertTrue(InStr(rNackConf, '"type":"nack"') && InStr(rNackConf, '"code":"confirm_required"') && st.recState == 1,
    "set_record recording=false confirmed=false returns nack confirm_required", rNackConf)

SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"set_record","cmdId":"rec-3","recording":false,"confirmed":true}'))
RawRecvBytes(sV2, 700)
AssertTrue(st.recState == 0, "set_record confirmed=true stops recording")

SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"set_standby","cmdId":"brb-1","isStandby":true,"expectedStateSeq":1}'))
rNackStale := BytesToAscii(RawRecvBytes(sV2, 1000))
AssertTrue(InStr(rNackStale, '"type":"nack"') && InStr(rNackStale, '"code":"stale_seq"'),
    "Stale expectedStateSeq triggers nack stale_seq", rNackStale)

SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"set_standby","cmdId":"brb-2","isStandby":true}'))
rBrb := BytesToAscii(RawRecvBytes(sV2, 1000))
AssertTrue(st.isStandby == true && InStr(rBrb, '"type":"ack"'), "set_standby activates BRB standby", rBrb)

; obs_offline nack check when EnableWS=true & obsConnected=false
st.obsSceneSwitchFn := ""
cfg.EnableWS := true
st.obsConnected := false
SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"switch_scene","cmdId":"sc-off-1","sceneName":"Slides [2]"}'))
rOffline := BytesToAscii(RawRecvBytes(sV2, 1000))
AssertTrue(InStr(rOffline, '"type":"nack"') && InStr(rOffline, '"code":"obs_offline"'), "switch_scene while OBS offline returns nack obs_offline", rOffline)

; RemoteBridgeClient v2 builders + ParseHostBridgeWsEvent v2 metadata
authBuilt := BuildRemoteBridgeAuthJson(cfg)
AssertTrue(InStr(authBuilt, '"protocolVersion":2') && InStr(authBuilt, '"capabilities":'), "BuildRemoteBridgeAuthJson emits Protocol v2 metadata")
parsedAck := ParseHostBridgeWsEvent('{"type":"ack","protocolVersion":2,"hostBootId":"abc123","stateSeq":9,"cmdId":"c-1","action":"set_mute","ok":true,"dedup":true}')
AssertTrue(IsObject(parsedAck) && parsedAck.protocolVersion == 2 && parsedAck.hostBootId == "abc123" && parsedAck.stateSeq == 9 && parsedAck.dedup == true,
    "ParseHostBridgeWsEvent extracts Protocol v2 envelope fields")

; disconnect preserves token, unpair revokes token
SendRawBuf(sV2, BuildClientWsFrame(0x1, true, true, '{"type":"disconnect","deviceId":"v2-dev-1"}'))
rDisc := BytesToAscii(RawRecvBytes(sV2, 1000))
try DllCall("ws2_32\closesocket", "Ptr", sV2)
AssertTrue(InStr(rDisc, '"type":"disconnected"') && bridge.pairedDevices.Has("v2-dev-1") && bridge.validTokens.Count >= 1 && bridge.GetConnectedClientCount() == 0,
    "WS disconnect closes active session while preserving pairing & token")

sUnp := RawTcpConnect(bPort)
RawSendStr(sUnp, "GET /ws HTTP/1.1`r`nHost: 127.0.0.1:" bPort "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
RawRecvBytes(sUnp, 600)
tokSaved := bridge.pairedDevices["v2-dev-1"].token
SendRawBuf(sUnp, BuildClientWsFrame(0x1, true, true, '{"type":"auth","protocolVersion":2,"token":"' tokSaved '","deviceId":"v2-dev-1","deviceName":"ProtoV2","platform":"Windows"}'))
rReauth := BytesToAscii(RawRecvBytes(sUnp, 1000))
AssertTrue(InStr(rReauth, '"type":"auth_ok"') && bridge.GetConnectedClientCount() == 1, "Client reconnects cleanly using preserved token after disconnect")

SendRawBuf(sUnp, BuildClientWsFrame(0x1, true, true, '{"type":"unpair","deviceId":"v2-dev-1"}'))
rUnp := BytesToAscii(RawRecvBytes(sUnp, 1000))
try DllCall("ws2_32\closesocket", "Ptr", sUnp)
AssertTrue(InStr(rUnp, '"unpaired":true') && !bridge.pairedDevices.Has("v2-dev-1") && bridge.validTokens.Count == 0 && bridge.GetConnectedClientCount() == 0,
    "WS unpair removes paired device and revokes session token")

StopHostCompanionBridge()
try FileDelete(tmpIni)
try FileDelete(tmpIni ".bak")

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
