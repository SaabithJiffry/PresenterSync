; PresenterSync.ahk - Updated with dynamic shortcuts
#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"
SetKeyDelay 50, 50 

#Include <WebSocket>

; === CONFIGURATION & MEMORY ===
global ConfigFile := A_ScriptDir "\MicOverlay_Config.ini"
global ObsMuteHotkey := IniRead(ConfigFile, "Settings", "ObsHotkey", "None")
global obsPassword := IniRead(ConfigFile, "Settings", "ObsPassword", "")

global EnablePPT := IniRead(ConfigFile, "Settings", "EnablePPT", 0)
global EnableWS := IniRead(ConfigFile, "Settings", "EnableWS", 0)

global ShowIndicator := IniRead(ConfigFile, "Settings", "ShowIndicator", 1)
global ShowText := IniRead(ConfigFile, "Settings", "ShowText", 0)
global MonoIcon := IniRead(ConfigFile, "Settings", "MonoIcon", 0)
global SleekCorners := IniRead(ConfigFile, "Settings", "SleekCorners", 0)
global AggressivePulse := IniRead(ConfigFile, "Settings", "AggressivePulse", 0)
global OpacityLevel := IniRead(ConfigFile, "Settings", "OpacityLevel", 220)
global FirstRun := IniRead(ConfigFile, "Settings", "FirstRun", 1)

; --- NEW DYNAMIC HOTKEYS ---
global PptHotkey := IniRead(ConfigFile, "Settings", "PptHotkey", "^F12")
global WsHotkey := IniRead(ConfigFile, "Settings", "WsHotkey", "!F12")
global IndHotkey := IniRead(ConfigFile, "Settings", "IndHotkey", "^+F12")
global ExitHotkey := IniRead(ConfigFile, "Settings", "ExitHotkey", "!+F12")

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
global targetMicName := "Mic/Aux" 

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
    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Help")
    
    helpGui.SetFont("s12 w700", "Segoe UI")
    helpGui.Add("Text", "w300 Center", "PresenterSync Shortcuts")
    
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "w300 y+15", FormatHK(PptHotkey) " :  Toggle PowerPoint Controls")
    helpGui.Add("Text", "w300 y+10", FormatHK(WsHotkey) " :  Toggle OBS WebSocket Sync")
    helpGui.Add("Text", "w300 y+10", FormatHK(IndHotkey) " :  Hide/Unhide Indicator")
    helpGui.Add("Text", "w300 y+10", FormatHK(ExitHotkey) " :  Exit PresenterSync")
    
    helpGui.SetFont("s9 italic cGray")
    helpGui.Add("Text", "w300 y+20 Center", "You can view these at any time by right-clicking the system tray icon.")
    
    btn := helpGui.Add("Button", "w100 x100 y+15 Default", "Got it!")
    btn.OnEvent("Click", (*) => helpGui.Destroy())
    
    helpGui.Show("AutoSize")
}

ChangeAppHotkeysUI(*) {
    Suspend(True) 

    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit App Shortcuts")
    hkGui.OnEvent("Close", (*) => Suspend(False)) 
    
    hkGui.Add("Text", "w150", "Toggle PowerPoint:")
    pptCtrl := hkGui.Add("Hotkey", "x+10 w120", PptHotkey)
    
    hkGui.Add("Text", "xm w150", "Toggle OBS WebSocket:")
    wsCtrl := hkGui.Add("Hotkey", "x+10 w120", WsHotkey)
    
    hkGui.Add("Text", "xm w150", "Toggle Indicator:")
    indCtrl := hkGui.Add("Hotkey", "x+10 w120", IndHotkey)
    
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
        IniWrite(exitCtrl.Value, ConfigFile, "Settings", "ExitHotkey")
        Reload() 
    }
    
    hkGui.Show()
}

ChangeMuteHotkeyUI(*) {
    Suspend(True) 
    
    hkGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit Mute Shortcut")
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
A_TrayMenu.Add("Enable PowerPoint Controls", TogglePPT)
if (EnablePPT)
    A_TrayMenu.Check("Enable PowerPoint Controls")

A_TrayMenu.Add("Enable OBS WebSocket Sync", ToggleWS)
if (EnableWS)
    A_TrayMenu.Check("Enable OBS WebSocket Sync")

A_TrayMenu.Add() 

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
A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)

