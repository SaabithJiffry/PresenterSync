; ==============================================================================
; Script: PresenterSync
; Description: OBS WebSocket and PowerPoint synchronization tool with system tray UI
; Version: 1.3.0
; Author: Saabith Jiffry
; License: MIT 
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"
SetKeyDelay 50, 50 

#Include <WebSocket>
#Include <UIA>

; === CONFIGURATION & MEMORY ===
global ConfigFile := A_ScriptDir "\MicOverlay_Config.ini"

ReadIniBool(section, key, defaultValue := 0) {
    value := IniRead(ConfigFile, section, key, defaultValue)

    switch (StrLower(value)) {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off", "":
            return false
        default:
            return !!Integer(value)
    }
}

WriteIniBool(section, key, value) {
    IniWrite(value ? 1 : 0, ConfigFile, section, key)
}

SetTrayCheck(itemText, enabled) {
    if (enabled)
        A_TrayMenu.Check(itemText)
    else
        A_TrayMenu.Uncheck(itemText)
}

global AudioRoutingMode := Integer(IniRead(ConfigFile, "Settings", "AudioRoutingMode", 0))
global ObsMuteHotkey := IniRead(ConfigFile, "Settings", "ObsHotkey", "None")
global ObsRecHotkey := IniRead(ConfigFile, "Settings", "ObsRecHotkey", "^F9")
global ObsPauseHotkey := IniRead(ConfigFile, "Settings", "ObsPauseHotkey", "^F10")
global ZoomMuteHotkey := IniRead(ConfigFile, "Settings", "ZoomMuteHotkey", "!a")
global ZoomRecHotkey := IniRead(ConfigFile, "Settings", "ZoomRecHotkey", "")
if (ZoomRecHotkey = "") {
    ZoomRecHotkey := "!r"
    IniWrite(ZoomRecHotkey, ConfigFile, "Settings", "ZoomRecHotkey")
}
global ZoomPauseHotkey := IniRead(ConfigFile, "Settings", "ZoomPauseHotkey", "")
if (ZoomPauseHotkey = "") {
    ZoomPauseHotkey := "!p"
    IniWrite(ZoomPauseHotkey, ConfigFile, "Settings", "ZoomPauseHotkey")
}
global obsPassword := IniRead(ConfigFile, "Settings", "ObsPassword", "")
global targetMicName := IniRead(ConfigFile, "Settings", "TargetMicName", "Mic/Aux")

global EnablePPT := ReadIniBool("Settings", "EnablePPT")
global EnableMicOnly := ReadIniBool("Settings", "EnableMicOnly")
global EnableWS := ReadIniBool("Settings", "EnableWS")
global EnableZoom := ReadIniBool("Settings", "EnableZoom")

if (EnableWS && EnableZoom) {
    EnableZoom := false
    WriteIniBool("Settings", "EnableZoom", false)
}

global ShowIndicator := ReadIniBool("Settings", "ShowIndicator", true)
global ShowText := ReadIniBool("Settings", "ShowText")
global MonoIcon := ReadIniBool("Settings", "MonoIcon")
global SleekCorners := ReadIniBool("Settings", "SleekCorners")
global AggressivePulse := ReadIniBool("Settings", "AggressivePulse")
global OpacityLevel := Integer(IniRead(ConfigFile, "Settings", "OpacityLevel", 220))
global IndicatorScale := Float(IniRead(ConfigFile, "Settings", "IndicatorScale", 1.0))
global FirstRun := ReadIniBool("Settings", "FirstRun", true)

; --- POINTER INTERCEPT SETTINGS ---
global CatchArrows := ReadIniBool("Pointer", "CatchArrows", true)
global CatchPg := ReadIniBool("Pointer", "CatchPg", true)
global CatchSpace := ReadIniBool("Pointer", "CatchSpace", true)
global CatchEnter := ReadIniBool("Pointer", "CatchEnter", true)
global CatchTab := ReadIniBool("Pointer", "CatchTab", true)
global CatchEsc := ReadIniBool("Pointer", "CatchEsc", true)

; --- NEW DYNAMIC HOTKEYS ---
global PptHotkey := IniRead(ConfigFile, "Settings", "PptHotkey", "^F12")
global WsHotkey := IniRead(ConfigFile, "Settings", "WsHotkey", "!F12")
global ZoomHotkey := IniRead(ConfigFile, "Settings", "ZoomHotkey", "^!F12")
global IndHotkey := IniRead(ConfigFile, "Settings", "IndHotkey", "^+F12")
global ExitHotkey := IniRead(ConfigFile, "Settings", "ExitHotkey", "!+F12")
global SuspendHotkey := IniRead(ConfigFile, "Settings", "SuspendHotkey", "^!+F12")
global HwMuteHotkey := IniRead(ConfigFile, "Settings", "HwMuteHotkey", "b") ; Pointer Mute Button

; 1. First-run / missing shortcut setup: Audio Routing Mode + shortcuts
if (AudioRoutingMode == 0
    || ((AudioRoutingMode == 1 || AudioRoutingMode == 3) && (ObsMuteHotkey = "None" || ObsMuteHotkey = ""))
    || ((AudioRoutingMode == 2 || AudioRoutingMode == 3) && ZoomMuteHotkey = "")) {
    PromptForSetup()
}

; 2. Boot-up check: If WS is enabled but password is missing, ask for it
if (EnableWS && obsPassword = "") {
    obsPassword := PromptForPassword()
    if (obsPassword != "") {
        IniWrite(obsPassword, ConfigFile, "Settings", "ObsPassword")
    } else {
        EnableWS := 0 
        IniWrite(0, ConfigFile, "Settings", "EnableWS")
    }
}

; 3. Show Help screen on very first launch
if (FirstRun) {
    IniWrite(0, ConfigFile, "Settings", "FirstRun")
    ShowHelpWindow()
}
; ==============================

; --- RESTORED VARIABLES ---
global obsWs := ""
global obsConnected := false
global zoomConnected := false
global IsSyncing := false
global zoomLastMuted := -1
global zoomRecGraceUntil := 0
global zoomSawRecControl := false

global isMuted := ReadIniBool("Settings", "IsMuted", false)
global recState := 0 ; 0 = NOT REC, 1 = REC, 2 = PAUSED
global studioModeActive := false
global currentSceneName := "Scene"
global unreadChatCount := 0
global baseAlpha := OpacityLevel     
global currentAlpha := baseAlpha
global breathDir := AggressivePulse ? -20 : -5      

global colorLive := "22C55E" 
global colorMuted := "EF4444" 
global borderLive := 0x5EC522  
global borderMuted := 0x4444EF 
global iconLive := "064E3B"   
global iconMuted := "540808"  

global recColorOff := "374151"
global recBorderOff := 0x514137
global recIconOff := "9CA3AF"
global recColorActive := "DC2626"
global recBorderActive := 0x2626DC
global recIconActive := "7F1D1D"
global recColorPaused := "D97706"
global recBorderPaused := 0x0677D9
global recIconPaused := "78350F"

global studioColorOff := "374151"
global studioBorderOff := 0x514137
global studioIconOff := "9CA3AF"
global studioColorOn := "7C3AED"
global studioBorderOn := 0xED3A7C
global studioIconOn := "4C1D95"
global sceneColor := "1E293B"
global sceneBorder := 0x3B291E

global chatColorClear := "374151"
global chatBorderClear := 0x514137
global chatIconClear := "9CA3AF"
global chatColorAlert := "2563EB"
global chatBorderAlert := 0xEB6325
global chatIconAlert := "1E3A8A"

; --- SETUP GUIS ---
PromptForSetup() {
    global AudioRoutingMode, ObsMuteHotkey, ZoomMuteHotkey, ConfigFile
    Suspend(True)

    setupGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Audio Setup")
    setupGui.OnEvent("Close", (*) => ExitApp())

    setupGui.Add("Text", "w280", "Select your Audio Routing Profile:")
    modes := [
        "1: Pro OBS Setup (VB-Cable)",
        "2: Standard Direct Mic (Zoom-Only)",
        "3: Dual App Sync (OBS + Zoom Direct)"
    ]
    initialMode := (AudioRoutingMode >= 1 && AudioRoutingMode <= 3) ? AudioRoutingMode : 1
    modeDrop := setupGui.Add("DropDownList", "w280 Choose" initialMode, modes)

    obsLbl := setupGui.Add("Text", "w280 y+15", "OBS Mute Shortcut:")
    obsVal := (ObsMuteHotkey != "None") ? ObsMuteHotkey : ""
    obsCtrl := setupGui.Add("Hotkey", "w280", obsVal)

    zoomLbl := setupGui.Add("Text", "w280 y+10", "Zoom Mute Shortcut (Default Alt+A):")
    zoomCtrl := setupGui.Add("Hotkey", "w280", ZoomMuteHotkey != "" ? ZoomMuteHotkey : "!a")

    btn := setupGui.Add("Button", "w280 Default y+15", "Save && Start")

    UpdateFieldStates(*) {
        sel := modeDrop.Value
        obsEnabled := (sel == 1 || sel == 3)
        zoomEnabled := (sel == 2 || sel == 3)
        obsLbl.Enabled := obsEnabled
        obsCtrl.Enabled := obsEnabled
        zoomLbl.Enabled := zoomEnabled
        zoomCtrl.Enabled := zoomEnabled
    }
    modeDrop.OnEvent("Change", UpdateFieldStates)
    UpdateFieldStates()

    SaveSetup(*) {
        sel := modeDrop.Value
        if ((sel == 1 || sel == 3) && obsCtrl.Value = "") {
            setupGui.Opt("+OwnDialogs")
            MsgBox("Please enter your OBS Mute shortcut.", "Setup", "Icon!")
            return
        }
        if ((sel == 2 || sel == 3) && zoomCtrl.Value = "") {
            setupGui.Opt("+OwnDialogs")
            MsgBox("Please enter your Zoom Mute shortcut.", "Setup", "Icon!")
            return
        }

        AudioRoutingMode := sel
        IniWrite(AudioRoutingMode, ConfigFile, "Settings", "AudioRoutingMode")

        if (sel == 1 || sel == 3) {
            ObsMuteHotkey := obsCtrl.Value
            IniWrite(ObsMuteHotkey, ConfigFile, "Settings", "ObsHotkey")
        }
        if (sel == 2 || sel == 3) {
            ZoomMuteHotkey := zoomCtrl.Value
            IniWrite(ZoomMuteHotkey, ConfigFile, "Settings", "ZoomMuteHotkey")
        }

        Suspend(False)
        setupGui.Destroy()
    }

    btn.OnEvent("Click", SaveSetup)
    setupGui.Show()
    WinWaitClose(setupGui.Hwnd)
}

