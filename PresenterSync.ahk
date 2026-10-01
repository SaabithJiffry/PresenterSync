; ==============================================================================
; Script: PresenterSync
; Description: OBS WebSocket and PowerPoint synchronization tool with system tray UI
; Version: 1.1.0
; Author: Saabith Jiffry
; License: MIT 
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"
SetKeyDelay 50, 50 

#Include <WebSocket>

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

global ObsMuteHotkey := IniRead(ConfigFile, "Settings", "ObsHotkey", "None")
global obsPassword := IniRead(ConfigFile, "Settings", "ObsPassword", "")
global targetMicName := IniRead(ConfigFile, "Settings", "TargetMicName", "Mic/Aux")

global EnablePPT := ReadIniBool("Settings", "EnablePPT")
global EnableMicOnly := ReadIniBool("Settings", "EnableMicOnly")
global EnableWS := ReadIniBool("Settings", "EnableWS")

global ShowIndicator := ReadIniBool("Settings", "ShowIndicator", true)
global ShowText := ReadIniBool("Settings", "ShowText")
global MonoIcon := ReadIniBool("Settings", "MonoIcon")
global SleekCorners := ReadIniBool("Settings", "SleekCorners")
global AggressivePulse := ReadIniBool("Settings", "AggressivePulse")
global OpacityLevel := IniRead(ConfigFile, "Settings", "OpacityLevel", 220)
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
global IndHotkey := IniRead(ConfigFile, "Settings", "IndHotkey", "^+F12")
global ExitHotkey := IniRead(ConfigFile, "Settings", "ExitHotkey", "!+F12")
global SuspendHotkey := IniRead(ConfigFile, "Settings", "SuspendHotkey", "^!+F12")
global HwMuteHotkey := IniRead(ConfigFile, "Settings", "HwMuteHotkey", "b") ; Pointer Mute Button

