; ==============================================================================
; Test Suite: test_v733_slide_telemetry.ahk
; Description: Verifies v7.3.3 PowerPoint COM Slide/Notes telemetry, 2000-char
;              notes cap, SessionTimeline slide logging, StartPowerPointSlideshow,
;              HostBridge slide JSON + slide_start, and PDF/Browser fallback keys.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\SessionTimeline.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"

global g_IsTestMode := true

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

class MockComCollection {
    items := Map()
    Count := 0
    __New(countVal, mapItems := "") {
        this.Count := countVal
        if IsObject(mapItems)
            this.items := mapItems
    }
    Item(idx) {
        return this.items.Has(idx) ? this.items[idx] : ""
    }
}

tmpIni := A_Temp "\PresenterSync_v733_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

origAutosave := SessionTimeline.EnableAutosave
SessionTimeline.EnableAutosave := false
SessionTimeline.Entries := []

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. PollPowerPointSlideTelemetry with active slideshow, 2000-char notes cap, & SessionTimeline entry
longNotes := ""
Loop 250
    longNotes .= "0123456789" ; 2500 chars

phMap := Map(2, { TextFrame: { TextRange: { Text: longNotes } } })
mockSlide := {
    Shapes: { Title: { TextFrame: { TextRange: { Text: "  Q4 Architecture Roadmap  " } } } },
    NotesPage: { Shapes: { Placeholders: MockComCollection(2, phMap) } }
}
mockSsWin := {
    View: { CurrentShowPosition: 3, Slide: mockSlide },
    Presentation: { Slides: { Count: 18 } }
}
mockPpt := {
    SlideShowWindows: MockComCollection(1, Map(1, mockSsWin)),
    ActivePresentation: { Slides: { Count: 18 }, SlideShowSettings: { ran: false, Run: (self) => (self.ran := true) } }
}

okPoll := PollPowerPointSlideTelemetry(st, mockPpt)
AssertTrue(okPoll == true && st.slideIndex == 3 && st.slideTotal == 18, "PollPowerPointSlideTelemetry reads slideIndex=3 and slideTotal=18")
AssertTrue(st.slideTitle = "Q4 Architecture Roadmap", "PollPowerPointSlideTelemetry trims slideTitle")
AssertTrue(StrLen(st.slideNotes) == 2000, "PollPowerPointSlideTelemetry caps speaker notes at 2000 chars")
AssertTrue(SessionTimeline.Entries.Length == 1 && StrLower(SessionTimeline.Entries[1].category) = "slide", "PollPowerPointSlideTelemetry logs SessionTimeline slide entry on slide change")

; Polling same slide index does not duplicate timeline entry
PollPowerPointSlideTelemetry(st, mockPpt)
AssertTrue(SessionTimeline.Entries.Length == 1, "Polling same slideIndex does not duplicate SessionTimeline entry")

; 2. HostBridge _BuildMuteStateJson includes slide fields & StartPowerPointSlideshow
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
json := bridge._BuildMuteStateJson()
AssertTrue(InStr(json, '"slideIndex":3') && InStr(json, '"slideTotal":18'), "_BuildMuteStateJson includes slideIndex and slideTotal")
AssertTrue(InStr(json, '"slideTitle":"Q4 Architecture Roadmap"'), "_BuildMuteStateJson includes slideTitle")
AssertTrue(InStr(json, '"slideNotes":"0123456789'), "_BuildMuteStateJson includes slideNotes")

okStart := StartPowerPointSlideshow(mockPpt)
AssertTrue(okStart == true && mockPpt.ActivePresentation.SlideShowSettings.ran == true, "StartPowerPointSlideshow invokes ActivePresentation.SlideShowSettings.Run()")

; When slideshow ends (Count == 0), telemetry resets to 0 / ""
mockPptEnded := { SlideShowWindows: MockComCollection(0) }
okEnd := PollPowerPointSlideTelemetry(st, mockPptEnded)
AssertTrue(okEnd == false && st.slideIndex == 0 && st.slideTotal == 0 && st.slideTitle = "" && st.slideNotes = "", "PollPowerPointSlideTelemetry resets all 4 fields when slideshow ends")

; 3. PDF / Browser / Google Slides fallback slide key selection
AssertTrue(GetFallbackSlideKey("chrome.exe", "next") = "{Right}", "Chrome next -> {Right}")
AssertTrue(GetFallbackSlideKey("msedge.exe", "prev") = "{Left}", "Edge prev -> {Left}")
AssertTrue(GetFallbackSlideKey("Acrobat.exe", "next") = "{PgDn}", "Acrobat next -> {PgDn}")
AssertTrue(GetFallbackSlideKey("SumatraPDF.exe", "prev") = "{PgUp}", "SumatraPDF prev -> {PgUp}")
AssertTrue(GetFallbackSlideKey("notepad.exe", "next") = "", "Non-presentation app returns empty key")

fbBrowser := TryDispatchFallbackSlideKey("next", { exe: "brave.exe", active: true }, true)
AssertTrue(fbBrowser.handled == true && fbBrowser.key = "{Right}", "TryDispatchFallbackSlideKey dispatches {Right} for Brave browser")

fbPdf := TryDispatchFallbackSlideKey("prev", { exe: "FoxitPDFReader.exe", active: true }, true)
AssertTrue(fbPdf.handled == true && fbPdf.key = "{PgUp}", "TryDispatchFallbackSlideKey dispatches {PgUp} for Foxit PDF Reader")

fbWps := TryDispatchFallbackSlideKey("next", { exe: "wpp.exe", active: true }, true)
AssertTrue(fbWps.handled == true && fbWps.key = "{PgDn}", "M6.3: TryDispatchFallbackSlideKey dispatches {PgDn} for WPS Presentation")

fbImp := TryDispatchFallbackSlideKey("prev", { exe: "soffice.bin", active: true }, true)
AssertTrue(fbImp.handled == true && fbImp.key = "{PgUp}", "M6.3: TryDispatchFallbackSlideKey dispatches {PgUp} for LibreOffice Impress")

fbWb := TryDispatchFallbackSlideKey("next", { exe: "mswhiteboard.exe", active: true }, true)
AssertTrue(fbWb.handled == true && fbWb.key = "{PgDn}", "M6.3: TryDispatchFallbackSlideKey dispatches {PgDn} for Microsoft Whiteboard")

SessionTimeline.EnableAutosave := origAutosave
SessionTimeline.Entries := []
cfg.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