PromptForPassword() {
    pwGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "WebSocket Setup")
    pwGui.OnEvent("Close", (*) => pwGui.Destroy()) 
    
    pwGui.Add("Text", "w250", "Enter your OBS WebSocket Password:")
    pwCtrl := pwGui.Add("Edit", "w250 Password")
    btn := pwGui.Add("Button", "w250 Default y+15", "Save & Connect")
    
    savedPw := ""
    btn.OnEvent("Click", SavePw)
    
    SavePw(*) {
        if (pwCtrl.Value = "") {
            MsgBox("Password cannot be empty.", "Setup", "Icon!")
            return
        }
        savedPw := pwCtrl.Value
        pwGui.Destroy()
    }
    
    pwGui.Show()
    WinWaitClose(pwGui.Hwnd)
    return savedPw
}

FormatHK(hk) {
    str := StrReplace(hk, "+", "Shift + ")
    str := StrReplace(str, "^", "Ctrl + ")
    str := StrReplace(str, "!", "Alt + ")
    str := StrReplace(str, "#", "Win + ")
    return str
}

ShowHelpWindow(*) {
    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Help & Guide")
    helpGui.SetFont("s10 w400", "Segoe UI")
    
    ; Create a tabbed interface (420px wide, 290px tall)
    tabs := helpGui.Add("Tab3", "w420 h290", ["Shortcuts", "Pointer Modes", "OBS & Zoom Sync", "Pro Tips"])
    
    ; --- TAB 1: SHORTCUTS ---
    tabs.UseTab(1)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Global Keyboard Shortcuts")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+15", FormatHK(PptHotkey) " :  Cycle Pointer Modes")
    helpGui.Add("Text", "x25 y+10", FormatHK(WsHotkey) " :  Toggle OBS WebSocket Sync")
    helpGui.Add("Text", "x25 y+10", FormatHK(ZoomHotkey) " :  Toggle Zoom Monitoring")
    helpGui.Add("Text", "x25 y+10", FormatHK(IndHotkey) " :  Hide/Unhide Indicator")
    helpGui.Add("Text", "x25 y+10", FormatHK(SuspendHotkey) " :  Suspend All Hotkeys")
    helpGui.Add("Text", "x25 y+10", FormatHK(ExitHotkey) " :  Exit PresenterSync")
    
    helpGui.SetFont("s9 italic cGray")
    helpGui.Add("Text", "x25 y+15 w370", "Note: You can rebind these shortcuts in the Settings menu.")
    
    ; --- TAB 2: POINTER MODES ---
    tabs.UseTab(2)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Hardware Pointer Controls")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "1. Full PPT + Mute:`nRoutes your clicker to PowerPoint while still allowing the hardware mute button to trigger OBS.`n`n2. Pointer Mute Only:`nBypasses PowerPoint completely. Your clicker only controls the mute overlay.`n`n* If you need to type normally while presenting, go to Settings > 'Configure Pointer Intercepts' to disable specific keys (like Space or Enter).")

    ; --- TAB 3: OBS & ZOOM SYNC ---
    tabs.UseTab(3)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "OBS WebSocket & Zoom UIA Sync")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "• OBS WebSocket v5: Enable in OBS (Tools > WebSocket Server Settings) for instant 2-way mic sync.`n`n• Zoom UIA Monitoring: Provides 2-way background sync with Zoom even if a host mutes you or you click Mute in Zoom.`n`n• Zoom Requirement: In Zoom Settings > Accessibility (or General), check 'Always show meeting controls' so PresenterSync can read Zoom's toolbar reliably in the background.")

    ; --- TAB 4: PRO TIPS ---
    tabs.UseTab(4)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Customizing & Smooth Animations")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "• Repositioning HUD: Hold Left Click on the indicator to drag it anywhere. Coordinates save automatically.`n`n• Appearance: Right-click the tray icon > 'Indicator Appearance' to customize labels, opacity, scale, or pulse.`n`n• Smooth PPT Animations: To prevent Windows from throttling background animations, capture the Slideshow in OBS using Window Capture ('Windows 10 1903+') and set POWERPNT.EXE to 'High performance' in Windows Graphics Settings.")

    tabs.UseTab() ; End tab definitions
    
    ; Add the close button centered (x160) and explicitly placed below the Tab control (y310)
    btn := helpGui.Add("Button", "w100 x160 y310 Default", "Got it!")
    btn.OnEvent("Click", (*) => helpGui.Destroy())
    
    helpGui.Show("AutoSize")
}

ShowAboutWindow(*) {
    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync")
    
    iconSource := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\PresenterSync.ico"
    
    if FileExist(iconSource) {
        aboutGui.Add("Picture", "x143 y15 w64 h64", iconSource)
    }
    
    aboutGui.SetFont("s16 w700", "Segoe UI")
    aboutGui.Add("Text", "x10 w330 Center y+15", "PresenterSync")
    
    aboutGui.SetFont("s10 w400")
    aboutGui.Add("Text", "x10 w330 Center y+5", "Version 1.3.0")
    aboutGui.Add("Text", "x10 w330 Center y+15", "Created by Saabith Jiffry")
    
    ; Two 110px buttons with 10px spacing = 230px total. Centered in 350px width (60px padding)
    gitBtn := aboutGui.Add("Button", "w110 x60 y+25", "GitHub Repo")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))
    
    closeBtn := aboutGui.Add("Button", "w110 x+10 Default", "Close")
    closeBtn.OnEvent("Click", (*) => aboutGui.Destroy())
    
    aboutGui.Show("AutoSize")
}

ChangeAppHotkeysUI(*) {
    Suspend(True) 

    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit App Shortcuts")
    hkGui.OnEvent("Close", (*) => Suspend(False)) 
    
    hkGui.Add("Text", "w150", "Cycle Pointer Mode:")
    pptCtrl := hkGui.Add("Hotkey", "x+10 w120", PptHotkey)
    
    hkGui.Add("Text", "xm w150", "Toggle OBS WebSocket:")
    wsCtrl := hkGui.Add("Hotkey", "x+10 w120", WsHotkey)

    hkGui.Add("Text", "xm w150", "Toggle Zoom Monitor:")
    zoomHkCtrl := hkGui.Add("Hotkey", "x+10 w120", ZoomHotkey)
    
    hkGui.Add("Text", "xm w150", "Toggle Indicator:")
    indCtrl := hkGui.Add("Hotkey", "x+10 w120", IndHotkey)

    hkGui.Add("Text", "xm w150", "Suspend Hotkeys:")
    suspCtrl := hkGui.Add("Hotkey", "x+10 w120", SuspendHotkey)
    
    hkGui.Add("Text", "xm w150", "Exit PresenterSync:")
    exitCtrl := hkGui.Add("Hotkey", "x+10 w120", ExitHotkey)
    
    btn := hkGui.Add("Button", "xm w280 Default y+15", "Save && Restart")
    btn.OnEvent("Click", SaveAppHk)
    
    SaveAppHk(*) {
        if (pptCtrl.Value = "" || wsCtrl.Value = "" || zoomHkCtrl.Value = "" || indCtrl.Value = "" || exitCtrl.Value = "") {
            hkGui.Opt("+OwnDialogs") ; Forces the MsgBox to appear on top
            MsgBox("Shortcuts cannot be left blank.", "Error", "Icon!")
            return
        }
        IniWrite(pptCtrl.Value, ConfigFile, "Settings", "PptHotkey")
        IniWrite(wsCtrl.Value, ConfigFile, "Settings", "WsHotkey")
        IniWrite(zoomHkCtrl.Value, ConfigFile, "Settings", "ZoomHotkey")
        IniWrite(indCtrl.Value, ConfigFile, "Settings", "IndHotkey")
        IniWrite(suspCtrl.Value, ConfigFile, "Settings", "SuspendHotkey")
        IniWrite(exitCtrl.Value, ConfigFile, "Settings", "ExitHotkey")
        Reload() 
    }
    
    hkGui.Show()
}

ChangeZoomShortcutsUI(*) {
    Suspend(True)

    zmGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit Zoom Shortcuts")
    zmGui.OnEvent("Close", (*) => Suspend(False))

    zmGui.Add("Text", "w280", "Zoom Mute Shortcut (Default Alt+A):")
    muteCtrl := zmGui.Add("Hotkey", "w280", ZoomMuteHotkey)

    zmGui.Add("Text", "w280 y+10", "Start/Stop Recording Shortcut (Default Alt+R):")
    recCtrl := zmGui.Add("Hotkey", "w280", ZoomRecHotkey)

    zmGui.Add("Text", "w280 y+10", "Pause/Resume Recording Shortcut (Default Alt+P):")
    pauseCtrl := zmGui.Add("Hotkey", "w280", ZoomPauseHotkey)

    btn := zmGui.Add("Button", "w280 Default y+15", "Save && Restart")

    btn.OnEvent("Click", SaveZoomHk)

    SaveZoomHk(*) {
        if (muteCtrl.Value = "") {
            zmGui.Opt("+OwnDialogs")
            MsgBox("Zoom Mute shortcut cannot be empty.", "Error", "Icon!")
            return
        }
        IniWrite(muteCtrl.Value, ConfigFile, "Settings", "ZoomMuteHotkey")
        IniWrite(recCtrl.Value != "" ? recCtrl.Value : "!r", ConfigFile, "Settings", "ZoomRecHotkey")
        IniWrite(pauseCtrl.Value != "" ? pauseCtrl.Value : "!p", ConfigFile, "Settings", "ZoomPauseHotkey")
        Reload()
    }

    zmGui.Show()
}

SetRoutingMode(mode) {
    global AudioRoutingMode, ObsMuteHotkey, ZoomMuteHotkey, ConfigFile
    IniWrite(mode, ConfigFile, "Settings", "AudioRoutingMode")
    if ((mode == 2 || mode == 3) && ZoomMuteHotkey = "")
        IniWrite("!a", ConfigFile, "Settings", "ZoomMuteHotkey")
    Reload()
}

ChangeObsSettingsUI(*) {
    Suspend(True)

    obsGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "OBS Settings")
    obsGui.OnEvent("Close", (*) => Suspend(False))

    obsGui.Add("Text", "w280", "OBS Mute Shortcut:")
    muteCtrl := obsGui.Add("Hotkey", "w280", (ObsMuteHotkey != "None") ? ObsMuteHotkey : "")

    obsGui.Add("Text", "w280 y+10", "Start/Stop Recording Shortcut:")
    recCtrl := obsGui.Add("Hotkey", "w280", ObsRecHotkey)

    obsGui.Add("Text", "w280 y+10", "Pause/Resume Recording Shortcut:")
    pauseCtrl := obsGui.Add("Hotkey", "w280", ObsPauseHotkey)

    obsGui.Add("Text", "w280 y+10", "Exact OBS Audio Source Name (e.g., Mic/Aux):")
    micCtrl := obsGui.Add("Edit", "w280", targetMicName)

    btn := obsGui.Add("Button", "w280 Default y+15", "Save && Restart")
    btn.OnEvent("Click", SaveObsSettings)

    SaveObsSettings(*) {
        if (muteCtrl.Value = "" || micCtrl.Value = "") {
            obsGui.Opt("+OwnDialogs")
            MsgBox("OBS Mute shortcut and Audio Source Name cannot be empty.", "Error", "Icon!")
            return
        }
        IniWrite(muteCtrl.Value, ConfigFile, "Settings", "ObsHotkey")
        IniWrite(recCtrl.Value != "" ? recCtrl.Value : "^F9", ConfigFile, "Settings", "ObsRecHotkey")
        IniWrite(pauseCtrl.Value != "" ? pauseCtrl.Value : "^F10", ConfigFile, "Settings", "ObsPauseHotkey")
        IniWrite(micCtrl.Value, ConfigFile, "Settings", "TargetMicName")
        Reload()
    }

    obsGui.Show()
}

