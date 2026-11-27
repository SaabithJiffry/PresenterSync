; ==============================================================================
; Minimal Windows UI Automation (UIA) Helper for AutoHotkey v2
; Used by PresenterSync to inspect Zoom meeting controls in the background
; ==============================================================================

class UIA {
    static _instance := 0
    static _trueCond := 0
    static _btnCond := 0
    static _confCond := 0
    static _nameCacheReq := 0
    static _confCacheReq := 0

    static Init() {
        if (!this._instance) {
            ; CLSID_CUIAutomation = {ff48dba4-60ef-4201-aa87-54103eef594e}
            ; IID_IUIAutomation   = {30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}
            this._instance := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        }
        return this._instance
    }

    static Shutdown() {
        if (this._confCacheReq) {
            ObjRelease(this._confCacheReq)
            this._confCacheReq := 0
        }
        if (this._nameCacheReq) {
            ObjRelease(this._nameCacheReq)
            this._nameCacheReq := 0
        }
        if (this._confCond) {
            ObjRelease(this._confCond)
            this._confCond := 0
        }
        if (this._btnCond) {
            ObjRelease(this._btnCond)
            this._btnCond := 0
        }
        if (this._trueCond) {
            ObjRelease(this._trueCond)
            this._trueCond := 0
        }
        this._instance := 0
    }

    static GetNameCacheRequest() {
        uiaObj := this.Init()
        if (!this._nameCacheReq) {
            pReq := 0
            try {
                ComCall(20, uiaObj, "ptr*", &pReq) ; CreateCacheRequest
                if (pReq) {
                    ComCall(3, pReq, "int", 30005) ; AddProperty(UIA_NamePropertyId = 30005)
                    ComCall(11, pReq, "int", 0)    ; put_AutomationElementMode(AutomationElementMode_None = 0)
                    this._nameCacheReq := pReq
                }
            } catch {
                if (pReq)
                    ObjRelease(pReq)
            }
        }
        return this._nameCacheReq
    }

    ; Multi-property CacheRequest for modern conferencing apps (Zoom Workplace v6.x, Teams, Meet)
    static GetConfCacheRequest() {
        uiaObj := this.Init()
        if (!this._confCacheReq) {
            pReq := 0
            try {
                ComCall(20, uiaObj, "ptr*", &pReq) ; CreateCacheRequest
                if (pReq) {
                    for _, propId in [30005, 30003, 30013, 30159, 30011, 30045, 30094] {
                        try ComCall(3, pReq, "int", propId)
                    }
                    ComCall(11, pReq, "int", 0) ; AutomationElementMode_None = 0
                    this._confCacheReq := pReq
                }
            } catch {
                if (pReq)
                    ObjRelease(pReq)
            }
        }
        return this._confCacheReq
    }

    static _CreateControlTypeCondition(ctId) {
        uiaObj := this.Init()
        varSize := (A_PtrSize == 8) ? 24 : 16
        varBuf := Buffer(varSize, 0)
        NumPut("UShort", 3, varBuf, 0)
        NumPut("Int", ctId, varBuf, 8)
        pCond := 0
        try {
            if (A_PtrSize == 8)
                ComCall(23, uiaObj, "int", 30003, "ptr", varBuf, "ptr*", &pCond)
            else
                ComCall(23, uiaObj, "int", 30003, "int64", NumGet(varBuf, 0, "int64"), "int64", NumGet(varBuf, 8, "int64"), "ptr*", &pCond)
        } catch {
            if (pCond)
                ObjRelease(pCond)
            pCond := 0
        }
        return pCond
    }

    static GetConfControlCondition() {
        uiaObj := this.Init()
        if (this._confCond)
            return this._confCond
        ; Button(50000), SplitButton(50031), MenuItem(50011), CheckBox(50002), Text(50020), Custom(50025), Group(50026)
        ctIds := [50000, 50031, 50011, 50002, 50020, 50025, 50026]
        acc := 0
        for _, ctId in ctIds {
            c := this._CreateControlTypeCondition(ctId)
            if (!c)
                continue
            if (!acc) {
                acc := c
            } else {
                pOr := 0
                try {
                    ComCall(28, uiaObj, "ptr", acc, "ptr", c, "ptr*", &pOr) ; IUIAutomation::CreateOrCondition
                } catch {
                    pOr := 0
                }
                ObjRelease(c)
                if (pOr) {
                    ObjRelease(acc)
                    acc := pOr
                }
            }
        }
        this._confCond := acc
        return this._confCond
    }

