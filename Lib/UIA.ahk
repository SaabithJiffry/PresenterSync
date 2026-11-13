; ==============================================================================
; Minimal Windows UI Automation (UIA) Helper for AutoHotkey v2
; Used by PresenterSync to inspect Zoom meeting controls in the background
; ==============================================================================

class UIA {
    static _instance := 0
    static _trueCond := 0
    static _btnCond := 0
    static _nameCacheReq := 0

    static Init() {
        if (!this._instance) {
            ; CLSID_CUIAutomation = {ff48dba4-60ef-4201-aa87-54103eef594e}
            ; IID_IUIAutomation   = {30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}
            this._instance := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        }
        return this._instance
    }

    static Shutdown() {
        if (this._nameCacheReq) {
            ObjRelease(this._nameCacheReq)
            this._nameCacheReq := 0
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
            if (bstr) {
                name := StrGet(bstr, "UTF-16")
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
            }
        } catch {
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
            if (bstr) {
                name := StrGet(bstr, "UTF-16")
                DllCall("oleaut32\SysFreeString", "ptr", bstr)
            }
        } catch {
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

    ; Returns an array of non-empty element names (optionally filtered to Button controls)
    static GetWindowElementNames(hwnd, buttonsOnly := true) {
        names := []
        pRoot := this.ElementFromHandle(hwnd)
        if (!pRoot)
            return names

        pCond := buttonsOnly ? this.GetButtonCondition() : this.GetTrueCondition()
        pCacheReq := this.GetNameCacheRequest()
        pArr := 0
        useCached := false
        try {
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
                            ObjRelease(pChild)
                        }
                    } catch {
                        if (pChild)
                            ObjRelease(pChild)
                    }
                }
                ObjRelease(pArr)
            }
        } catch {
            if (pArr)
                ObjRelease(pArr)
        }
        ObjRelease(pRoot)
        return names
    }
}