ChangeHwMuteHotkeyUI(*) {
    Suspend(True) 
    
    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit Pointer Mute Button")
    hkGui.OnEvent("Close", (*) => Suspend(False)) 
    
    hkGui.Add("Text", "w250", "Focus the box below and press the button on your presentation clicker:")
    hkCtrl := hkGui.Add("Hotkey", "w250", HwMuteHotkey)
    btn := hkGui.Add("Button", "w250 Default y+15", "Save && Restart")
    
    btn.OnEvent("Click", SaveHwMuteHk)
    
    SaveHwMuteHk(*) {
        if (hkCtrl.Value = "") {
            hkGui.Opt("+OwnDialogs")
            MsgBox("Please press a button to register it.", "Error", "Icon!")
            return
        }
        IniWrite(hkCtrl.Value, ConfigFile, "Settings", "HwMuteHotkey")
        Reload() 
    }
    
    hkGui.Show()
}

ConfigurePointerKeysUI(*) {
    Suspend(True) 
    
    pkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Configure Pointer Intercepts")
    pkGui.OnEvent("Close", (*) => Suspend(False)) 
    
    pkGui.Add("Text", "w250", "Select which keys to intercept in Full PPT Mode:")
    
    chkArrows := pkGui.Add("Checkbox", "w250 Checked" CatchArrows, "Arrow Keys (Up, Down, Left, Right)")
    chkPg := pkGui.Add("Checkbox", "w250 Checked" CatchPg, "Page Keys (PgUp, PgDn)")
    chkSpace := pkGui.Add("Checkbox", "w250 Checked" CatchSpace, "Spacebar")
    chkEnter := pkGui.Add("Checkbox", "w250 Checked" CatchEnter, "Enter Key")
    chkTab := pkGui.Add("Checkbox", "w250 Checked" CatchTab, "Tab Key")
    chkEsc := pkGui.Add("Checkbox", "w250 Checked" CatchEsc, "Escape Key")
    
    btn := pkGui.Add("Button", "w250 Default y+15", "Save && Restart")
    btn.OnEvent("Click", SavePointerKeys)
    
    SavePointerKeys(*) {
        IniWrite(chkArrows.Value, ConfigFile, "Pointer", "CatchArrows")
        IniWrite(chkPg.Value, ConfigFile, "Pointer", "CatchPg")
        IniWrite(chkSpace.Value, ConfigFile, "Pointer", "CatchSpace")
        IniWrite(chkEnter.Value, ConfigFile, "Pointer", "CatchEnter")
        IniWrite(chkTab.Value, ConfigFile, "Pointer", "CatchTab")
        IniWrite(chkEsc.Value, ConfigFile, "Pointer", "CatchEsc")
        Reload() 
    }
    
    pkGui.Show()
}

; Removed standalone ChangeMicNameUI (merged into ChangeObsSettingsUI)

; --- CRYPTOGRAPHY ENGINE ---
HashSHA256_Base64(stringToHash) {
    DllCall("LoadLibrary", "Str", "bcrypt.dll")
    DllCall("LoadLibrary", "Str", "crypt32.dll")

    size := StrPut(stringToHash, "UTF-8") - 1
    buf := Buffer(size)
    StrPut(stringToHash, buf, "UTF-8")

    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg:=0, "Str", "SHA256", "Ptr", 0, "UInt", 0)
    DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash:=0, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0)
    DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", size, "UInt", 0)
    
    hashBuf := Buffer(32)
    DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hashBuf, "UInt", 32, "UInt", 0)
    
    DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)

    DllCall("crypt32\CryptBinaryToStringW", "Ptr", hashBuf, "UInt", 32, "UInt", 0x40000001, "Ptr", 0, "UInt*", &b64Len:=0)
    b64Buf := Buffer(b64Len * 2)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", hashBuf, "UInt", 32, "UInt", 0x40000001, "Ptr", b64Buf, "UInt*", &b64Len)

    return StrGet(b64Buf)
}

; --- INITIALIZE OBS CONNECTION ---
ConnectToOBS() {
    global obsWs, obsConnected, EnableWS
    if (!EnableWS)
        return
        
    try {
        obsWs := WebSocket("ws://127.0.0.1:4455", {
            message: HandleObsMessage,
            close: HandleObsClose
        })
    } catch {
        if (EnableWS)
            SetTimer ConnectToOBS, 5000 
    }
}
if (EnableWS)
    SetTimer ConnectToOBS, -100 

HandleObsClose(ws, status, reason) {
    global obsConnected, ConfigFile, EnableWS
    
    if (!EnableWS)
        return
        
    if (!obsConnected) {
        IniWrite("", ConfigFile, "Settings", "ObsPassword")
        MsgBox("PresenterSync detected an incorrect OBS password.`n`nPlease re-enter your OBS WebSocket details.", "Authentication Failed", "Icon!")
        Reload() 
        return
    }
    
    obsConnected := false
    SyncRecState(0)
    SyncStudioState(false)
    SyncSceneState("Scene")
    SetTimer ConnectToOBS, 5000
}

; --- BULLETPROOF REGEX NETWORK LISTENER ---
HandleObsMessage(ws, rawMsg) {
    global obsConnected, targetMicName, obsPassword
    
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    
    if (!RegExMatch(msg, '"op"\s*:\s*(\d+)', &matchOp))
        return
    opCode := Integer(matchOp[1])
    
    if (opCode == 0) {
        authString := ""
        if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &matchSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &matchChallenge)) {
            salt := matchSalt[1]
            challenge := matchChallenge[1]
            
            secret := HashSHA256_Base64(obsPassword . salt)
            authResponse := HashSHA256_Base64(secret . challenge)
            authString := ',"authentication":"' authResponse '"'
        }
        
        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":33554431' authString '}}'
        ws.sendText(identifyJson) 
    }
    else if (opCode == 2) {
        obsConnected := true
        stateJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitState","requestData":{"inputName":"' targetMicName '"}}}'
        ws.sendText(stateJson)
        recJson := '{"op":6,"d":{"requestType":"GetRecordStatus","requestId":"InitRecState"}}'
        ws.sendText(recJson)
        studioJson := '{"op":6,"d":{"requestType":"GetStudioModeEnabled","requestId":"InitStudioState"}}'
        ws.sendText(studioJson)
        sceneJson := '{"op":6,"d":{"requestType":"GetCurrentProgramScene","requestId":"InitSceneState"}}'
        ws.sendText(sceneJson)
    }
    else if (opCode == 5) {
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            if (InStr(msg, '"inputName":"' targetMicName '"') || InStr(msg, '"inputName": "' targetMicName '"')) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    SyncUIState(isMutedOBS)
                    PushObsMuteToZoom(isMutedOBS)
                }
            }
        }
        else if (InStr(msg, '"eventType":"RecordStateChanged"') || InStr(msg, '"eventType": "RecordStateChanged"')) {
            if (RegExMatch(msg, '"outputState"\s*:\s*"([^"]+)"', &matchRecOut)) {
                outState := matchRecOut[1]
                if (outState = "OBS_WEBSOCKET_OUTPUT_STARTED" || outState = "OBS_WEBSOCKET_OUTPUT_RESUMED")
                    SyncRecState(1)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_PAUSED")
                    SyncRecState(2)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_STOPPED")
                    SyncRecState(0)
            }
        }
        else if (InStr(msg, '"eventType":"StudioModeStateChanged"') || InStr(msg, '"eventType": "StudioModeStateChanged"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"eventType":"CurrentProgramSceneChanged"') || InStr(msg, '"eventType": "CurrentProgramSceneChanged"')) {
            if (RegExMatch(msg, '"sceneName"\s*:\s*"([^"]+)"', &matchScene)) {
                SyncSceneState(matchScene[1])
            }
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')) {
            if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                SyncUIState(isMutedOBS)
                PushObsMuteToZoom(isMutedOBS)
            }
        }
        else if (InStr(msg, '"requestId":"InitRecState"') || InStr(msg, '"requestId": "InitRecState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchActive)) {
                active := (matchActive[1] == "true")
                paused := false
                if (RegExMatch(msg, '"outputPaused"\s*:\s*(true|false)', &matchPaused))
                    paused := (matchPaused[1] == "true")
                SyncRecState(active ? (paused ? 2 : 1) : 0)
            }
        }
        else if (InStr(msg, '"requestId":"InitStudioState"') || InStr(msg, '"requestId": "InitStudioState"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                SyncStudioState(matchStudio[1] == "true")
            }
        }
        else if (InStr(msg, '"requestId":"InitSceneState"') || InStr(msg, '"requestId": "InitSceneState"')) {
            if (RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"([^"]+)"', &matchScene) || RegExMatch(msg, '"sceneName"\s*:\s*"([^"]+)"', &matchScene)) {
                SyncSceneState(matchScene[1])
            }
        }
    }
}

ReleaseSyncLock() {
    global IsSyncing
    IsSyncing := false
}

PushObsMuteToZoom(obsIsMuted) {
    global AudioRoutingMode, IsSyncing, ZoomMuteHotkey
    if (AudioRoutingMode != 3 || IsSyncing || ZoomMuteHotkey = "")
        return
    if !WinExist("ahk_exe Zoom.exe")
        return

    zoomState := DetectZoomStates()
    if (!zoomState.hasMic || zoomState.muted == obsIsMuted)
        return

    IsSyncing := true
    SetKeyDelay -1, 30
    try ControlSend FormatSendKey(ZoomMuteHotkey),, "ahk_exe Zoom.exe"
    SetKeyDelay 50, 50
    SetTimer ReleaseSyncLock, -1000
}