; 1. First-run: Only ask for the Hotkey
if (ObsMuteHotkey = "None") {
    ObsMuteHotkey := PromptForHotkey()
    IniWrite(ObsMuteHotkey, ConfigFile, "Settings", "ObsHotkey")
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

global isMuted := IniRead(ConfigFile, "Settings", "IsMuted", 0)
global baseAlpha := OpacityLevel     
global currentAlpha := baseAlpha
global breathDir := AggressivePulse ? -20 : -5      

global colorLive := "22C55E" 
global colorMuted := "EF4444" 
global borderLive := 0x5EC522  
global borderMuted := 0x4444EF 
global iconLive := "064E3B"   
global iconMuted := "540808"  

; --- SETUP GUIS ---
PromptForHotkey() {
    Suspend(True) 
    
    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Setup")
    hkGui.OnEvent("Close", (*) => ExitApp()) 
    
    hkGui.Add("Text", "w250", "Press your OBS Mute shortcut:")
    hkCtrl := hkGui.Add("Hotkey", "w250")
    btn := hkGui.Add("Button", "w250 Default y+15", "Save && Start")
    
    savedHk := ""
    btn.OnEvent("Click", SaveHk)
    
    SaveHk(*) {
        if (hkCtrl.Value = "") {
            hkGui.Opt("+OwnDialogs") ; Forces the MsgBox to appear on top
            MsgBox("Please enter a shortcut.", "Setup", "Icon!")
            return
        }
        savedHk := hkCtrl.Value
        Suspend(False) 
        hkGui.Destroy()
    }
    
    hkGui.Show()
    WinWaitClose(hkGui.Hwnd)
    return savedHk
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
    
    ; Create a tabbed interface (400px wide, 240px tall)
    tabs := helpGui.Add("Tab3", "w420 h260", ["Shortcuts", "Pointer Modes", "OBS Sync", "Pro Tips"])
    
    ; --- TAB 1: SHORTCUTS ---
    tabs.UseTab(1)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Global Keyboard Shortcuts")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+15", FormatHK(PptHotkey) " :  Cycle Pointer Modes")
    helpGui.Add("Text", "x25 y+10", FormatHK(WsHotkey) " :  Toggle OBS WebSocket Sync")
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

    ; --- TAB 3: OBS SYNC ---
    tabs.UseTab(3)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "OBS WebSocket Sync")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "PresenterSync uses OBS WebSocket v5 to talk directly to OBS Studio behind the scenes.`n`n• True 2-Way Sync: If you mute the mic inside OBS with your mouse, the PresenterSync overlay updates instantly to match.`n• Reliability: Clicker commands are sent instantly over the local network to prevent input drops.`n`nMake sure WebSocket is enabled in OBS (Tools > WebSocket Server Settings).")

    ; --- TAB 4: PRO TIPS ---
    tabs.UseTab(4)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Customizing the Overlay")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "• Repositioning HUD: Hold down your Left Mouse Button on the indicator to drag it anywhere on your screen. Its exact coordinates are saved automatically for your next session.`n`n• Appearance: Right-click the system tray icon and explore 'Indicator Appearance' to add text labels, change opacity levels, or enable the aggressive pulse animation for high visibility.")

    tabs.UseTab() ; End tab definitions
    
    ; Add the close button centered (x160) and explicitly placed below the Tab control (y280)
    btn := helpGui.Add("Button", "w100 x160 y280 Default", "Got it!")
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
    aboutGui.Add("Text", "x10 w330 Center y+5", "Version 1.1.0")
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
    
    hkGui.Add("Text", "xm w150", "Toggle Indicator:")
    indCtrl := hkGui.Add("Hotkey", "x+10 w120", IndHotkey)

    hkGui.Add("Text", "xm w150", "Suspend Hotkeys:")
    suspCtrl := hkGui.Add("Hotkey", "x+10 w120", SuspendHotkey)
    
    hkGui.Add("Text", "xm w150", "Exit PresenterSync:")
    exitCtrl := hkGui.Add("Hotkey", "x+10 w120", ExitHotkey)
    
    btn := hkGui.Add("Button", "xm w280 Default y+15", "Save && Restart")
    btn.OnEvent("Click", SaveAppHk)
    
    SaveAppHk(*) {
        ; Check if any of the 4 inputs were cleared
        if (pptCtrl.Value = "" || wsCtrl.Value = "" || indCtrl.Value = "" || exitCtrl.Value = "") {
            hkGui.Opt("+OwnDialogs") ; Forces the MsgBox to appear on top
            MsgBox("Shortcuts cannot be left blank.", "Error", "Icon!")
            return
        }
        IniWrite(pptCtrl.Value, ConfigFile, "Settings", "PptHotkey")
        IniWrite(wsCtrl.Value, ConfigFile, "Settings", "WsHotkey")
        IniWrite(indCtrl.Value, ConfigFile, "Settings", "IndHotkey")
        IniWrite(suspCtrl.Value, ConfigFile, "Settings", "SuspendHotkey")
        IniWrite(exitCtrl.Value, ConfigFile, "Settings", "ExitHotkey")
        Reload() 
    }
    
    hkGui.Show()
}

