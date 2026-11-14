Hotkey("^!+F19", (*) => 0, "S")
Suspend(true)
ListHotkeys()
Sleep 100
txt := ControlGetText("Edit1", "ahk_id " A_ScriptHwnd)
FileAppend(txt, "tests\_hk_probe.txt", "UTF-8")
ExitApp()