DetectZoomStates() {
    result := {foundWindow: false, hasMic: false, muted: false, hasRec: false, recState: 0, hasChat: false, unreadChat: 0}
    hwndList := WinGetList("ahk_exe Zoom.exe")
    if (hwndList.Length == 0)
        return result

    result.foundWindow := true
    for hwnd in hwndList {
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            continue
        names := UIA.GetWindowElementNames(hwnd, false)
        for n in names {
            if (!result.hasMic) {
                if RegExMatch(n, "i)\bunmute\b.*\baudio\b|^unmute$") {
                    result.hasMic := true
                    result.muted := true
                } else if RegExMatch(n, "i)\bmute\b.*\baudio\b|^mute$") {
                    result.hasMic := true
                    result.muted := false
                }
            }
            if (result.recState == 0) {
                if RegExMatch(n, "i)\bresume\b.*\brecording\b") {
                    result.hasRec := true
                    result.recState := 2
                } else if RegExMatch(n, "i)\b(pause|stop)\b.*\brecording\b") {
                    result.hasRec := true
                    result.recState := 1
                } else if (!result.hasRec && RegExMatch(n, "i)^record(\b|,|$)|^record (on this computer|to the cloud)")) {
                    result.hasRec := true
                    result.recState := 0
                }
            }
            if RegExMatch(n, "i)\bchat\b.*?(\d+)\s*unread|(\d+)\s*unread.*\bchat\b", &mChat) {
                result.hasChat := true
                cnt := Integer(mChat[1] != "" ? mChat[1] : mChat[2])
                if (cnt > result.unreadChat)
                    result.unreadChat := cnt
            } else if (!result.hasChat && RegExMatch(n, "i)^chat(\b|,|$)|open chat|show chat|chat panel")) {
                result.hasChat := true
            }
        }
        if (result.hasMic && result.hasRec && result.recState > 0 && result.hasChat && result.unreadChat > 0)
            break
    }
    return result
}

ZoomStateMonitor() {
    global EnableZoom, EnableWS, AudioRoutingMode, zoomConnected, isMuted
    global obsConnected, IsSyncing, ObsMuteHotkey, zoomLastMuted
    global zoomRecGraceUntil, zoomSawRecControl

    if (!EnableZoom && !EnableWS)
        return

    state := DetectZoomStates()
    if (state.hasChat)
        SyncChatState(state.unreadChat)
    else
        SyncChatState(0)

    if (!state.hasMic) {
        zoomConnected := false
        zoomLastMuted := -1
        zoomSawRecControl := false
        if (EnableZoom && !EnableWS)
            SyncRecState(0)
        return
    }

    zoomConnected := (EnableZoom && !EnableWS)
    if (EnableZoom && !EnableWS) {
        SyncUIState(state.muted)
        if (state.hasRec) {
            zoomSawRecControl := true
            if (A_TickCount >= zoomRecGraceUntil)
                SyncRecState(state.recState)
        } else if (zoomSawRecControl && A_TickCount >= zoomRecGraceUntil) {
            zoomSawRecControl := false
            SyncRecState(0)
        }
    } else if (EnableWS && AudioRoutingMode == 3 && obsConnected && !IsSyncing) {
        if (zoomLastMuted != -1 && state.muted != zoomLastMuted && state.muted != isMuted) {
            if (ObsMuteHotkey != "None" && ObsMuteHotkey != "") {
                IsSyncing := true
                SetKeyDelay -1, 30
                try ControlSend FormatSendKey(ObsMuteHotkey),, "ahk_exe obs64.exe"
                SetKeyDelay 50, 50
                SetTimer ReleaseSyncLock, -1000
            }
        }
    }
    zoomLastMuted := state.muted
}

UpdateZoomMonitorTimer() {
    global EnableZoom, EnableWS
    if (EnableZoom || EnableWS)
        SetTimer ZoomStateMonitor, 500
    else
        SetTimer ZoomStateMonitor, 0
}
UpdateZoomMonitorTimer()

SyncChatState(newCount) {
    global unreadChatCount
    if (unreadChatCount != newCount) {
        unreadChatCount := newCount
        ApplyChatAppearance()
    }
}

ApplyChatAppearance() {
    global unreadChatCount, ChatGui, ChatIconText, ChatLabelText, ShowText, MonoIcon
    global chatColorClear, chatBorderClear, chatIconClear
    global chatColorAlert, chatBorderAlert, chatIconAlert

    if (!IsSet(ChatGui))
        return

    hasUnread := (unreadChatCount > 0)
    bg := hasUnread ? chatColorAlert : chatColorClear
    brd := hasUnread ? chatBorderAlert : chatBorderClear
    ic := MonoIcon ? (hasUnread ? chatIconAlert : chatIconClear) : (hasUnread ? "White" : "D1D5DB")

    ChatGui.BackColor := bg
    ChatIconText.Opt("c" ic)
    ChatLabelText.Opt("c" ic)
    if (ShowText) {
        ChatIconText.Visible := true
        ChatLabelText.Visible := true
        ChatLabelText.Value := hasUnread ? (unreadChatCount " NEW") : "CHAT"
    } else {
        ChatIconText.Visible := !hasUnread
        ChatLabelText.Visible := hasUnread
        ChatLabelText.Value := String(unreadChatCount)
    }
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ChatGui.Hwnd, "Int", 34, "Int*", brd, "Int", 4)
}

SyncStudioState(isEnabled) {
    global studioModeActive
    if (studioModeActive != isEnabled) {
        studioModeActive := isEnabled
        ApplyStudioAppearance()
    }
}

ApplyStudioAppearance() {
    global studioModeActive, StudioGui, StudioIconText, StudioLabelText, ShowText, MonoIcon
    global studioColorOff, studioBorderOff, studioIconOff
    global studioColorOn, studioBorderOn, studioIconOn

    if (!IsSet(StudioGui))
        return

    bg := studioModeActive ? studioColorOn : studioColorOff
    brd := studioModeActive ? studioBorderOn : studioBorderOff
    ic := MonoIcon ? (studioModeActive ? studioIconOn : studioIconOff) : (studioModeActive ? "White" : "D1D5DB")

    StudioGui.BackColor := bg
    StudioIconText.Opt("c" ic)
    if (ShowText && IsObject(StudioLabelText))
        StudioLabelText.Opt("c" ic)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", StudioGui.Hwnd, "Int", 34, "Int*", brd, "Int", 4)
}

SyncSceneState(sceneName) {
    global currentSceneName, SceneGui, SceneLabelText
    if (sceneName != "" && currentSceneName != sceneName) {
        currentSceneName := sceneName
        if (IsSet(SceneGui) && IsSet(SceneLabelText))
            SceneLabelText.Value := currentSceneName
    }
}

SyncRecState(newState) {
    global recState
    if (recState != newState) {
        recState := newState
        ApplyRecAppearance()
    }
}

ApplyRecAppearance() {
    global recState, RecGui, RecIconText, RecLabelText, ShowText, MonoIcon
    global recColorOff, recBorderOff, recIconOff
    global recColorActive, recBorderActive, recIconActive
    global recColorPaused, recBorderPaused, recIconPaused

    if (!IsSet(RecGui))
        return

    if (recState == 1) {
        bg := recColorActive, brd := recBorderActive, ic := MonoIcon ? recIconActive : "White"
        glyph := Chr(0xE7C8), lbl := "REC"
    } else if (recState == 2) {
        bg := recColorPaused, brd := recBorderPaused, ic := MonoIcon ? recIconPaused : "White"
        glyph := Chr(0xE769), lbl := "PAUSED"
    } else {
        bg := recColorOff, brd := recBorderOff, ic := MonoIcon ? recIconOff : "D1D5DB"
        glyph := Chr(0xE71A), lbl := "NOT REC"
    }

    RecGui.BackColor := bg
    RecIconText.Opt("c" ic)
    RecIconText.Value := glyph
    if (ShowText && IsObject(RecLabelText)) {
        RecLabelText.Opt("c" ic)
        RecLabelText.Value := lbl
    }
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", RecGui.Hwnd, "Int", 34, "Int*", brd, "Int", 4)
}

SyncUIState(obsIsMuted) {
    global isMuted, ConfigFile
    if (isMuted != obsIsMuted) {
        isMuted := obsIsMuted
        IniWrite(isMuted ? 1 : 0, ConfigFile, "Settings", "IsMuted")
        PlayMuteAnimation()
    }
}

; --- CUSTOM TRAY MENU ---
A_TrayMenu.Delete() 

; MODULE CONTROLS
A_TrayMenu.Add("Enable Full Pointer Controls (PPT + Mute)", TogglePPT)
if (EnablePPT)
    A_TrayMenu.Check("Enable Full Pointer Controls (PPT + Mute)")

A_TrayMenu.Add("Enable Pointer Mute Only", ToggleMicOnly)
if (EnableMicOnly)
    A_TrayMenu.Check("Enable Pointer Mute Only")

A_TrayMenu.Add()

A_TrayMenu.Add("Enable OBS WebSocket Sync", ToggleWS)
if (EnableWS)
    A_TrayMenu.Check("Enable OBS WebSocket Sync")

A_TrayMenu.Add("Enable Zoom Monitoring", ToggleZoom)
if (EnableZoom)
    A_TrayMenu.Check("Enable Zoom Monitoring")

; MAIN UI TOGGLE
A_TrayMenu.Add("Show Mute Indicator", ToggleIndicator)
if (ShowIndicator)
    A_TrayMenu.Check("Show Mute Indicator")

; APPEARANCE SUBMENU
AppearanceMenu := Menu()
AppearanceMenu.Add("Show Text Label", ToggleText)
if (ShowText)
    AppearanceMenu.Check("Show Text Label")

AppearanceMenu.Add("Use Monochromatic Icon", ToggleMono)
if (MonoIcon)
    AppearanceMenu.Check("Use Monochromatic Icon")

AppearanceMenu.Add("Use Sleek Corners", ToggleCorners)
if (SleekCorners)
    AppearanceMenu.Check("Use Sleek Corners")

AppearanceMenu.Add("Aggressive Mute Pulse", TogglePulse)
if (AggressivePulse)
    AppearanceMenu.Check("Aggressive Mute Pulse")

OpacityMenu := Menu()
OpacityMenu.Add("Solid (100%)", SetSolid)
OpacityMenu.Add("Frosted (85%)", SetFrosted)
OpacityMenu.Add("Ghost (50%)", SetGhost)
if (OpacityLevel == 255)
    OpacityMenu.Check("Solid (100%)")
else if (OpacityLevel == 220)
    OpacityMenu.Check("Frosted (85%)")
else if (OpacityLevel == 127)
    OpacityMenu.Check("Ghost (50%)")
    
AppearanceMenu.Add("Transparency Level", OpacityMenu)