ChangeMuteHotkeyUI(*) {
    Suspend(True) 
    
    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit System Mute Shortcut")
    hkGui.OnEvent("Close", (*) => Suspend(False)) 
    
    hkGui.Add("Text", "w250", "Press your new OBS Mute shortcut:")
    hkCtrl := hkGui.Add("Hotkey", "w250", ObsMuteHotkey)
    btn := hkGui.Add("Button", "w250 Default y+15", "Save && Restart")
    
    btn.OnEvent("Click", SaveMuteHk)
    
    SaveMuteHk(*) {
        if (hkCtrl.Value = "") {
            hkGui.Opt("+OwnDialogs") ; Forces the MsgBox to appear on top
            MsgBox("Please enter a shortcut.", "Error", "Icon!")
            return
        }
        IniWrite(hkCtrl.Value, ConfigFile, "Settings", "ObsHotkey")
        Reload() 
    }
    
    hkGui.Show()
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

ChangeMicNameUI(*) {
    Suspend(True) 
    
    micGuiPrompt := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit OBS Audio Source")
    micGuiPrompt.OnEvent("Close", (*) => Suspend(False)) 
    
    micGuiPrompt.Add("Text", "w280", "Enter exact OBS Audio Source Name (e.g., Mic/Aux):")
    micCtrl := micGuiPrompt.Add("Edit", "w280", targetMicName)
    btn := micGuiPrompt.Add("Button", "w280 Default y+15", "Save && Restart")
    
    btn.OnEvent("Click", SaveMicName)
    
    SaveMicName(*) {
        if (micCtrl.Value = "") {
            micGuiPrompt.Opt("+OwnDialogs")
            MsgBox("Audio source name cannot be empty.", "Error", "Icon!")
            return
        }
        IniWrite(micCtrl.Value, ConfigFile, "Settings", "TargetMicName")
        Reload() 
    }
    
    micGuiPrompt.Show()
}

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
    }
    else if (opCode == 5) {
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            if (InStr(msg, '"inputName":"' targetMicName '"') || InStr(msg, '"inputName": "' targetMicName '"')) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    SyncUIState(isMutedOBS)
                }
            }
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')) {
            if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                SyncUIState(isMutedOBS)
            }
        }
    }
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
ScaleMenu.Add("Tiny (x0.25)", (*) => SetScale(0.25))
ScaleMenu.Add("Small (x0.5)", (*) => SetScale(0.5))
ScaleMenu.Add("Normal (x1.0)", (*) => SetScale(1.0))
ScaleMenu.Add("Large (x1.5)", (*) => SetScale(1.5))
ScaleMenu.Add("Huge (x2.0)", (*) => SetScale(2.0))
ScaleMenu.Add("Massive (x2.5)", (*) => SetScale(2.5))

if (IndicatorScale == 0.25)
    ScaleMenu.Check("Tiny (x0.25)")
else if (IndicatorScale == 0.5)
    ScaleMenu.Check("Small (x0.5)")
else if (IndicatorScale == 1.0)
    ScaleMenu.Check("Normal (x1.0)")
else if (IndicatorScale == 1.5)
    ScaleMenu.Check("Large (x1.5)")
else if (IndicatorScale == 2.0)
    ScaleMenu.Check("Huge (x2.0)")
else if (IndicatorScale == 2.5)
    ScaleMenu.Check("Massive (x2.5)")
    
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
SettingsMenu.Add("Launch Clicker Tester", ShowPointerTester)
SettingsMenu.Add("Change App Shortcuts", ChangeAppHotkeysUI)
SettingsMenu.Add("Configure Pointer Intercepts", ConfigurePointerKeysUI)
SettingsMenu.Add("Change Pointer Mute Button", ChangeHwMuteHotkeyUI)
SettingsMenu.Add("Change System Mute Shortcut", ChangeMuteHotkeyUI) 
SettingsMenu.Add("Change OBS Audio Source Name", ChangeMicNameUI)
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
    global EnableWS, obsWs, obsConnected, obsPassword, ConfigFile
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
        if (obsWs) {
            obsWs.shutdown()
            obsWs := ""
        }
    }

    SetTimer RemoveToolTip, -2000
}

ToggleIndicator(*) {
    global ShowIndicator, isMuted, AggressivePulse, baseWidth, baseHeight, posX, posY, MicGui
    ShowIndicator := !ShowIndicator
    IniWrite(ShowIndicator ? 1 : 0, ConfigFile, "Settings", "ShowIndicator")

    if (ShowIndicator) {
        SetTrayCheck("Show Mute Indicator", true)
        MicGui.Show("NoActivate w" baseWidth " h" baseHeight " " posX " " posY)
        if (isMuted)
            SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
    } else {
        SetTrayCheck("Show Mute Indicator", false)
        MicGui.Hide()
        SetTimer BreathingAnimation, 0
    }
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
global iconSize := Max(1, Round(18 * IndicatorScale))
global textSize := Max(1, Round(13 * IndicatorScale))

if (savedX = "Default" || savedY = "Default") {
    MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
    savedX := Right - baseWidth - 20 
    savedY := Bottom - baseHeight - 20 
}

posX := "x" savedX
posY := "y" savedY

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
}

