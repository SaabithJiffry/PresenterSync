; ==============================================================================
; Test Suite: test_v761_web_remote.ahk
; Description: Automated unit + live loopback HTTP/WS test for Zero-Install
;              Browser Web Remote (Lib\WebRemoteUI.ahk + HostCompanionBridge):
;              GET /, /remote, /favicon.ico, /health, zero \x27 escapes,
;              About modal, Clean Disconnect, and host toggle_mute ack/broadcast.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -25000)

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

PassCount := 0
FailCount := 0
OnError((exc, mode) => (FileAppend("[ERROR] " exc.What " (" exc.File ":" exc.Line "): " exc.Message "`n", "*"), ExitApp(1)))

Assert(name, cond, detail := "") {
    global PassCount, FailCount
    if (cond) {
        PassCount += 1
        FileAppend("[PASS] " name (detail != "" ? " - " detail : "") "`n", "*")
    } else {
        FailCount += 1
        FileAppend("[FAIL] " name (detail != "" ? " - " detail : "") "`n", "*")
    }
}

; 1. Pure HTML & /arcade.js builder checks (#1 zero \x27, #2 1.25x scale, #7 favicon/About/Disconnect, M2.4 Vault & Asteroid Blaster)
html := BuildWebRemoteHtml("8.2.0", 14472)
Assert("BuildWebRemoteHtml returns valid HTML5", InStr(html, "<!DOCTYPE html>") && InStr(html, "</html>"))
Assert("BuildWebRemoteHtml embeds version & port", InStr(html, "8.2.0") && InStr(html, "14472"))
Assert("BuildWebRemoteHtml contains ZERO broken \x27 escapes (#1)", !InStr(html, "\x27"))
for _, token in ["toggle_mute", "transition_scene", "slide_start", "ppt_next", "ppt_prev", "toggle_standby", "timer_start", "stage_nudge", "/ws", "/favicon.ico", "/arcade.js", "aboutModal", "discBtn", "cleanDisconnect", "addEventListener", "ps_web_scale", "1.25", "vaultSlotBadge", "vaultDrawerSlot", "CABINET: LOCKED [0 CREDITS]", "PSArcadeVault", "PSArcadeHost", "pongWatchT", "visibilitychange", "sha256Base64", "DIRECT OBS", "startDirectObsFallback", "startRepromoteProbe"] {
    Assert("BuildWebRemoteHtml includes control/feature '" token "'", InStr(html, token) > 0)
}
arcadeJs := BuildWebRemoteArcadeJs()
Assert("BuildWebRemoteArcadeJs returns valid JS with ZERO \x27 escapes", StrLen(arcadeJs) > 3000 && !InStr(arcadeJs, "\x27"))
for _, jsToken in ["PSArcadeVault", "PSArcadeHost", "PSWebSnake", "PSWebAsteroids", "PSWebBrickBreaker", "PSWebCyberPong", "PSWebFlappy", "PSWebLightCycles", "PSWebPacGrid", "ps_arcade_hi_snake", "ps_arcade_hi_asteroids", "ps_arcade_hi_brick_breaker", "ps_arcade_hi_cyber_pong", "ps_arcade_hi_flappy", "ps_arcade_hi_tron", "ps_arcade_hi_pac_grid", "buildPieces", "View: Full", "INSERTCOIN", "ASTEROID BLASTER", "ALIEN BLASTER", "Mode: Alien", "BRICK BREAKER", "CYBER PONG", "CLICKER FLAPPY", "NEON LIGHT CYCLES", "NEON PAC-GRID", "GRAVITY WAVE", "MIC BUMPER"] {
    Assert("BuildWebRemoteArcadeJs includes '" jsToken "'", InStr(arcadeJs, jsToken) > 0)
}
Assert("BuildWebRemoteArcadeJs never persists vault unlock status in localStorage/sessionStorage", !InStr(arcadeJs, "ps_arcade_unlocked") && !InStr(arcadeJs, "sessionStorage.setItem"))

; 2. Live loopback HostCompanionBridge HTTP checks on port 14472
tmpIni := A_Temp "\ps_v761_web_remote_test.ini"
try FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.SessionPairingCode := "WEB-761"
cfg.EnableWS := true
cfg.targetMicName := "Mic/Aux"
cfg.obsPassword := "TopSecretOBS4455!"
mockObsSent := []
cfg.AudioRoutingMode := 1
state := {
    isMuted: false,
    obsConnected: true,
    obsWs: { sendText: (this, pkt) => mockObsSent.Push(pkt) },
    recState: 0,
    recElapsedSec: 0,
    streamState: 0,
    voiceWhileMuted: false,
    currentSceneName: "Main",
    sceneList: ["Main", "Slides", "BRB"],
    isStandby: false,
    timerState: "stopped",
    timerRemainingSec: 600,
    timerPresetSec: 600,
    slideIndex: 1,
    slideTotal: 10,
    slideTitle: "Intro",
    slideNotes: "Welcome"
}

bridgePort := 14472
bridge := StartHostCompanionBridge(cfg, state, bridgePort, bridgePort, bridgePort + 1)
Assert("HostCompanionBridge starts on loopback port 14472", IsObject(bridge) && bridge.running)

HttpGetAsync(url) {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(1500, 1500, 1500, 1500)
    req.Open("GET", url, true)
    req.Send()
    okResp := false
    deadline := A_TickCount + 2500
    while (A_TickCount < deadline) {
        try {
            if (req.WaitForResponse(0)) {
                okResp := true
                break
            }
        }
        Sleep 10
    }
    if (!okResp)
        return {status: 0, contentType: "", body: "TIMEOUT", byteLen: 0}
    bLen := 0
    try bLen := req.ResponseBody.MaxIndex() + 1
    bodyTxt := ""
    try bodyTxt := req.ResponseText
    return {
        status: req.Status,
        contentType: req.GetResponseHeader("Content-Type"),
        body: bodyTxt,
        byteLen: bLen
    }
}

resRoot := HttpGetAsync("http://127.0.0.1:" bridgePort "/")
Assert("GET / returns 200 OK", resRoot.status = 200, "status=" resRoot.status)
Assert("GET / returns text/html", InStr(StrLower(resRoot.contentType), "text/html") > 0, resRoot.contentType)
Assert("GET / returns full Web Remote HTML with zero \x27", InStr(resRoot.body, "PresenterSync Web Remote") > 0 && !InStr(resRoot.body, "\x27"))

resRemote := HttpGetAsync("http://127.0.0.1:" bridgePort "/remote")
Assert("GET /remote returns 200 OK", resRemote.status = 200, "status=" resRemote.status)

resFav := HttpGetAsync("http://127.0.0.1:" bridgePort "/favicon.ico")
Assert("GET /favicon.ico returns 200 OK binary image/x-icon (#7)", resFav.status = 200 && InStr(StrLower(resFav.contentType), "image/x-icon") > 0 && resFav.byteLen > 1000, Format("status={} type={} bytes={}", resFav.status, resFav.contentType, resFav.byteLen))

resHealth := HttpGetAsync("http://127.0.0.1:" bridgePort "/health")
Assert("GET /health returns 200 OK & JSON", resHealth.status = 200 && InStr(StrLower(resHealth.contentType), "application/json") > 0 && InStr(resHealth.body, '"ok":true') > 0)
Assert("GET /health NEVER exposes obsPassword or obsFallback (M5A.3)", !InStr(resHealth.body, "TopSecretOBS4455!") && !InStr(resHealth.body, "obsFallback"))
Assert("GET / HTML NEVER exposes obsPassword (M5A.3)", !InStr(resRoot.body, "TopSecretOBS4455!"))

resArcade := HttpGetAsync("http://127.0.0.1:" bridgePort "/arcade.js")
Assert("GET /arcade.js returns 200 OK application/javascript with full M2-M6 suite (LightCycles, PacGrid, MissileDefense, Snake buildPieces, View: Full, Alien Blaster)", resArcade.status = 200 && InStr(StrLower(resArcade.contentType), "javascript") > 0 && InStr(resArcade.body, "PSWebAsteroids") > 0 && InStr(resArcade.body, "ALIEN BLASTER") > 0 && InStr(resArcade.body, "Mode: Alien") > 0 && InStr(resArcade.body, "PSWebBrickBreaker") > 0 && InStr(resArcade.body, "PSWebCyberPong") > 0 && InStr(resArcade.body, "PSWebFlappy") > 0 && InStr(resArcade.body, "PSWebLightCycles") > 0 && InStr(resArcade.body, "PSWebPacGrid") > 0 && InStr(resArcade.body, "PSWebMissileDefense") > 0 && InStr(resArcade.body, "ps_arcade_hi_tron") > 0 && InStr(resArcade.body, "ps_arcade_hi_pac_grid") > 0 && InStr(resArcade.body, "ps_arcade_hi_missile_defense") > 0 && InStr(resArcade.body, "MISSILE DEFENSE") > 0 && InStr(resArcade.body, "buildPieces") > 0 && InStr(resArcade.body, "View: Full") > 0 && !InStr(resArcade.body, "\x27"), Format("status={} type={} bytes={}", resArcade.status, resArcade.contentType, resArcade.byteLen))

; 3. Non-blocking WinSock2 loopback WS toggle_mute ack (#1) + clean disconnect (#7)
LoopbackWsOpen(port, path) {
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    nonBlk := Buffer(4, 0)
    NumPut("UInt", 1, nonBlk, 0)
    DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int")
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", ((port & 0xFF) << 8) | ((port >> 8) & 0xFF), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)
    DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr.Ptr, "Int", 16, "Int")

    req := "GET " path " HTTP/1.1`r`nHost: 127.0.0.1:" port "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n"
    reqLen := StrPut(req, "UTF-8") - 1
    reqBuf := Buffer(reqLen + 1, 0)
    StrPut(req, reqBuf, "UTF-8")
    deadline := A_TickCount + 2000
    while (A_TickCount < deadline) {
        if (DllCall("ws2_32\send", "Ptr", sock, "Ptr", reqBuf.Ptr, "Int", reqLen, "Int", 0, "Int") == reqLen)
            break
        Sleep 15
    }
    return sock
}

LoopbackWsSendText(sock, txt) {
    pLen := StrPut(txt, "UTF-8") - 1
    pBuf := Buffer(Max(1, pLen + 1), 0)
    StrPut(txt, pBuf, "UTF-8")
    ; Client->Server WS frames must be masked; use simple mask [0x11,0x22,0x33,0x44]
    hdrLen := (pLen <= 125) ? 6 : 8
    frame := Buffer(hdrLen + pLen, 0)
    NumPut("UChar", 0x81, frame, 0)
    if (pLen <= 125) {
        NumPut("UChar", 0x80 | pLen, frame, 1)
        off := 2
    } else {
        NumPut("UChar", 0x80 | 126, frame, 1)
        NumPut("UChar", (pLen >> 8) & 0xFF, frame, 2)
        NumPut("UChar", pLen & 0xFF, frame, 3)
        off := 4
    }
    masks := [0x11, 0x22, 0x33, 0x44]
    Loop 4
        NumPut("UChar", masks[A_Index], frame, off + A_Index - 1)
    Loop pLen {
        i := A_Index - 1
        NumPut("UChar", NumGet(pBuf, i, "UChar") ^ masks[Mod(i, 4) + 1], frame, hdrLen + i)
    }
    DllCall("ws2_32\send", "Ptr", sock, "Ptr", frame.Ptr, "Int", hdrLen + pLen, "Int", 0, "Int")
}

LoopbackWsPumpAndFind(sock, pattern, timeoutMs := 2000) {
    static accText := Map()
    if (!accText.Has(sock))
        accText[sock] := ""
    rx := Buffer(16384, 0)
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        n := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", rx.Ptr, "Int", 16384, "Int", 0, "Int")
        if (n > 0) {
            ; Scan raw ASCII/UTF-8 bytes cleanly for readable JSON tokens inside unmasked server frames
            Loop n {
                b := NumGet(rx, A_Index - 1, "UChar")
                accText[sock] .= (b >= 32 && b <= 126) ? Chr(b) : " "
            }
        }
        if (InStr(accText[sock], pattern))
            return true
        Sleep 15
    }
    return InStr(accText[sock], pattern) > 0
}