ScaleMenu := Menu()
ScaleOptions := [
    {label: "Tiny (x0.25)", val: 0.25},
    {label: "Small (x0.5)", val: 0.5},
    {label: "Normal (x1.0)", val: 1.0},
    {label: "Large (x1.5)", val: 1.5},
    {label: "Huge (x2.0)", val: 2.0},
    {label: "Massive (x2.5)", val: 2.5},
    {label: "Colossal (x3.0)", val: 3.0},
    {label: "Gigantic (x5.0)", val: 5.0}
]
for opt in ScaleOptions {
    ScaleMenu.Add(opt.label, ((v, *) => SetScale(v)).Bind(opt.val))
    if (Abs(IndicatorScale - opt.val) < 0.001)
        ScaleMenu.Check(opt.label)
}

AppearanceMenu.Add("Indicator Scale", ScaleMenu)

SetScale(val) {
    IniWrite(val, ConfigFile, "Settings", "IndicatorScale")
    Reload()
}

AppearanceMenu.Add() 
AppearanceMenu.Add("Restore Default Appearance", ResetAppearance)

A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)

A_TrayMenu.Add() 

; SETTINGS SUBMENU
SettingsMenu := Menu()
RoutingMenu := Menu()
RoutingModes := [
    {label: "1: Pro OBS Setup (VB-Cable)", mode: 1},
    {label: "2: Standard Direct Mic (Zoom-Only)", mode: 2},
    {label: "3: Dual App Sync (OBS + Zoom)", mode: 3}
]
for rm in RoutingModes {
    RoutingMenu.Add(rm.label, ((m, *) => SetRoutingMode(m)).Bind(rm.mode))
    if (AudioRoutingMode == rm.mode)
        RoutingMenu.Check(rm.label)
}
SettingsMenu.Add("Audio Routing Mode", RoutingMenu)
SettingsMenu.Add("Launch Clicker Tester", ShowPointerTester)
SettingsMenu.Add("Change App Shortcuts", ChangeAppHotkeysUI)
SettingsMenu.Add("Configure Pointer Intercepts", ConfigurePointerKeysUI)
SettingsMenu.Add("Change Pointer Mute Button", ChangeHwMuteHotkeyUI)
SettingsMenu.Add("Change OBS Settings", ChangeObsSettingsUI)
SettingsMenu.Add("Change Zoom Shortcuts", ChangeZoomShortcutsUI)
SettingsMenu.Add("Reset Indicator Position", ResetTrayPosition)

A_TrayMenu.Add("Settings", SettingsMenu)
A_TrayMenu.Add("Help && Shortcuts", ShowHelpWindow) 
A_TrayMenu.Add("About PresenterSync", ShowAboutWindow)

A_TrayMenu.Add("Suspend All Hotkeys", ToggleSuspend)
A_TrayMenu.Add() 
A_TrayMenu.Add("Exit PresenterSync", ExitTrayApp)

ToggleSuspend(*) {
    Suspend(-1) ; Toggles suspension state
    if A_IsSuspended {
        A_TrayMenu.Check("Suspend All Hotkeys")
        TrayTip("PresenterSync", "All hotkeys suspended.", 1)
    } else {
        A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip("PresenterSync", "Hotkeys active.", 1)
    }
}

TogglePPT(*) {
    global EnablePPT, EnableMicOnly, ConfigFile
    ToolTip()

    EnablePPT := !EnablePPT

    if (EnablePPT) {
        EnableMicOnly := false
        WriteIniBool("Settings", "EnableMicOnly", false)
        SetTrayCheck("Enable Pointer Mute Only", false)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    } else {
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        ToolTip "Pointer Mode: OFF"
    }

    WriteIniBool("Settings", "EnablePPT", EnablePPT)
    SetTimer RemoveToolTip, -2000
}

ToggleMicOnly(*) {
    global EnablePPT, EnableMicOnly, ConfigFile
    ToolTip()

    EnableMicOnly := !EnableMicOnly

    if (EnableMicOnly) {
        EnablePPT := false
        WriteIniBool("Settings", "EnablePPT", false)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        SetTrayCheck("Enable Pointer Mute Only", true)
        ToolTip "Pointer Mode: Mute Only"
    } else {
        SetTrayCheck("Enable Pointer Mute Only", false)
        ToolTip "Pointer Mode: OFF"
    }

    WriteIniBool("Settings", "EnableMicOnly", EnableMicOnly)
    SetTimer RemoveToolTip, -2000
}

CyclePointerMode(*) {
    global EnablePPT, EnableMicOnly, ConfigFile
    ToolTip()

    if (EnablePPT) {
        ; State 1 -> 2: Full PPT is ON, switch to Mic Only
        EnablePPT := false
        EnableMicOnly := true
        WriteIniBool("Settings", "EnablePPT", false)
        WriteIniBool("Settings", "EnableMicOnly", true)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        SetTrayCheck("Enable Pointer Mute Only", true)
        ToolTip "Pointer Mode: Mute Only"
    } else if (EnableMicOnly) {
        ; State 2 -> 3: Mic Only is ON, switch to OFF
        EnableMicOnly := false
        WriteIniBool("Settings", "EnableMicOnly", false)
        SetTrayCheck("Enable Pointer Mute Only", false)
        ToolTip "Pointer Mode: OFF"
    } else {
        ; State 3 -> 1: Both are OFF, switch to Full PPT
        EnablePPT := true
        WriteIniBool("Settings", "EnablePPT", true)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    }

    SetTimer RemoveToolTip, -2000
}

ToggleWS(*) {
    global EnableWS, EnableZoom, obsWs, obsConnected, obsPassword, zoomConnected, zoomLastMuted
    global zoomRecGraceUntil, zoomSawRecControl, ConfigFile
    ToolTip()

    EnableWS := !EnableWS

    if (EnableWS) {
        if (obsPassword = "") {
            obsPassword := PromptForPassword()
            if (obsPassword = "") {
                EnableWS := false
                return
            }
            IniWrite(obsPassword, ConfigFile, "Settings", "ObsPassword")
        }

        if (EnableZoom) {
            EnableZoom := false
            zoomConnected := false
            zoomLastMuted := -1
            zoomRecGraceUntil := 0
            zoomSawRecControl := false
            WriteIniBool("Settings", "EnableZoom", false)
            SetTrayCheck("Enable Zoom Monitoring", false)
        }

        WriteIniBool("Settings", "EnableWS", true)
        SetTrayCheck("Enable OBS WebSocket Sync", true)
        ToolTip "WebSocket Sync: ON"
        SetTimer ConnectToOBS, -100
    } else {
        WriteIniBool("Settings", "EnableWS", false)
        SetTrayCheck("Enable OBS WebSocket Sync", false)
        ToolTip "WebSocket Sync: OFF"
        SetTimer ConnectToOBS, 0
        obsConnected := false
        zoomConnected := false
        zoomLastMuted := -1
        zoomRecGraceUntil := 0
        zoomSawRecControl := false
        if (obsWs) {
            obsWs.shutdown()
            obsWs := ""
        }
        SyncRecState(0)
        SyncChatState(0)
        SyncStudioState(false)
        SyncSceneState("Scene")
    }

    UpdateZoomMonitorTimer()
    UpdateHudVisibility()
    SetTimer RemoveToolTip, -2000
}

ToggleZoom(*) {
    global EnableZoom, EnableWS, obsWs, obsConnected, zoomConnected, zoomLastMuted
    global zoomRecGraceUntil, zoomSawRecControl
    ToolTip()

    EnableZoom := !EnableZoom

    if (EnableZoom) {
        if (EnableWS) {
            EnableWS := false
            WriteIniBool("Settings", "EnableWS", false)
            SetTrayCheck("Enable OBS WebSocket Sync", false)
            SetTimer ConnectToOBS, 0
            obsConnected := false
            if (obsWs) {
                obsWs.shutdown()
                obsWs := ""
            }
            SyncRecState(0)
            SyncStudioState(false)
            SyncSceneState("Scene")
        }

        zoomRecGraceUntil := 0
        zoomSawRecControl := false
        WriteIniBool("Settings", "EnableZoom", true)
        SetTrayCheck("Enable Zoom Monitoring", true)
        ToolTip "Zoom Monitoring: ON"
    } else {
        WriteIniBool("Settings", "EnableZoom", false)
        SetTrayCheck("Enable Zoom Monitoring", false)
        zoomConnected := false
        zoomLastMuted := -1
        zoomRecGraceUntil := 0
        zoomSawRecControl := false
        SyncRecState(0)
        SyncChatState(0)
        ToolTip "Zoom Monitoring: OFF"
    }

    UpdateZoomMonitorTimer()
    UpdateHudVisibility()
    SetTimer RemoveToolTip, -2000
}

ToggleIndicator(*) {
    global ShowIndicator, isMuted, AggressivePulse, ConfigFile
    ShowIndicator := !ShowIndicator
    IniWrite(ShowIndicator ? 1 : 0, ConfigFile, "Settings", "ShowIndicator")

    SetTrayCheck("Show Mute Indicator", ShowIndicator)
    UpdateHudVisibility()
    if (ShowIndicator && isMuted)
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
    else if (!ShowIndicator)
        SetTimer BreathingAnimation, 0
}
ToggleText(*) {
    IniWrite(ShowText ? 0 : 1, ConfigFile, "Settings", "ShowText")
    Reload()
}
ToggleMono(*) {
    IniWrite(MonoIcon ? 0 : 1, ConfigFile, "Settings", "MonoIcon")
    Reload()
}
ToggleCorners(*) {
    IniWrite(SleekCorners ? 0 : 1, ConfigFile, "Settings", "SleekCorners")
    Reload()
}
TogglePulse(*) {
    global AggressivePulse, isMuted, breathDir
    AggressivePulse := !AggressivePulse
    IniWrite(AggressivePulse ? 1 : 0, ConfigFile, "Settings", "AggressivePulse")
    SetTrayCheck("Aggressive Mute Pulse", AggressivePulse)

    if (isMuted) {
        breathDir := AggressivePulse ? -20 : -5
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
    }
}
SetSolid(*) {
    IniWrite(255, ConfigFile, "Settings", "OpacityLevel")
    Reload()
}
SetFrosted(*) {
    IniWrite(220, ConfigFile, "Settings", "OpacityLevel")
    Reload()
}
SetGhost(*) {
    IniWrite(127, ConfigFile, "Settings", "OpacityLevel")
    Reload()
}
ResetAppearance(*) {
    ; Resets all cosmetic settings to their factory defaults
    IniWrite(0, ConfigFile, "Settings", "ShowText")
    IniWrite(0, ConfigFile, "Settings", "MonoIcon")
    IniWrite(0, ConfigFile, "Settings", "SleekCorners")
    IniWrite(0, ConfigFile, "Settings", "AggressivePulse")
    IniWrite(220, ConfigFile, "Settings", "OpacityLevel")
    IniWrite(1.0, ConfigFile, "Settings", "IndicatorScale")
    Reload() ; Instantly applies changes
}
ResetSettings(*) {
    FileDelete(ConfigFile)
    Reload() 
}
ResetTrayPosition(*) {
    IniWrite("Default", ConfigFile, "Position", "X")
    IniWrite("Default", ConfigFile, "Position", "Y")
    Reload() 
}
ExitTrayApp(*) {
    ExitApp()
}