cornerStyle := SleekCorners ? 3 : 2
initialBorder := isMuted ? borderMuted : borderLive
DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MicGui.Hwnd, "Int", 33, "Int*", cornerStyle, "Int", 4)
DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MicGui.Hwnd, "Int", 34, "Int*", initialBorder, "Int", 4)
margins := Buffer(16, 0)
NumPut("Int", 1, margins, 0), NumPut("Int", 1, margins, 4)
NumPut("Int", 1, margins, 8), NumPut("Int", 1, margins, 12)
DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", MicGui.Hwnd, "Ptr", margins)

if (ShowIndicator) {
    MicGui.Show("NoActivate w" baseWidth " h" baseHeight " " posX " " posY) 
    if (isMuted)
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
} else {
    MicGui.Hide()
}
WinSetTransparent(currentAlpha, MicGui.Hwnd)

; --- SYSTEM HOTKEYS ---
try Hotkey(PptHotkey, (*) => CyclePointerMode())
try Hotkey(WsHotkey, (*) => ToggleWS())
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
    
    ; Failsafe: Abort if PPT mode is disabled
    if (!EnablePPT) {
        return
    }
    
    ; 1. If Presenter View is open
    if WinExist("PowerPoint Presenter View ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "PowerPoint Presenter View ahk_exe POWERPNT.EXE"
    }
    ; 2. Target the normal fullscreen Slide Show
    else if WinExist("ahk_class screenClass ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_class screenClass ahk_exe POWERPNT.EXE"
    }
    ; 3. Target the generic background process
    else if WinExist("ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_exe POWERPNT.EXE"
    }
    ; 4. If PowerPoint is completely closed, play distinct error tone
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
Hotkey("~" ObsMuteHotkey, LaptopKeyboardMute)

LaptopKeyboardMute(ThisHotkey) {
    global obsConnected, isMuted
    
    ; OBS natively receives this physical keystroke. Do NOT send it a second time.
    ; Only update the UI manually if the WebSocket is turned off.
    if (!obsConnected) {
        SyncUIState(!isMuted)
    }
}

TriggerMute() {
    global obsConnected, isMuted, ObsMuteHotkey, EnablePPT, EnableMicOnly
    
    ; Failsafe: Abort if hardware triggers are turned off
    if !(EnablePPT || EnableMicOnly) {
        return
    }
    
    ; If OBS isn't running, play a distinct error tone and abort
    if !WinExist("ahk_exe obs64.exe") {
        SoundPlay "*16"
        return
    }
    
    formattedKey := RegExReplace(ObsMuteHotkey, "([a-zA-Z0-9]+)$", "{$1}")
    
    SetKeyDelay -1, 30
    try ControlSend formattedKey,, "ahk_exe obs64.exe"
    SetKeyDelay 50, 50 
    
    if (!obsConnected) {
        SyncUIState(!isMuted)
    }
}

PlayMuteAnimation() {
    global isMuted, colorLive, colorMuted, borderLive, borderMuted
    global iconLive, iconMuted, ShowText, MonoIcon, baseWidth, baseHeight, ShowIndicator
    global currentAlpha, baseAlpha, IconText, MicGui, AggressivePulse, breathDir, IndicatorScale
    
    if (ShowText) {
        global LabelText
    }
    
    if (!ShowIndicator) {
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
    WinGetPos(&baseX, &baseY,,, MicGui.Hwnd)
    
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

OnMessage(0x0201, WM_LBUTTONDOWN)
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global ConfigFile, MicGui
    if (hwnd != MicGui.Hwnd)
        return
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton" 
    WinGetPos(&X, &Y,,, MicGui.Hwnd)
    IniWrite(X, ConfigFile, "Position", "X")
    IniWrite(Y, ConfigFile, "Position", "Y")
}

OnMessage(0x02E0, WM_DPICHANGED)
WM_DPICHANGED(wParam, lParam, msg, hwnd) {
    global MicGui, baseWidth
    if (hwnd != MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    newRight := NumGet(lParam, 8, "Int")
    newBottom := NumGet(lParam, 12, "Int")
    MicGui.Move(newLeft, newTop, newRight - newLeft, newBottom - newTop)
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