wsSock := LoopbackWsOpen(bridgePort, "/ws?code=WEB-761&deviceId=dev-web-1&deviceName=WebTest&platform=Web")
gotAuth := LoopbackWsPumpAndFind(wsSock, "auth_ok", 2500)
Assert("Loopback WS authenticates Web Remote client", gotAuth && bridge.pairedDevices.Has("dev-web-1"))
gotObsFb := LoopbackWsPumpAndFind(wsSock, '"obsFallback":{"port":4455,"targetMic":"Mic/Aux","password":"TopSecretOBS4455!"}', 1000)
Assert("Post-auth auth_ok includes obsFallback metadata when EnableWS=true (M5A.3)", gotObsFb)

LoopbackWsSendText(wsSock, '{"type":"ping"}')
gotPong := LoopbackWsPumpAndFind(wsSock, '"type":"pong"', 2000)
Assert("Client ping receives server pong for 3s watchdog (M5A.3)", gotPong)

LoopbackWsSendText(wsSock, '{"type":"toggle_mute","deviceId":"dev-web-1","source":"web_remote"}')
gotAck := LoopbackWsPumpAndFind(wsSock, "toggle_mute", 2000)
Assert("toggle_mute triggers host OBS ToggleInputMute & queues ack/state (#1)", gotAck && mockObsSent.Length >= 1 && InStr(mockObsSent[1], "ToggleInputMute") > 0)

LoopbackWsSendText(wsSock, '{"type":"disconnect","deviceId":"dev-web-1","source":"web_remote"}')
gotDisc := LoopbackWsPumpAndFind(wsSock, "disconnected", 2000)
tDiscEnd := A_TickCount + 1500
while (A_TickCount < tDiscEnd && (bridge.pairedDevices.Has("dev-web-1") || bridge.GetConnectedClientCount() > 0))
    Sleep 15
try DllCall("ws2_32\closesocket", "Ptr", wsSock)
Assert("WS disconnect immediately unregisters Web Remote client, token & active count (#7)", gotDisc && !bridge.pairedDevices.Has("dev-web-1") && bridge.validTokens.Count == 0 && bridge.GetConnectedClientCount() == 0)

StopHostCompanionBridge()
try FileDelete(tmpIni)

FileAppend("PASS=" PassCount " FAIL=" FailCount "`n", "*")
ExitApp(FailCount > 0 ? 1 : 0)