; --- LOCATION MEMORY & SCALE GEOMETRY ---
savedX := IniRead(ConfigFile, "Position", "X", "Default")
savedY := IniRead(ConfigFile, "Position", "Y", "Default")

global baseWidth := Round((ShowText ? 140 : 80) * IndicatorScale)
global baseHeight := Round(40 * IndicatorScale)
global hudGap := Max(2, Round(6 * IndicatorScale))
global recHeight := Round(34 * IndicatorScale)
global recW := Round((baseWidth - hudGap) * 0.54)
global chatW := baseWidth - hudGap - recW
global row3Height := Round(30 * IndicatorScale)
global studioW := Round((baseWidth - hudGap) * 0.38)
global sceneW := baseWidth - hudGap - studioW
global iconSize := Max(1, Round(18 * IndicatorScale))
global textSize := Max(1, Round(13 * IndicatorScale))
global subIconSize := Max(1, Round(12 * IndicatorScale))
global subTextSize := Max(1, Round(9 * IndicatorScale))
global miniTextSize := Max(1, Round(9 * IndicatorScale))

if (savedX = "Default" || savedY = "Default" || !IsInteger(savedX) || !IsInteger(savedY)) {
    MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
    stackTopPad := 10 + recHeight + row3Height + (2 * hudGap)
    savedX := Max(Left + 10, Right - baseWidth - 20)
    savedY := Max(Top + stackTopPad, Bottom - baseHeight - 20)
} else {
    savedX := Integer(savedX)
    savedY := Integer(savedY)
    vLeft := SysGet(76), vTop := SysGet(77)
    vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
    stackTopPad := recHeight + row3Height + (2 * hudGap)
    savedX := Max(vLeft, Min(savedX, vRight - baseWidth))
    savedY := Max(vTop + stackTopPad, Min(savedY, vBottom - baseHeight))
}

posX := "x" savedX
posY := "y" savedY

StyleHudWindow(guiObj, borderColor) {
    global SleekCorners, currentAlpha
    cornerStyle := SleekCorners ? 3 : 2
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "Int", 33, "Int*", cornerStyle, "Int", 4)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "Int", 34, "Int*", borderColor, "Int", 4)
    margins := Buffer(16, 0)
    NumPut("Int", 1, margins, 0), NumPut("Int", 1, margins, 4)
    NumPut("Int", 1, margins, 8), NumPut("Int", 1, margins, 12)
    DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", guiObj.Hwnd, "Ptr", margins)
    WinSetTransparent(currentAlpha, guiObj.Hwnd)
}

; --- GUI SETUP ---
MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
MicGui.BackColor := isMuted ? colorMuted : colorLive
MicGui.MarginX := 0
MicGui.MarginY := 0