A_TrayMenu.Add() 

; SETTINGS SUBMENU
SettingsMenu := Menu()
SettingsMenu.Add("Change App Shortcuts", ChangeAppHotkeysUI)
SettingsMenu.Add("Change Mute Hotkey", ChangeMuteHotkeyUI) ; Now uses the dedicated, safe UI
SettingsMenu.Add("Reset Indicator Position", ResetTrayPosition)

A_TrayMenu.Add("Settings", SettingsMenu)
A_TrayMenu.Add("Help && Shortcuts", ShowHelpWindow) ; Fixed the missing ampersand

A_TrayMenu.Add() 
A_TrayMenu.Add("Exit PresenterSync", ExitTrayApp)

TogglePPT(*) {
    global EnablePPT := !EnablePPT
    IniWrite(EnablePPT ? 1 : 0, ConfigFile, "Settings", "EnablePPT")
    
    if (EnablePPT) {
        A_TrayMenu.Check("Enable PowerPoint Controls")
        ToolTip "PowerPoint Controls: ON"
    } else {
        A_TrayMenu.Uncheck("Enable PowerPoint Controls")
        ToolTip "PowerPoint Controls: OFF"
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
                EnableWS := 0 
                return
            }
            IniWrite(obsPassword, ConfigFile, "Settings", "ObsPassword")
        }
        
        IniWrite(1, ConfigFile, "Settings", "EnableWS")
        A_TrayMenu.Check("Enable OBS WebSocket Sync")
        ToolTip "WebSocket Sync: ON"
        SetTimer ConnectToOBS, -100
    } else {
        IniWrite(0, ConfigFile, "Settings", "EnableWS")
        A_TrayMenu.Uncheck("Enable OBS WebSocket Sync")
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
    global ShowIndicator := !ShowIndicator
    global isMuted, AggressivePulse, baseWidth, posX, posY, MicGui
    IniWrite(ShowIndicator ? 1 : 0, ConfigFile, "Settings", "ShowIndicator")
    if (ShowIndicator) {
        A_TrayMenu.Check("Show Mute Indicator")
        MicGui.Show("NoActivate w" baseWidth " h40 " posX " " posY)
        if (isMuted)
            SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
    } else {
        A_TrayMenu.Uncheck("Show Mute Indicator")
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
    global AggressivePulse := !AggressivePulse
    IniWrite(AggressivePulse ? 1 : 0, ConfigFile, "Settings", "AggressivePulse")
    if (AggressivePulse)
        A_TrayMenu.Check("Aggressive Mute Pulse")
    else
        A_TrayMenu.Uncheck("Aggressive Mute Pulse")
    global isMuted, breathDir
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

; --- LOCATION MEMORY ---
savedX := IniRead(ConfigFile, "Position", "X", "Default")
savedY := IniRead(ConfigFile, "Position", "Y", "Default")
global baseWidth := ShowText ? 140 : 80

if (savedX = "Default" || savedY = "Default") {
    MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
    savedX := Right - baseWidth - 20 
    savedY := Bottom - 40 - 20 
}

posX := "x" savedX
posY := "y" savedY

; --- GUI SETUP ---
MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
MicGui.BackColor := isMuted ? colorMuted : colorLive
MicGui.MarginX := 0
MicGui.MarginY := 0

activeIconColor := MonoIcon ? (isMuted ? iconMuted : iconLive) : "White"
initialIcon := isMuted ? Chr(0xF781) : Chr(0xE720)
initialText := isMuted ? "MUTED" : "LIVE"

if (ShowText) {
    global IconText := MicGui.Add("Text", "x15 y0 w30 h40 Center +0x200 BackgroundTrans c" activeIconColor, initialIcon)
    IconText.SetFont("s18", "Segoe Fluent Icons") 
    global LabelText := MicGui.Add("Text", "x50 y0 w80 h40 Left +0x200 BackgroundTrans c" activeIconColor, initialText)
    LabelText.SetFont("s13 w700", "Segoe UI")
} else {
    global IconText := MicGui.Add("Text", "x0 y0 w80 h40 Center +0x200 BackgroundTrans c" activeIconColor, initialIcon)
    IconText.SetFont("s18", "Segoe Fluent Icons") 
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
    MicGui.Show("NoActivate w" baseWidth " h40 " posX " " posY) 
    if (isMuted)
        SetTimer BreathingAnimation, (AggressivePulse ? 15 : 40)
} else {
    MicGui.Hide()
}
WinSetTransparent(currentAlpha, MicGui.Hwnd) 

; --- SYSTEM HOTKEYS ---
try Hotkey(PptHotkey, (*) => TogglePPT())
try Hotkey(WsHotkey, (*) => ToggleWS())
try Hotkey(IndHotkey, (*) => ToggleIndicator())
try Hotkey(ExitHotkey, (*) => ExitTrayApp())

RemoveToolTip() {
    ToolTip
}

; --- POWERPOINT CONTROLS ---
#HotIf EnablePPT
$Down::ControlSend "{Down}",, "ahk_exe POWERPNT.EXE"
$Up::ControlSend "{Up}",, "ahk_exe POWERPNT.EXE"
$Tab::ControlSend "{Tab}",, "ahk_exe POWERPNT.EXE"
$Esc::ControlSend "{Esc}",, "ahk_exe POWERPNT.EXE"
$+F5::ControlSend "{Blind}{F5}",, "ahk_exe POWERPNT.EXE"
#HotIf

; --- MUTE CONTROL ---
$b::TriggerMute()

Hotkey("~" ObsMuteHotkey, LaptopKeyboardMute)
LaptopKeyboardMute(ThisHotkey) {
    TriggerMute()
}

TriggerMute() {
    global obsConnected, isMuted, ObsMuteHotkey
    
    ControlSend ObsMuteHotkey,, "ahk_exe obs64.exe"
    
    if (!obsConnected) {
        SyncUIState(!isMuted)
    }
}

PlayMuteAnimation() {
    global isMuted, colorLive, colorMuted, borderLive, borderMuted
    global iconLive, iconMuted, ShowText, MonoIcon, baseWidth, ShowIndicator
    global currentAlpha, baseAlpha, IconText, MicGui, AggressivePulse, breathDir
    
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
    
    Loop 10 {
        currentAlpha -= fadeStep
        if (currentAlpha < 0)
            currentAlpha := 0
        
        widthIncrement := ShowText ? 1.5 : 1
        popWidth := Round(baseWidth + (A_Index * widthIncrement))
        popHeight := Round(40 + (A_Index * 0.5))
        offsetX := Round((popWidth - baseWidth) / 2) 
        offsetY := Round((popHeight - 40) / 2)
        
        MicGui.Move(baseX - offsetX, baseY - offsetY, popWidth, popHeight)
        
        if (ShowText) {
            IconText.Move(offsetX + 15, offsetY, 30, 40) 
            LabelText.Move(offsetX + 50, offsetY, 80, 40)
        } else {
            IconText.Move(offsetX, offsetY, 80, 40) 
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
        
        widthIncrement := ShowText ? 1.5 : 1
        popWidth := Round((baseWidth + (10 * widthIncrement)) - (A_Index * widthIncrement))
        popHeight := Round(45 - (A_Index * 0.5))
        offsetX := Round((popWidth - baseWidth) / 2)
        offsetY := Round((popHeight - 40) / 2)
        
        MicGui.Move(baseX - offsetX, baseY - offsetY, popWidth, popHeight)
        
        if (ShowText) {
            IconText.Move(offsetX + 15, offsetY, 30, 40)
            LabelText.Move(offsetX + 50, offsetY, 80, 40)
        } else {
            IconText.Move(offsetX, offsetY, 80, 40)
        }
        
        WinSetTransparent(currentAlpha, MicGui.Hwnd)
        Sleep 10
    }
    
    currentAlpha := baseAlpha
    MicGui.Move(baseX, baseY, baseWidth, 40)
    
    if (ShowText) {
        IconText.Move(15, 0, 30, 40) 
        LabelText.Move(50, 0, 80, 40)
    } else {
        IconText.Move(0, 0, 80, 40)
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