    static GetTrueCondition() {
        uiaObj := this.Init()
        if (!this._trueCond) {
            pCond := 0
            ComCall(21, uiaObj, "ptr*", &pCond) ; CreateTrueCondition
            this._trueCond := pCond
        }
        return this._trueCond
    }

    static GetButtonCondition() {
        uiaObj := this.Init()
        if (!this._btnCond) {
            ; VARIANT for VT_I4 (3), value = 50000 (UIA_ButtonControlTypeId)
            varSize := (A_PtrSize == 8) ? 24 : 16
            varBuf := Buffer(varSize, 0)
            NumPut("UShort", 3, varBuf, 0)
            NumPut("Int", 50000, varBuf, 8)
            pCond := 0
            if (A_PtrSize == 8) {
                ComCall(23, uiaObj, "int", 30003, "ptr", varBuf, "ptr*", &pCond) ; CreatePropertyCondition
            } else {
                ComCall(23, uiaObj, "int", 30003, "int64", NumGet(varBuf, 0, "int64"), "int64", NumGet(varBuf, 8, "int64"), "ptr*", &pCond)
            }
            this._btnCond := pCond
        }
        return this._btnCond
    }

    static ElementFromHandle(hwnd) {
        if (!hwnd)
            return 0
        uiaObj := this.Init()
        pElem := 0
        try {
            ComCall(6, uiaObj, "ptr", hwnd, "ptr*", &pElem) ; ElementFromHandle
        } catch {
            return 0
        }
        return pElem
    }

    static GetElementName(pElem) {
        if (!pElem)
            return ""
        bstr := 0
        name := ""
        try {
            ComCall(23, pElem, "ptr*", &bstr) ; get_CurrentName
            if (bstr)
                name := StrGet(bstr, "UTF-16")
        } catch {
        } finally {
            if (bstr)
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
        }
        return name
    }

    static GetCachedElementName(pElem) {
        if (!pElem)
            return ""
        bstr := 0
        name := ""
        try {
            ComCall(55, pElem, "ptr*", &bstr) ; get_CachedName
            if (bstr)
                name := StrGet(bstr, "UTF-16")
        } catch {
        } finally {
            if (bstr)
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
        }
        return name
    }

    static GetElementControlType(pElem) {
        if (!pElem)
            return 0
        ct := 0
        try {
            ComCall(21, pElem, "int*", &ct) ; get_CurrentControlType
        }
        return ct
    }

    static GetCachedElementControlType(pElem) {
        if (!pElem)
            return 0
        ct := 0
        try {
            ComCall(53, pElem, "int*", &ct) ; get_CachedControlType
        }
        return ct
    }

    static GetCachedElementAutomationId(pElem) {
        if (!pElem)
            return ""
        bstr := 0
        val := ""
        try {
            ComCall(61, pElem, "ptr*", &bstr) ; get_CachedAutomationId
            if (bstr)
                val := StrGet(bstr, "UTF-16")
        } catch {
        } finally {
            if (bstr)
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
        }
        return val
    }

    static GetCachedElementHelpText(pElem) {
        if (!pElem)
            return ""
        bstr := 0
        val := ""
        try {
            ComCall(63, pElem, "ptr*", &bstr) ; get_CachedHelpText
            if (bstr)
                val := StrGet(bstr, "UTF-16")
        } catch {
        } finally {
            if (bstr)
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
        }
        return val
    }

    static GetCachedStringProperty(pElem, propId) {
        if (!pElem)
            return ""
        varSize := (A_PtrSize == 8) ? 24 : 16
        varBuf := Buffer(varSize, 0)
        val := ""
        try {
            ComCall(12, pElem, "int", propId, "ptr", varBuf) ; GetCachedPropertyValue
            if (NumGet(varBuf, 0, "UShort") == 8) { ; VT_BSTR
                bstr := NumGet(varBuf, 8, "Ptr")
                if (bstr)
                    val := StrGet(bstr, "UTF-16")
            }
        } catch {
        } finally {
            DllCall("oleaut32\VariantClear", "ptr", varBuf)
        }
        return val
    }

    static IsWindowElevatedMismatch(hwnd) {
        if (!hwnd)
            return false
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if (!pid || A_IsAdmin)
            return false
        hProc := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        if (!hProc)
            return true
        elevated := false
        hTok := 0
        try {
            if (DllCall("Advapi32\OpenProcessToken", "Ptr", hProc, "UInt", 0x0008, "Ptr*", &hTok)) {
                buf := Buffer(4, 0)
                retLen := 0
                if (DllCall("Advapi32\GetTokenInformation", "Ptr", hTok, "Int", 20, "Ptr", buf, "UInt", 4, "UInt*", &retLen))
                    elevated := (NumGet(buf, 0, "UInt") != 0)
                DllCall("CloseHandle", "Ptr", hTok)
            }
        } finally {
            DllCall("CloseHandle", "Ptr", hProc)
        }
        return elevated
    }

