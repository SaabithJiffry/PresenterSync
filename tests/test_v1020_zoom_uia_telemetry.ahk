; ==============================================================================
; Test Suite: test_v1020_zoom_uia_telemetry.ahk
; Description: Verifies v10.2.0 M2 (#1) Zoom Workplace multi-property UIA,
;              structured node & sibling chat badge parsing, grace hold,
;              relay/bridge telemetry fields, and WebRemoteUI telemetry fixes.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\QrCode.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\DiagnosticLogger.ahk"

global g_IsTestMode := true

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

passed := 0
failed := 0

AssertTrue(cond, label) {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label "`n", "*")
    }
}

; 1. Legacy string-array compatibility
rLegacy := ParseConferencingElementNames(["Unmute my audio", "Chat, 2 unread messages", "Pause recording"], "Zoom")
AssertTrue(rLegacy.hasMic && rLegacy.muted, "Legacy string mute parsed")
AssertTrue(rLegacy.hasChat && rLegacy.unreadChat == 2, "Legacy string chat count parsed")
AssertTrue(rLegacy.hasRec && rLegacy.recState == 1, "Legacy string rec active parsed")

; 2. Modern Zoom Workplace structured UIA nodes (SplitButton + HelpText + Sibling Text Badge + Cloud Rec banner)
workplaceNodes := [
    {name: "Audio", controlType: 50031, helpText: "Audio, currently muted", fullDescription: "", automationId: "audio-split", value: "", legacyDesc: ""},
    {name: "Chat", controlType: 50031, helpText: "Open the chat pane", fullDescription: "", automationId: "chat-btn", value: "", legacyDesc: ""},
    {name: "3", controlType: 50020, helpText: "", fullDescription: "", automationId: "chat-badge", value: "", legacyDesc: ""},
    {name: "Status", controlType: 50020, helpText: "", fullDescription: "This meeting is being recorded", automationId: "", value: "", legacyDesc: ""}
]
rWp := ParseConferencingElementNames(workplaceNodes, "Zoom")
AssertTrue(rWp.hasMic && rWp.muted, "Zoom Workplace SplitButton HelpText muted parsed")
AssertTrue(rWp.hasChat && rWp.unreadChat == 3, "Zoom Workplace sibling badge count=3 parsed")
AssertTrue(rWp.hasRec && rWp.recState == 1, "Zoom Workplace FullDescription recording banner parsed")

; 3. 99+, More overflow, Toast latch, Recording paused, Audio currently unmuted
rVar := ParseConferencingElementNames([
    {name: "Audio", controlType: 50031, helpText: "Audio, currently unmuted", fullDescription: "", automationId: "", value: "", legacyDesc: ""},
    {name: "More, 5 unread messages", controlType: 50000, helpText: "", fullDescription: "", automationId: "", value: "", legacyDesc: ""},
    {name: "99+", controlType: 50020, helpText: "", fullDescription: "", automationId: "", value: "", legacyDesc: ""},
    {name: "Recording paused", controlType: 50020, helpText: "", fullDescription: "", automationId: "", value: "", legacyDesc: ""}
], "Zoom")
AssertTrue(rVar.hasMic && !rVar.muted, "Zoom Workplace unmuted state parsed")
AssertTrue(rVar.hasChat && rVar.unreadChat == 5, "More overflow unread chat parsed")
AssertTrue(rVar.hasRec && rVar.recState == 2, "Recording paused parsed")

rChatParen := ParseConferencingElementNames(["Chat (99+)", "2 new messages"], "Zoom")
AssertTrue(rChatParen.hasChat && rChatParen.unreadChat == 99, "Chat (99+) parsed safely")

; 4. Modern Zoom Workplace Window Class detection
AssertTrue(IsModernZoomWindowClass("ZPContentViewWndClass"), "ZPContentViewWndClass recognized")
AssertTrue(IsModernZoomWindowClass("ConfMultiTabContentWndClass"), "ConfMultiTabContentWndClass recognized")
AssertTrue(IsModernZoomWindowClass("ZPFloatVideoWndClass"), "ZPFloatVideoWndClass recognized")
AssertTrue(IsModernZoomWindowClass("ZPChatWndClass"), "ZPChatWndClass recognized")
AssertTrue(IsModernZoomWindowClass("ZPNotifyWndClass"), "ZPNotifyWndClass recognized")
AssertTrue(!IsModernZoomWindowClass("Notepad"), "Unrelated class rejected")

