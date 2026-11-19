; ==============================================================================
; Test Suite: test_v761_web_remote.ahk
; Description: Automated unit + live loopback HTTP test for Zero-Install Browser
;              Web Remote (Lib\WebRemoteUI.ahk + HostCompanionBridge GET / & /remote)
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

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

; 1. Pure HTML builder checks
html := BuildWebRemoteHtml("7.6.1", 14472)
Assert("BuildWebRemoteHtml returns valid HTML5", InStr(html, "<!DOCTYPE html>") && InStr(html, "</html>"))
Assert("BuildWebRemoteHtml embeds version & port", InStr(html, "7.6.1") && InStr(html, "14472"))
for _, token in ["toggle_mute", "transition_scene", "slide_start", "ppt_next", "ppt_prev", "toggle_standby", "timer_start", "stage_nudge", "/ws"] {
    Assert("BuildWebRemoteHtml includes control/protocol '" token "'", InStr(html, token) > 0)
}

; 2. Live loopback HostCompanionBridge HTTP checks on port 14472
tmpIni := A_Temp "\ps_v761_web_remote_test.ini"
try FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.SessionPairingCode := "WEB-761"
state := {
    isMuted: false,
    obsConnected: false,
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
        return {status: 0, contentType: "", body: "TIMEOUT"}
    return {
        status: req.Status,
        contentType: req.GetResponseHeader("Content-Type"),
        body: req.ResponseText
    }
}

resRoot := HttpGetAsync("http://127.0.0.1:" bridgePort "/")
Assert("GET / returns 200 OK", resRoot.status = 200, "status=" resRoot.status)
Assert("GET / returns text/html", InStr(StrLower(resRoot.contentType), "text/html") > 0, resRoot.contentType)
Assert("GET / returns full Web Remote HTML", InStr(resRoot.body, "PresenterSync Web Remote") > 0 && InStr(resRoot.body, "</html>") > 0)

resRemote := HttpGetAsync("http://127.0.0.1:" bridgePort "/remote")
Assert("GET /remote returns 200 OK", resRemote.status = 200, "status=" resRemote.status)
Assert("GET /remote returns full Web Remote HTML", InStr(resRemote.body, "PresenterSync Web Remote") > 0 && InStr(resRemote.body, "</html>") > 0)

resHealth := HttpGetAsync("http://127.0.0.1:" bridgePort "/health")
Assert("GET /health returns 200 OK", resHealth.status = 200, "status=" resHealth.status)
Assert("GET /health still returns JSON", InStr(StrLower(resHealth.contentType), "application/json") > 0 && InStr(resHealth.body, '"ok":true') > 0)

StopHostCompanionBridge()
try FileDelete(tmpIni)

FileAppend("PASS=" PassCount " FAIL=" FailCount "`n", "*")
ExitApp(FailCount > 0 ? 1 : 0)