    ; Targeted multi-property conferencing UIA scan strictly bounded by maxBudgetMs and maxNodes
    static FindConferencingNodes(hwnd, maxBudgetMs := 12, maxNodes := 160) {
        nodes := []
        pRoot := this.ElementFromHandle(hwnd)
        if (!pRoot)
            return nodes

        startTick := A_TickCount
        pArr := 0
        try {
            pCond := this.GetConfControlCondition()
            if (!pCond)
                pCond := this.GetTrueCondition()
            pCacheReq := this.GetConfCacheRequest()
            if (pCond && pCacheReq) {
                ComCall(8, pRoot, "int", 4, "ptr", pCond, "ptr", pCacheReq, "ptr*", &pArr) ; FindAllBuildCache
            } else if (pCond) {
                ComCall(6, pRoot, "int", 4, "ptr", pCond, "ptr*", &pArr) ; FindAll
            }
            if (pArr) {
                len := 0
                ComCall(3, pArr, "int*", &len)
                limit := Min(len, Max(1, Integer(maxNodes)))
                Loop limit {
                    if ((A_TickCount - startTick) >= maxBudgetMs)
                        break
                    pChild := 0
                    try {
                        ComCall(4, pArr, "int", A_Index - 1, "ptr*", &pChild)
                        if (pChild) {
                            nm := pCacheReq ? this.GetCachedElementName(pChild) : this.GetElementName(pChild)
                            ct := pCacheReq ? this.GetCachedElementControlType(pChild) : this.GetElementControlType(pChild)
                            ht := pCacheReq ? this.GetCachedElementHelpText(pChild) : ""
                            fd := pCacheReq ? this.GetCachedStringProperty(pChild, 30159) : ""
                            aid := pCacheReq ? this.GetCachedElementAutomationId(pChild) : ""
                            val := pCacheReq ? this.GetCachedStringProperty(pChild, 30045) : ""
                            ld := pCacheReq ? this.GetCachedStringProperty(pChild, 30094) : ""
                            if (nm != "" || ht != "" || fd != "" || aid != "" || val != "" || ld != "") {
                                nodes.Push({
                                    name: nm,
                                    controlType: ct,
                                    helpText: ht,
                                    fullDescription: fd,
                                    automationId: aid,
                                    value: val,
                                    legacyDesc: ld
                                })
                            }
                        }
                    } catch {
                    } finally {
                        if (pChild)
                            ObjRelease(pChild)
                    }
                }
            }
        } catch {
        } finally {
            if (pArr)
                ObjRelease(pArr)
            if (pRoot)
                ObjRelease(pRoot)
        }
        return nodes
    }

    ; Returns an array of non-empty element names (optionally filtered to Button controls)
    static GetWindowElementNames(hwnd, buttonsOnly := true) {
        names := []
        pRoot := this.ElementFromHandle(hwnd)
        if (!pRoot)
            return names

        pArr := 0
        useCached := false
        try {
            pCond := buttonsOnly ? this.GetButtonCondition() : this.GetTrueCondition()
            pCacheReq := this.GetNameCacheRequest()
            if (pCond && pCacheReq) {
                ComCall(8, pRoot, "int", 4, "ptr", pCond, "ptr", pCacheReq, "ptr*", &pArr) ; FindAllBuildCache(TreeScope_Descendants = 4)
                useCached := (pArr != 0)
            }
            if (!pArr && pCond) {
                ComCall(6, pRoot, "int", 4, "ptr", pCond, "ptr*", &pArr) ; FindAll(TreeScope_Descendants = 4)
            }
            if (pArr) {
                len := 0
                ComCall(3, pArr, "int*", &len) ; get_Length
                Loop len {
                    pChild := 0
                    try {
                        ComCall(4, pArr, "int", A_Index - 1, "ptr*", &pChild) ; GetElement
                        if (pChild) {
                            name := useCached ? this.GetCachedElementName(pChild) : this.GetElementName(pChild)
                            if (name != "")
                                names.Push(name)
                        }
                    } catch {
                    } finally {
                        if (pChild)
                            ObjRelease(pChild)
                    }
                }
            }
        } catch {
        } finally {
            if (pArr)
                ObjRelease(pArr)
            if (pRoot)
                ObjRelease(pRoot)
        }
        return names
    }
}