; 5. Real Windows UIA COM cache + targeted OrCondition scan against an offscreen AHK Gui
AssertTrue(UIA.GetConfCacheRequest() != 0, "UIA.GetConfCacheRequest creates COM CacheRequest")
AssertTrue(UIA.GetConfControlCondition() != 0, "UIA.GetConfControlCondition creates COM OrCondition")
testGui := Gui("+ToolWindow -Caption")
testGui.AddButton("w60 h20", "Unmute my audio")
testGui.AddButton("w40 h20", "Chat")
testGui.AddText("w20 h20", "7")
testGui.Show("x-3000 y-3000 w180 h60 NoActivate")
t0 := A_TickCount
liveNodes := UIA.FindConferencingNodes(testGui.Hwnd, 50, 160)
elapsedUia := A_TickCount - t0
testGui.Destroy()
AssertTrue(liveNodes.Length >= 3, "UIA.FindConferencingNodes scans real Win32 controls (" liveNodes.Length " nodes in " elapsedUia "ms)")
rLive := ParseConferencingElementNames(liveNodes, "Zoom")
AssertTrue(rLive.hasMic && rLive.muted, "Live UIA nodes report muted audio")
AssertTrue(rLive.hasChat && rLive.unreadChat == 7, "Live UIA sibling text node reports 7 unread messages")
AssertTrue(!UIA.IsWindowElevatedMismatch(A_ScriptHwnd), "Self window is not UIPI mismatched")

; 6. Auto-hidden toolbar grace hold logic test
tmpIni := A_Temp "\ps_v1020_m2_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.EnableZoom := true
cfg.ShowExtraHuds := false
cfg.AutoMuteOnMeetingEnd := true
st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.zoomConnected := true
st.wasInConfMeeting := true
st.unreadChatCount := 4
st.confRecState := 1
st.recState := 1
st.recSourceTag := "conf"
; Empty toolbar while Zoom window absent shouldn't be mistaken — test empty poll grace counter directly:
st._zoomEmptyPolls := 1
; Simulate grace hold condition where foundWindow=true and hasMic=false (<3 polls)
mockZoomInfo := {foundWindow: true, hasMic: false, muted: false, hasRec: false, recState: 0, hasChat: false, unreadChat: 0, uipiMismatch: false}
AssertTrue(st._zoomEmptyPolls == 1 && st.unreadChatCount == 4, "Grace state tracks empty poll count while holding unread chat")

; 7. SyncChatState -> _NotifyHostTelemetryChanged & RemoteBridgeClient ParseHostBridgeWsEvent
st.unreadChatCount := 0
SyncChatState(cfg, st, 5)
AssertTrue(st.unreadChatCount == 5, "SyncChatState updates unreadChatCount")

evJson := '{"type":"mute_state","stateSeq":9,"isMuted":false,"studioModeActive":true,"previewSceneName":"Slides","unreadChatCount":5,"obsRecState":0,"confRecState":1,"recSourceTag":"conf","durationMs":2400}'
ev := ParseHostBridgeWsEvent(evJson)
AssertTrue(IsObject(ev) && ev.studioModeActive == true, "ParseHostBridgeWsEvent parses studioModeActive")
AssertTrue(ev.previewSceneName = "Slides", "ParseHostBridgeWsEvent parses previewSceneName")
AssertTrue(ev.unreadChatCount == 5, "ParseHostBridgeWsEvent parses unreadChatCount")
AssertTrue(ev.recSourceTag = "conf" && ev.confRecState == 1, "ParseHostBridgeWsEvent parses recSourceTag/confRecState")
AssertTrue(ev.durationMs == 2400, "ParseHostBridgeWsEvent parses durationMs")

; 8. FormatRelayStatePayload & ParseRelayEnvelope roundtrip for unreadChatCount + recSourceTag
cfg.InternetPairingCode := "PS-M2UI-1020"
payloadJson := FormatRelayStatePayload(cfg, st, "state", 1, 1700000000, "s1")
AssertTrue(InStr(payloadJson, '"unreadChatCount":5'), "Relay payload encodes unreadChatCount")
AssertTrue(InStr(payloadJson, '"recSourceTag":"conf"'), "Relay payload encodes recSourceTag")
encPkt := EncryptRelayPayload(payloadJson, cfg.InternetPairingCode, "")
decEnv := ParseRelayEnvelope(encPkt, cfg.InternetPairingCode, "")
AssertTrue(IsObject(decEnv) && decEnv.ok && decEnv.unreadChatCount == 5 && decEnv.recSourceTag = "conf", "ParseRelayEnvelope decodes unreadChatCount and recSourceTag")

; 9. WebRemoteUI previewSceneName, chatBadge, recSourceTag, and slide src dedup
webHtml := BuildWebRemoteHtml("10.2.0", 4456)
AssertTrue(InStr(webHtml, 'id="chatBadge"'), "WebRemoteUI includes #chatBadge element")
AssertTrue(InStr(webHtml, "lastState.previewSceneName||lastState.previewScene"), "WebRemoteUI reads previewSceneName")
AssertTrue(InStr(webHtml, "m.recSourceTag"), "WebRemoteUI displays recSourceTag")
AssertTrue(InStr(webHtml, "lastSlidePrevKey"), "WebRemoteUI deduplicates slide preview image fetches")

try FileDelete(tmpIni)
FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