osBuild := Integer(StrSplit(A_OSVersion, ".")[3])
global IconFont := (osBuild >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

activeIconColor := MonoIcon ? (isMuted ? iconMuted : iconLive) : "White"
initialIcon := isMuted ? Chr(0xF781) : Chr(0xE720)
initialText := isMuted ? "MUTED" : "LIVE"

if (ShowText) {
    iconW := Round(30 * IndicatorScale)
    iconX := Round(15 * IndicatorScale)
    textW := Round(80 * IndicatorScale)
    textX := Round(50 * IndicatorScale)

    global IconText := MicGui.Add("Text", "x" iconX " y0 w" iconW " h" baseHeight " Center +0x200 BackgroundTrans c" activeIconColor, initialIcon)
    IconText.SetFont("s" iconSize, IconFont) 
    global LabelText := MicGui.Add("Text", "x" textX " y0 w" textW " h" baseHeight " Left +0x200 BackgroundTrans c" activeIconColor, initialText)
    LabelText.SetFont("s" textSize " w700", "Segoe UI")
} else {
    global IconText := MicGui.Add("Text", "x0 y0 w" baseWidth " h" baseHeight " Center +0x200 BackgroundTrans c" activeIconColor, initialIcon)
    IconText.SetFont("s" iconSize, IconFont) 
    global LabelText := ""
}

StyleHudWindow(MicGui, isMuted ? borderMuted : borderLive)

; --- ROW 2: RECORDING & ZOOM CHAT GUIS ---
RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
RecGui.BackColor := recColorOff
RecGui.MarginX := 0
RecGui.MarginY := 0

if (ShowText) {
    rIconW := Round(18 * IndicatorScale)
    rIconX := Round(6 * IndicatorScale)
    rTextX := rIconX + rIconW + Round(2 * IndicatorScale)
    rTextW := Max(8, recW - rTextX - Round(2 * IndicatorScale))

    global RecIconText := RecGui.Add("Text", "x" rIconX " y0 w" rIconW " h" recHeight " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE71A))
    RecIconText.SetFont("s" subIconSize, IconFont)
    global RecLabelText := RecGui.Add("Text", "x" rTextX " y0 w" rTextW " h" recHeight " Left +0x200 BackgroundTrans cD1D5DB", "NOT REC")
    RecLabelText.SetFont("s" subTextSize " w700", "Segoe UI")
} else {
    global RecIconText := RecGui.Add("Text", "x0 y0 w" recW " h" recHeight " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE71A))
    RecIconText.SetFont("s" subIconSize, IconFont)
    global RecLabelText := ""
}

StyleHudWindow(RecGui, recBorderOff)
ApplyRecAppearance()

ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
ChatGui.BackColor := chatColorClear
ChatGui.MarginX := 0
ChatGui.MarginY := 0

if (ShowText) {
    cIconW := Round(16 * IndicatorScale)
    cIconX := Round(5 * IndicatorScale)
    cTextX := cIconX + cIconW + Round(2 * IndicatorScale)
    cTextW := Max(8, chatW - cTextX - Round(2 * IndicatorScale))

    global ChatIconText := ChatGui.Add("Text", "x" cIconX " y0 w" cIconW " h" recHeight " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE8BD))
    ChatIconText.SetFont("s" subIconSize, IconFont)
    global ChatLabelText := ChatGui.Add("Text", "x" cTextX " y0 w" cTextW " h" recHeight " Left +0x200 BackgroundTrans cD1D5DB", "CHAT")
    ChatLabelText.SetFont("s" subTextSize " w700", "Segoe UI")
} else {
    global ChatIconText := ChatGui.Add("Text", "x0 y0 w" chatW " h" recHeight " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE8BD))
    ChatIconText.SetFont("s" subIconSize, IconFont)
    global ChatLabelText := ChatGui.Add("Text", "x0 y0 w" chatW " h" recHeight " Center +0x200 BackgroundTrans cFFFFFF Hidden", "0")
    ChatLabelText.SetFont("s" subTextSize " w700", "Segoe UI")
}

StyleHudWindow(ChatGui, chatBorderClear)
ApplyChatAppearance()

; --- ROW 3: STUDIO MODE & ACTIVE SCENE GUIS ---
StudioGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
StudioGui.BackColor := studioColorOff
StudioGui.MarginX := 0
StudioGui.MarginY := 0

if (ShowText) {
    stIconW := Round(16 * IndicatorScale)
    stIconX := Round(4 * IndicatorScale)
    stTextX := stIconX + stIconW
    stTextW := Max(8, studioW - stTextX - Round(2 * IndicatorScale))
    global StudioIconText := StudioGui.Add("Text", "x" stIconX " y0 w" stIconW " h" row3Height " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE7F4))
    StudioIconText.SetFont("s" Max(1, Round(11 * IndicatorScale)), IconFont)
    global StudioLabelText := StudioGui.Add("Text", "x" stTextX " y0 w" stTextW " h" row3Height " Left +0x200 BackgroundTrans cD1D5DB", "STUDIO")
    StudioLabelText.SetFont("s" Max(1, Round(8 * IndicatorScale)) " w700", "Segoe UI")
} else {
    global StudioIconText := StudioGui.Add("Text", "x0 y0 w" studioW " h" row3Height " Center +0x200 BackgroundTrans cD1D5DB", Chr(0xE7F4))
    StudioIconText.SetFont("s" Max(1, Round(12 * IndicatorScale)), IconFont)
    global StudioLabelText := ""
}
StyleHudWindow(StudioGui, studioBorderOff)
ApplyStudioAppearance()

SceneGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
SceneGui.BackColor := sceneColor
SceneGui.MarginX := 0
SceneGui.MarginY := 0

scPad := Round(4 * IndicatorScale)
global SceneLabelText := SceneGui.Add("Text", "x" scPad " y0 w" Max(8, sceneW - 2 * scPad) " h" row3Height " Center +0x200 +0x80 BackgroundTrans cFFFFFF", currentSceneName)
SceneLabelText.SetFont("s" miniTextSize " w600", "Segoe UI")
StyleHudWindow(SceneGui, sceneBorder)

ComputeHudLayout(anchorX, anchorY) {
    global baseWidth, baseHeight, recHeight, recW, chatW, row3Height, studioW, sceneW, hudGap
    recY := anchorY - recHeight - hudGap
    row3Y := recY - row3Height - hudGap
    return {
        micX: anchorX,
        micY: anchorY,
        micW: baseWidth,
        micH: baseHeight,
        recX: anchorX,
        recY: recY,
        recW: recW,
        recH: recHeight,
        chatX: anchorX + recW + hudGap,
        chatY: recY,
        chatW: chatW,
        chatH: recHeight,
        studioX: anchorX,
        studioY: row3Y,
        studioW: studioW,
        studioH: row3Height,
        sceneX: anchorX + studioW + hudGap,
        sceneY: row3Y,
        sceneW: sceneW,
        sceneH: row3Height
    }
}

UpdateHudLayout(anchorX := "", anchorY := "", skipHwnd := 0) {
    global MicGui, RecGui, ChatGui, StudioGui, SceneGui, savedX, savedY
    if (anchorX = "" || anchorY = "") {
        if (IsSet(MicGui) && DllCall("IsWindowVisible", "Ptr", MicGui.Hwnd))
            try WinGetPos(&anchorX, &anchorY,,, MicGui.Hwnd)
        if (anchorX = "" || anchorY = "")
            anchorX := savedX, anchorY := savedY
    }
    savedX := anchorX, savedY := anchorY
    pos := ComputeHudLayout(anchorX, anchorY)
    if (IsSet(MicGui) && MicGui.Hwnd != skipHwnd)
        MicGui.Move(pos.micX, pos.micY, pos.micW, pos.micH)
    if (IsSet(RecGui) && RecGui.Hwnd != skipHwnd)
        RecGui.Move(pos.recX, pos.recY, pos.recW, pos.recH)
    if (IsSet(ChatGui) && ChatGui.Hwnd != skipHwnd)
        ChatGui.Move(pos.chatX, pos.chatY, pos.chatW, pos.chatH)
    if (IsSet(StudioGui) && StudioGui.Hwnd != skipHwnd)
        StudioGui.Move(pos.studioX, pos.studioY, pos.studioW, pos.studioH)
    if (IsSet(SceneGui) && SceneGui.Hwnd != skipHwnd)
        SceneGui.Move(pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH)
}

UpdateHudVisibility() {
    global ShowIndicator, EnableWS, EnableZoom, MicGui, RecGui, ChatGui, StudioGui, SceneGui, savedX, savedY, baseAlpha

    if (!ShowIndicator) {
        if IsSet(MicGui)
            MicGui.Hide()
        if IsSet(RecGui)
            RecGui.Hide()
        if IsSet(ChatGui)
            ChatGui.Hide()
        if IsSet(StudioGui)
            StudioGui.Hide()
        if IsSet(SceneGui)
            SceneGui.Hide()
        return
    }

    curX := savedX, curY := savedY
    if (IsSet(MicGui) && DllCall("IsWindowVisible", "Ptr", MicGui.Hwnd))
        try WinGetPos(&curX, &curY,,, MicGui.Hwnd)
    pos := ComputeHudLayout(curX, curY)

    MicGui.Show("NoActivate x" pos.micX " y" pos.micY " w" pos.micW " h" pos.micH)
    WinSetTransparent(baseAlpha, MicGui.Hwnd)
    if (EnableWS || EnableZoom) {
        RecGui.Show("NoActivate x" pos.recX " y" pos.recY " w" pos.recW " h" pos.recH)
        WinSetTransparent(baseAlpha, RecGui.Hwnd)
        ChatGui.Show("NoActivate x" pos.chatX " y" pos.chatY " w" pos.chatW " h" pos.chatH)
        WinSetTransparent(baseAlpha, ChatGui.Hwnd)
    } else {
        RecGui.Hide()
        ChatGui.Hide()
    }

    if (EnableWS) {
        StudioGui.Show("NoActivate x" pos.studioX " y" pos.studioY " w" pos.studioW " h" pos.studioH)
        WinSetTransparent(baseAlpha, StudioGui.Hwnd)
        SceneGui.Show("NoActivate x" pos.sceneX " y" pos.sceneY " w" pos.sceneW " h" pos.sceneH)
        WinSetTransparent(baseAlpha, SceneGui.Hwnd)
    } else {
        StudioGui.Hide()
        SceneGui.Hide()
    }
}

if (ShowIndicator) {
    pos := ComputeHudLayout(savedX, savedY)
    MicGui.Show("NoActivate x" pos.micX " y" pos.micY " w" pos.micW " h" pos.micH)
    UpdateHudVisibility()
    if (isMuted)
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
} else {
    UpdateHudVisibility()
}

; --- SYSTEM HOTKEYS ---
try Hotkey(PptHotkey, (*) => CyclePointerMode())
try Hotkey(WsHotkey, (*) => ToggleWS())
try Hotkey(ZoomHotkey, (*) => ToggleZoom())
try Hotkey(IndHotkey, (*) => ToggleIndicator())
try Hotkey(SuspendHotkey, (*) => ToggleSuspend())
try Hotkey(ExitHotkey, (*) => ExitTrayApp())

RemoveToolTip() {
    ToolTip
}

; --- POWERPOINT CONTROLS (OMNI-CATCH) ---

#HotIf EnablePPT && CatchArrows
$Down::SendToPPT("{Down}")
$Up::SendToPPT("{Up}")
$Left::SendToPPT("{Left}")
$Right::SendToPPT("{Right}")

#HotIf EnablePPT && CatchPg
$PgDn::SendToPPT("{PgDn}")
$PgUp::SendToPPT("{PgUp}")

#HotIf EnablePPT && CatchSpace
$Space::SendToPPT("{Space}")

#HotIf EnablePPT && CatchEnter
$Enter::SendToPPT("{Enter}")

#HotIf EnablePPT && CatchTab
$Tab::SendToPPT("{Tab}")

#HotIf EnablePPT && CatchEsc
$Esc::SendToPPT("{Esc}")

#HotIf EnablePPT
$+F5::SendToPPT("{Blind}{F5}") ; Always intercepted if PPT mode is active

#HotIf ; Reset directive

SendToPPT(Key) {
    global EnablePPT
    static LastSignal := 0 
    
    ; Failsafe: Abort if PPT mode is disabled
    if (!EnablePPT) {
        return
    }
    
    ; Shield against dirty hardware clicker signals (150ms cooldown)
    if (A_TickCount - LastSignal < 150) { 
        return 
    }
    LastSignal := A_TickCount
    
    ; 1. Target the normal fullscreen Slide Show FIRST
    if WinExist("ahk_class screenClass ahk_exe POWERPNT.EXE") {
        ; Attempt native COM navigation first to avoid synthetic ControlSend key-hold fast-forwarding
        comHandled := false
        if (Key = "{Down}" || Key = "{Right}" || Key = "{PgDn}" || Key = "{Space}") {
            try {
                ComObjActive("PowerPoint.Application").SlideShowWindows(1).View.Next()
                comHandled := true
            }
        } else if (Key = "{Up}" || Key = "{Left}" || Key = "{PgUp}") {
            try {
                ComObjActive("PowerPoint.Application").SlideShowWindows(1).View.Previous()
                comHandled := true
            }
        }
        if (!comHandled) {
            try ControlSend Key,, "ahk_class screenClass ahk_exe POWERPNT.EXE"
        }
    }
    ; 2. Fallback to Presenter View if fullscreen isn't found
    else if WinExist("PowerPoint Presenter View ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "PowerPoint Presenter View ahk_exe POWERPNT.EXE"
    }
    ; 3. Target the main PowerPoint Edit window explicitly (avoids hidden NUIDialog helper windows)
    else if WinExist("ahk_class PPTFrameClass ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_class PPTFrameClass ahk_exe POWERPNT.EXE"
    }
    ; 4. Target the generic background process as final fallback
    else if WinExist("ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_exe POWERPNT.EXE"
    }
    ; 5. If PowerPoint is completely closed, play distinct error tone
    else {
        SoundPlay "*16"
    }
}

; --- DYNAMIC HARDWARE MUTE TRIGGER ---
CheckPointerEnable(ThisHotkey) {
    global EnablePPT, EnableMicOnly
    return (EnablePPT || EnableMicOnly)
}

HotIf CheckPointerEnable
if (HwMuteHotkey != "") {
    try Hotkey(HwMuteHotkey, (*) => TriggerMute(), "On")
}
HotIf

; --- MUTE CONTROL ---
FormatSendKey(hk) {
    return RegExReplace(hk, "([a-zA-Z0-9_]+)$", "{$1}")
}

FormatPassthroughHook(hk) {
    return "~$" RegExReplace(hk, "^[~*$]+")
}

if ((AudioRoutingMode == 1 || AudioRoutingMode == 3) && ObsMuteHotkey != "None" && ObsMuteHotkey != "")
    try Hotkey(FormatPassthroughHook(ObsMuteHotkey), LaptopKeyboardMute)
if ((AudioRoutingMode == 2 || AudioRoutingMode == 3) && ZoomMuteHotkey != "")
    try Hotkey(FormatPassthroughHook(ZoomMuteHotkey), LaptopKeyboardMute)
obsRecHook := (ObsRecHotkey != "") ? FormatPassthroughHook(ObsRecHotkey) : ""
zoomRecHook := (ZoomRecHotkey != "") ? FormatPassthroughHook(ZoomRecHotkey) : ""
if (obsRecHook != "" && obsRecHook = zoomRecHook) {
    try Hotkey(obsRecHook, LaptopCombinedRecToggle)
} else {
    if (obsRecHook != "")
        try Hotkey(obsRecHook, LaptopObsRecToggle)
    if (zoomRecHook != "")
        try Hotkey(zoomRecHook, LaptopZoomRecToggle)
}

obsPauseHook := (ObsPauseHotkey != "") ? FormatPassthroughHook(ObsPauseHotkey) : ""
zoomPauseHook := (ZoomPauseHotkey != "") ? FormatPassthroughHook(ZoomPauseHotkey) : ""
if (obsPauseHook != "" && obsPauseHook = zoomPauseHook) {
    try Hotkey(obsPauseHook, LaptopCombinedPauseToggle)
} else {
    if (obsPauseHook != "")
        try Hotkey(obsPauseHook, LaptopObsPauseToggle)
    if (zoomPauseHook != "")
        try Hotkey(zoomPauseHook, LaptopZoomPauseToggle)
}

LaptopCombinedRecToggle(ThisHotkey) {
    LaptopObsRecToggle(ThisHotkey)
    LaptopZoomRecToggle(ThisHotkey)
}

LaptopCombinedPauseToggle(ThisHotkey) {
    LaptopObsPauseToggle(ThisHotkey)
    LaptopZoomPauseToggle(ThisHotkey)
}

LaptopObsRecToggle(ThisHotkey) {
    global obsConnected, EnableWS, recState
    if (!obsConnected && EnableWS)
        SyncRecState(recState == 0 ? 1 : 0)
}

LaptopObsPauseToggle(ThisHotkey) {
    global obsConnected, EnableWS, recState
    if (!obsConnected && EnableWS && recState != 0)
        SyncRecState(recState == 1 ? 2 : 1)
}

LaptopZoomRecToggle(ThisHotkey) {
    global EnableZoom, EnableWS, recState, zoomRecGraceUntil
    if (EnableZoom && !EnableWS) {
        zoomRecGraceUntil := A_TickCount + 1500
        SyncRecState(recState == 0 ? 1 : 0)
    }
}

LaptopZoomPauseToggle(ThisHotkey) {
    global EnableZoom, EnableWS, recState, zoomRecGraceUntil
    if (EnableZoom && !EnableWS && recState != 0) {
        zoomRecGraceUntil := A_TickCount + 1500
        SyncRecState(recState == 1 ? 2 : 1)
    }
}

LaptopKeyboardMute(ThisHotkey) {
    global obsConnected, zoomConnected, isMuted

    ; Target app natively receives this physical keystroke. Do NOT send it a second time.
    ; Only update the UI manually if active telemetry listeners are off.
    if (!obsConnected && !zoomConnected) {
        SyncUIState(!isMuted)
    }
}

TriggerMute() {
    global obsConnected, zoomConnected, isMuted, ObsMuteHotkey, ZoomMuteHotkey, AudioRoutingMode, EnablePPT, EnableMicOnly

    ; Failsafe: Abort if hardware triggers are turned off
    if !(EnablePPT || EnableMicOnly) {
        return
    }

    obsOpen := WinExist("ahk_exe obs64.exe")
    zoomOpen := WinExist("ahk_exe Zoom.exe")

    if (AudioRoutingMode == 1) {
        if !obsOpen {
            SoundPlay "*16"
            return
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(ObsMuteHotkey),, "ahk_exe obs64.exe"
        SetKeyDelay 50, 50
    } else if (AudioRoutingMode == 2) {
        if !zoomOpen {
            SoundPlay "*16"
            return
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(ZoomMuteHotkey),, "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
    } else if (AudioRoutingMode == 3) {
        if (!obsOpen && !zoomOpen) {
            SoundPlay "*16"
            return
        }
        SetKeyDelay -1, 30
        if (obsOpen && ObsMuteHotkey != "None" && ObsMuteHotkey != "")
            try ControlSend FormatSendKey(ObsMuteHotkey),, "ahk_exe obs64.exe"
        if (zoomOpen && ZoomMuteHotkey != "")
            try ControlSend FormatSendKey(ZoomMuteHotkey),, "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
    }

    if (!obsConnected && !zoomConnected) {
        SyncUIState(!isMuted)
    }
}

PlayMuteAnimation() {
    global isMuted, colorLive, colorMuted, borderLive, borderMuted
    global iconLive, iconMuted, ShowText, MonoIcon, baseWidth, baseHeight, ShowIndicator
    global currentAlpha, baseAlpha, IconText, LabelText, MicGui, AggressivePulse, breathDir, IndicatorScale
    global savedX, savedY
    
    if (!ShowIndicator) {
        SetTimer BreathingAnimation, 0
        currentAlpha := baseAlpha
        MicGui.BackColor := isMuted ? colorMuted : colorLive
        activeFontColor := MonoIcon ? (isMuted ? iconMuted : iconLive) : "White"
        IconText.Opt("c" activeFontColor)
        IconText.Value := isMuted ? Chr(0xF781) : Chr(0xE720)
        
        if (ShowText) {
            LabelText.Opt("c" activeFontColor)
            LabelText.Value := isMuted ? "MUTED" : "LIVE"
        }
            
        newBorder := isMuted ? borderMuted : borderLive
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MicGui.Hwnd, "Int", 34, "Int*", newBorder, "Int", 4)
        return 
    }

    SetTimer BreathingAnimation, 0
    baseX := savedX
    baseY := savedY
    
    fadeStep := Round(baseAlpha / 10)
    iconW := Round(30 * IndicatorScale)
    iconX := Round(15 * IndicatorScale)
    textW := Round(80 * IndicatorScale)
    textX := Round(50 * IndicatorScale)
    
    Loop 10 {
        currentAlpha -= fadeStep
        if (currentAlpha < 0)
            currentAlpha := 0
        
        widthIncrement := (ShowText ? 1.5 : 1) * IndicatorScale
        heightIncrement := 0.5 * IndicatorScale
        popWidth := Round(baseWidth + (A_Index * widthIncrement))
        popHeight := Round(baseHeight + (A_Index * heightIncrement))
        offsetX := Round((popWidth - baseWidth) / 2) 
        offsetY := Round((popHeight - baseHeight) / 2)
        
        MicGui.Move(baseX - offsetX, baseY - offsetY, popWidth, popHeight)
        
        if (ShowText) {
            IconText.Move(offsetX + iconX, offsetY, iconW, baseHeight) 
            LabelText.Move(offsetX + textX, offsetY, textW, baseHeight)
        } else {
            IconText.Move(offsetX, offsetY, baseWidth, baseHeight) 
        }
        
        WinSetTransparent(currentAlpha, MicGui.Hwnd)
        Sleep 10
    }
    
    MicGui.BackColor := isMuted ? colorMuted : colorLive
    
    activeFontColor := MonoIcon ? (isMuted ? iconMuted : iconLive) : "White"
    IconText.Opt("c" activeFontColor)
    IconText.Value := isMuted ? Chr(0xF781) : Chr(0xE720)
    
    if (ShowText) {
        LabelText.Opt("c" activeFontColor)
        LabelText.Value := isMuted ? "MUTED" : "LIVE"
    }
        
    newBorder := isMuted ? borderMuted : borderLive
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MicGui.Hwnd, "Int", 34, "Int*", newBorder, "Int", 4)
    
    Loop 10 {
        currentAlpha += fadeStep
        if (currentAlpha > baseAlpha)
            currentAlpha := baseAlpha
        
        widthIncrement := (ShowText ? 1.5 : 1) * IndicatorScale
        heightIncrement := 0.5 * IndicatorScale
        popWidth := Round((baseWidth + (10 * widthIncrement)) - (A_Index * widthIncrement))
        popHeight := Round((baseHeight + (10 * heightIncrement)) - (A_Index * heightIncrement))
        offsetX := Round((popWidth - baseWidth) / 2)
        offsetY := Round((popHeight - baseHeight) / 2)
        
        MicGui.Move(baseX - offsetX, baseY - offsetY, popWidth, popHeight)
        
        if (ShowText) {
            IconText.Move(offsetX + iconX, offsetY, iconW, baseHeight)
            LabelText.Move(offsetX + textX, offsetY, textW, baseHeight)
        } else {
            IconText.Move(offsetX, offsetY, baseWidth, baseHeight)
        }
        
        WinSetTransparent(currentAlpha, MicGui.Hwnd)
        Sleep 10
    }
    
    currentAlpha := baseAlpha
    MicGui.Move(baseX, baseY, baseWidth, baseHeight)
    
    if (ShowText) {
        IconText.Move(iconX, 0, iconW, baseHeight) 
        LabelText.Move(textX, 0, textW, baseHeight)
    } else {
        IconText.Move(0, 0, baseWidth, baseHeight)
    }
    
    WinSetTransparent(currentAlpha, MicGui.Hwnd)
    
    if (isMuted) {
        breathDir := AggressivePulse ? -20 : -5
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
    }
}

BreathingAnimation() {
    global currentAlpha, breathDir, baseAlpha, MicGui, AggressivePulse
    
    lowerBound := Round(baseAlpha * (AggressivePulse ? 0.2 : 0.6))
    stepAmount := AggressivePulse ? 20 : 5
    
    currentAlpha += breathDir
    if (currentAlpha <= lowerBound) {
        currentAlpha := lowerBound
        breathDir := stepAmount
    } else if (currentAlpha >= baseAlpha) {
        currentAlpha := baseAlpha
        breathDir := -stepAmount
    }
    WinSetTransparent(currentAlpha, MicGui.Hwnd)
}

global isDraggingHud := false
global activeDragHwnd := 0

AnchorFromHwnd(hwnd, X, Y) {
    global RecGui, ChatGui, StudioGui, SceneGui
    global recHeight, recW, row3Height, studioW, hudGap
    if (IsSet(RecGui) && hwnd == RecGui.Hwnd) {
        Y := Y + recHeight + hudGap
    } else if (IsSet(ChatGui) && hwnd == ChatGui.Hwnd) {
        X := X - recW - hudGap
        Y := Y + recHeight + hudGap
    } else if (IsSet(StudioGui) && hwnd == StudioGui.Hwnd) {
        Y := Y + row3Height + hudGap + recHeight + hudGap
    } else if (IsSet(SceneGui) && hwnd == SceneGui.Hwnd) {
        X := X - studioW - hudGap
        Y := Y + row3Height + hudGap + recHeight + hudGap
    }
    return {x: X, y: Y}
}

DragSyncTick() {
    global isDraggingHud, activeDragHwnd
    if (!isDraggingHud || !activeDragHwnd)
        return
    try {
        WinGetPos(&curX, &curY,,, "ahk_id " activeDragHwnd)
        anchor := AnchorFromHwnd(activeDragHwnd, curX, curY)
        UpdateHudLayout(anchor.x, anchor.y, activeDragHwnd)
    }
}

OnMessage(0x0003, WM_HUD_MOVE)
WM_HUD_MOVE(wParam, lParam, msg, hwnd) {
    global isDraggingHud, activeDragHwnd
    if (isDraggingHud && hwnd == activeDragHwnd)
        DragSyncTick()
}

OnMessage(0x0201, WM_LBUTTONDOWN)
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global ConfigFile, MicGui, RecGui, ChatGui, StudioGui, SceneGui
    global isDraggingHud, activeDragHwnd

    isHudHwnd := (hwnd == MicGui.Hwnd)
        || (IsSet(RecGui) && hwnd == RecGui.Hwnd)
        || (IsSet(ChatGui) && hwnd == ChatGui.Hwnd)
        || (IsSet(StudioGui) && hwnd == StudioGui.Hwnd)
        || (IsSet(SceneGui) && hwnd == SceneGui.Hwnd)
    if (!isHudHwnd)
        return

    activeDragHwnd := hwnd
    isDraggingHud := true
    SetTimer DragSyncTick, 16
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton"
    isDraggingHud := false
    activeDragHwnd := 0
    SetTimer DragSyncTick, 0

    WinGetPos(&X, &Y,,, "ahk_id " hwnd)
    anchor := AnchorFromHwnd(hwnd, X, Y)

    IniWrite(anchor.x, ConfigFile, "Position", "X")
    IniWrite(anchor.y, ConfigFile, "Position", "Y")
    UpdateHudLayout(anchor.x, anchor.y)
}

OnMessage(0x02E0, WM_DPICHANGED)
WM_DPICHANGED(wParam, lParam, msg, hwnd) {
    global MicGui
    if (hwnd != MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    newRight := NumGet(lParam, 8, "Int")
    newBottom := NumGet(lParam, 12, "Int")
    MicGui.Move(newLeft, newTop, newRight - newLeft, newBottom - newTop)
    UpdateHudLayout(newLeft, newTop)
}

; --- POINTER TESTER ---
ShowPointerTester(*) {
    testerGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Pointer Tester")
    
    testerGui.SetFont("s10", "Segoe UI")
    testerGui.Add("Text", "w250 Center", "Press any button on your clicker.")
    
    keyDisplay := testerGui.Add("Text", "w250 Center y+15", "Listening...")
    keyDisplay.SetFont("s14 w700 c0055CC") ; Blue bold text
    
    btn := testerGui.Add("Button", "w100 x75 y+20 Default", "Close")
    
    ; Create an InputHook to capture raw keystrokes
    ih := InputHook("L0 V") 
    ih.KeyOpt("{All}", "N") ; Notify on all keys
    
    ih.OnKeyDown := (ih, VK, SC) => UpdateKeyDisplay(VK, SC)
    
    UpdateKeyDisplay(VK, SC) {
        ; Convert the virtual key and scan code into a readable name
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC))
        if WinExist(testerGui.Hwnd)
            keyDisplay.Value := keyName
    }
    
    Cleanup(*) {
        ih.Stop()
        testerGui.Destroy()
    }
    
    testerGui.OnEvent("Close", Cleanup)
    btn.OnEvent("Click", Cleanup)
    
    testerGui.Show("AutoSize")
    ih.Start()
}
