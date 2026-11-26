; ==============================================================================
; Module: ConfigStore.ahk
; Description: Atomic INI persistence, .bak crash recovery, DPAPI per-user
;              secret vaulting (Guardrail #2 soft-fallback on undecryptable
;              blobs), schema migration, and %APPDATA% data-dir resolution.
; ==============================================================================

#DllLoad crypt32.dll

class ConfigStore {
    static CURRENT_SCHEMA_VERSION := 2
    static DPAPI_PREFIX := "DPAPI_B64:"
    static _RtlZeroAvailable := true

    static IsSecretKey(section, key) {
        sec := StrLower(Trim(String(section)))
        k := StrLower(Trim(String(key)))
        if (k = "obspassword" || k = "bridgetoken" || k = "sessiontoken"
            || k = "sessionpairingcode" || k = "internetpairingcode" || k = "kioskpin")
            return true
        if (InStr(sec, "profile:") = 1) {
            if (RegExMatch(k, "^(settings|connection)_(obspassword|bridgetoken|sessiontoken|sessionpairingcode|internetpairingcode|kioskpin)$"))
                return true
        }
        return false
    }

    static IsSecretValueEncrypted(rawVal) {
        val := String(rawVal)
        return (SubStr(val, 1, StrLen(this.DPAPI_PREFIX)) = this.DPAPI_PREFIX)
    }

    static _B64Encode(buf) {
        if (!IsObject(buf) || buf.Size <= 0)
            return ""
        ; CRYPT_STRING_BASE64 (0x1) | CRYPT_STRING_NOCRLF (0x40000000)
        flags := 0x40000001
        cch := 0
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", 0, "UInt*", &cch, "Int")
            return ""
        if (cch <= 0)
            return ""
        out := Buffer(cch * 2, 0)
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", out.Ptr, "UInt*", &cch, "Int")
            return ""
        return Trim(StrGet(out.Ptr, cch, "UTF-16"), "`r`n `t`0")
    }

    static _B64Decode(b64Str) {
        clean := RegExReplace(Trim(String(b64Str)), "\s+", "")
        if (clean = "")
            return ""
        cb := 0
        flags := 0x1 ; CRYPT_STRING_BASE64
        if !DllCall("crypt32\CryptStringToBinaryW", "Str", clean, "UInt", StrLen(clean), "UInt", flags, "Ptr", 0, "UInt*", &cb, "Ptr", 0, "Ptr", 0, "Int")
            return ""
        if (cb <= 0)
            return ""
        out := Buffer(cb, 0)
        if !DllCall("crypt32\CryptStringToBinaryW", "Str", clean, "UInt", StrLen(clean), "UInt", flags, "Ptr", out.Ptr, "UInt*", &cb, "Ptr", 0, "Ptr", 0, "Int")
            return ""
        if (cb < out.Size) {
            exact := Buffer(cb, 0)
            DllCall("kernel32\RtlMoveMemory", "Ptr", exact.Ptr, "Ptr", out.Ptr, "UPtr", cb)
            return exact
        }
        return out
    }

    static _ZeroBuf(buf) {
        if (IsObject(buf) && buf.Size > 0)
            try DllCall("kernel32\RtlZeroMemory", "Ptr", buf.Ptr, "UPtr", buf.Size)
    }

    static _RecordDiag(tag, msg) {
        if (IsSet(DiagnosticLogger)) {
            try DiagnosticLogger.RecordBreadcrumb("ConfigStore", String(tag), String(msg))
        }
    }

    ; Encrypts plaintext with Windows DPAPI (CurrentUser scope). Empty values return "".
    static ProtectSecret(plainVal) {
        s := String(plainVal)
        if (s = "")
            return ""
        if (this.IsSecretValueEncrypted(s))
            return s
        byteLen := StrPut(s, "UTF-8") - 1
        if (byteLen <= 0)
            return ""
        inBuf := Buffer(byteLen, 0)
        StrPut(s, inBuf, byteLen, "UTF-8")

        inBlob := Buffer(A_PtrSize * 2, 0)
        NumPut("UInt", byteLen, inBlob, 0)
        NumPut("Ptr", inBuf.Ptr, inBlob, A_PtrSize)
        outBlob := Buffer(A_PtrSize * 2, 0)

        ok := false
        b64 := ""
        try {
            ; CRYPTPROTECT_UI_FORBIDDEN = 0x1
            ok := DllCall("crypt32\CryptProtectData"
                , "Ptr", inBlob.Ptr
                , "Ptr", 0
                , "Ptr", 0
                , "Ptr", 0
                , "Ptr", 0
                , "UInt", 0x1
                , "Ptr", outBlob.Ptr
                , "Int")
            if (ok) {
                cbOut := NumGet(outBlob, 0, "UInt")
                pbOut := NumGet(outBlob, A_PtrSize, "Ptr")
                if (cbOut > 0 && pbOut != 0) {
                    cipherBuf := Buffer(cbOut, 0)
                    DllCall("kernel32\RtlMoveMemory", "Ptr", cipherBuf.Ptr, "Ptr", pbOut, "UPtr", cbOut)
                    b64 := this._B64Encode(cipherBuf)
                }
            }
        } catch as err {
            this._RecordDiag("DpapiProtectErr", err.Message)
        } finally {
            pbOutFree := NumGet(outBlob, A_PtrSize, "Ptr")
            if (pbOutFree != 0)
                try DllCall("kernel32\LocalFree", "Ptr", pbOutFree, "Ptr")
            this._ZeroBuf(inBuf)
        }
        if (b64 = "") {
            this._RecordDiag("DpapiProtectFailed", "DPAPI unavailable; storing raw fallback")
            return s
        }
        return this.DPAPI_PREFIX b64
    }

    ; Decrypts DPAPI_B64:... blobs. Guardrail #2: on corruption or wrong user/PC,
    ; fail softly to "" + diagnostic breadcrumb instead of throwing at startup.
    static UnprotectSecret(rawVal, contextTag := "") {
        s := String(rawVal)
        if (s = "")
            return ""
        if (!this.IsSecretValueEncrypted(s))
            return s

        b64Part := SubStr(s, StrLen(this.DPAPI_PREFIX) + 1)
        if (Trim(b64Part) = "") {
            this._RecordDiag("DpapiEmptyCipher", contextTag)
            return ""
        }
        encBuf := this._B64Decode(b64Part)
        if (!IsObject(encBuf) || encBuf.Size <= 0) {
            this._RecordDiag("DpapiInvalidB64", contextTag)
            return ""
        }

        inBlob := Buffer(A_PtrSize * 2, 0)
        NumPut("UInt", encBuf.Size, inBlob, 0)
        NumPut("Ptr", encBuf.Ptr, inBlob, A_PtrSize)
        outBlob := Buffer(A_PtrSize * 2, 0)

        plain := ""
        try {
            ; CRYPTPROTECT_UI_FORBIDDEN = 0x1
            ok := DllCall("crypt32\CryptUnprotectData"
                , "Ptr", inBlob.Ptr
                , "Ptr", 0
                , "Ptr", 0
                , "Ptr", 0
                , "Ptr", 0
                , "UInt", 0x1
                , "Ptr", outBlob.Ptr
                , "Int")
            if (!ok) {
                errCode := DllCall("kernel32\GetLastError", "UInt")
                this._RecordDiag("DpapiUnprotectSoftFail", contextTag " (err=" errCode ")")
                return ""
            }
            cbOut := NumGet(outBlob, 0, "UInt")
            pbOut := NumGet(outBlob, A_PtrSize, "Ptr")
            if (cbOut > 0 && pbOut != 0)
                plain := StrGet(pbOut, cbOut, "UTF-8")
        } catch as err {
            this._RecordDiag("DpapiUnprotectException", contextTag ": " err.Message)
            plain := ""
        } finally {
            pbOutFree := NumGet(outBlob, A_PtrSize, "Ptr")
            cbOutFree := NumGet(outBlob, 0, "UInt")
            if (pbOutFree != 0) {
                if (cbOutFree > 0)
                    try DllCall("kernel32\RtlZeroMemory", "Ptr", pbOutFree, "UPtr", cbOutFree)
                try DllCall("kernel32\LocalFree", "Ptr", pbOutFree, "Ptr")
            }
        }
        return plain
    }

    static IsDirWritable(dirPath) {
        if (dirPath = "" || !DirExist(dirPath))
            return false
        pid := DllCall("kernel32\GetCurrentProcessId", "UInt")
        probe := RTrim(dirPath, "\/") "\.ps_write_probe_" A_TickCount "_" pid ".tmp"
        try {
            f := FileOpen(probe, "w")
            if (!IsObject(f))
                return false
            f.Write("1")
            f.Close()
            FileDelete(probe)
            return true
        } catch {
            try if FileExist(probe)
                FileDelete(probe)
            return false
        }
    }

    static ResolveDataDir(appBaseDir := "", preferAppData := false) {
        baseDir := (appBaseDir != "") ? RTrim(String(appBaseDir), "\/") : RTrim(A_ScriptDir, "\/")
        if (!preferAppData && FileExist(baseDir "\portable.flag"))
            return baseDir

        useAppData := !!preferAppData
        if (!useAppData) {
            pf := RTrim(EnvGet("ProgramFiles"), "\/")
            pf86 := RTrim(EnvGet("ProgramFiles(x86)"), "\/")
            lowBase := StrLower(baseDir)
            if ((pf != "" && InStr(lowBase, StrLower(pf)) = 1)
                || (pf86 != "" && InStr(lowBase, StrLower(pf86)) = 1)) {
                useAppData := true
            } else if (!this.IsDirWritable(baseDir)) {
                useAppData := true
            }
        }
        if (!useAppData)
            return baseDir

        appDataRoot := RTrim(A_AppData, "\/") "\PresenterSync"
        try {
            if (!DirExist(appDataRoot))
                DirCreate(appDataRoot)
        }
        return DirExist(appDataRoot) ? appDataRoot : baseDir
    }

    static EnsureParentDir(filePath) {
        if (filePath = "")
            return false
        SplitPath(filePath, , &dir)
        if (dir != "" && !DirExist(dir)) {
            try DirCreate(dir)
            catch
                return false
        }
        return true
    }

    static AtomicWriteText(filePath, content, encoding := "UTF-8") {
        if (filePath = "")
            return false
        this.EnsureParentDir(filePath)
        tmpPath := filePath ".tmp." A_TickCount
        try {
            f := FileOpen(tmpPath, "w", encoding)
            if (!IsObject(f))
                return false
            f.Write(String(content))
            f.Close()
            FileMove(tmpPath, filePath, 1)
            return true
        } catch as err {
            this._RecordDiag("AtomicWriteErr", err.Message)
            try if FileExist(tmpPath)
                FileDelete(tmpPath)
            return false
        }
    }

    static IsValidIniFile(filePath, requiredSection := "") {
        if (filePath = "" || !FileExist(filePath))
            return false
        sz := 0
        try sz := FileGetSize(filePath)
        catch
            return false
        if (sz <= 0)
            return false
        if (requiredSection != "") {
            try {
                sec := IniRead(filePath, requiredSection, , "")
                if (sec != "")
                    return true
            }
        }
        try {
            raw := FileRead(filePath)
            if (requiredSection != "") {
                escSec := RegExReplace(requiredSection, "[.*+?^${}()|\[\]\\]", "\$0")
                if (RegExMatch(raw, "im)^\s*\[" escSec "\]") > 0)
                    return true
            } else {
                if (RegExMatch(raw, "im)^\s*\[[^\r\n\]]+\]") > 0)
                    return true
            }
        }
        return false
    }

    static BackupIniFile(iniPath, requiredSection := "") {
        if (iniPath = "" || !this.IsValidIniFile(iniPath, requiredSection))
            return false
        bakPath := iniPath ".bak"
        tmpPath := bakPath ".tmp"
        try {
            FileCopy(iniPath, tmpPath, 1)
            FileMove(tmpPath, bakPath, 1)
            return true
        } catch {
            try if FileExist(tmpPath)
                FileDelete(tmpPath)
            return false
        }
    }

    static RecoverIniFromBackup(iniPath, requiredSection := "") {
        if (iniPath = "")
            return false
        bakPath := iniPath ".bak"
        if (!this.IsValidIniFile(iniPath, requiredSection) && this.IsValidIniFile(bakPath, requiredSection)) {
            this.EnsureParentDir(iniPath)
            try {
                FileCopy(bakPath, iniPath, 1)
                this._RecordDiag("RecoveredFromBak", iniPath)
                return true
            } catch as err {
                this._RecordDiag("RecoverBakFailed", err.Message)
            }
        }
        return false
    }

    ; Atomically replaces an entire INI section without risking partial IniDelete + crash loss.
    static AtomicReplaceIniSection(iniPath, section, entriesMap) {
        if (iniPath = "" || section = "")
            return false
        this.EnsureParentDir(iniPath)
        tmpPath := iniPath ".sec.tmp"
        try {
            if FileExist(iniPath) {
                FileCopy(iniPath, tmpPath, 1)
            } else {
                f := FileOpen(tmpPath, "w", "UTF-16")
                if (IsObject(f))
                    f.Close()
            }
            try IniDelete(tmpPath, section)
            if (IsObject(entriesMap)) {
                for key, val in entriesMap {
                    kStr := Trim(String(key))
                    if (kStr = "")
                        continue
                    IniWrite(String(val), tmpPath, section, kStr)
                }
            }
            FileMove(tmpPath, iniPath, 1)
            return true
        } catch as err {
            this._RecordDiag("AtomicReplaceSecErr", err.Message)
            try if FileExist(tmpPath)
                FileDelete(tmpPath)
            return false
        }
    }

    ; Migrates legacy plaintext secret keys in [Settings]/[Connection] to DPAPI_B64: and stamps SchemaVersion=2.
    static MigrateIniSchema(iniPath, secretSection := "Settings") {
        if (iniPath = "" || !FileExist(iniPath))
            return false
        curVer := 0
        try {
            rawVer := Trim(IniRead(iniPath, "ConfigMeta", "SchemaVersion", "1"))
            curVer := IsInteger(rawVer) ? Integer(rawVer) : 1
        }
        if (curVer >= this.CURRENT_SCHEMA_VERSION)
            return false

        tmpPath := iniPath ".mig.tmp"
        try {
            FileCopy(iniPath, tmpPath, 1)
            secretKeys := ["ObsPassword", "BridgeToken", "SessionToken", "SessionPairingCode", "InternetPairingCode"]
            for _, k in secretKeys {
                rawVal := ""
                try rawVal := IniRead(tmpPath, secretSection, k, "__MISSING__")
                if (rawVal != "__MISSING__" && rawVal != "" && !this.IsSecretValueEncrypted(rawVal)) {
                    prot := this.ProtectSecret(rawVal)
                    if (prot != "")
                        IniWrite(prot, tmpPath, secretSection, k)
                }
            }
            IniWrite(this.CURRENT_SCHEMA_VERSION, tmpPath, "ConfigMeta", "SchemaVersion")
            FileMove(tmpPath, iniPath, 1)
            this._RecordDiag("SchemaMigrated", iniPath " -> v" this.CURRENT_SCHEMA_VERSION)
            return true
        } catch as err {
            this._RecordDiag("SchemaMigrateErr", err.Message)
            try if FileExist(tmpPath)
                FileDelete(tmpPath)
            return false
        }
    }

    static ExportDeploymentBundle(cfg, includeSecrets := false) {
        if (!IsObject(cfg))
            return "{}"
        keys := ["AudioRoutingMode", "BridgePort", "ObsWsHost", "ObsWsPort", "StandbySceneName", "PanicSceneName", "QuickNudgePresets", "RunOfShowMacros", "HwMuteHotkey", "ObsMuteHotkey", "ZoomMuteHotkey", "AutoProfileRules"]
        if (includeSecrets)
            keys.Push("obsPassword", "InternetPairingCode")
        out := '{"bundleVersion":1,'
        first := true
        for _, k in keys {
            if (cfg.HasOwnProp(k)) {
                v := String(cfg.%k%)
                v := StrReplace(StrReplace(StrReplace(v, "\", "\\"), '"', '\"'), "`n", "\n")
                out .= (first ? "" : ",") '"' k '":"' v '"'
                first := false
            }
        }
        return out . "}"
    }

    static ImportDeploymentBundle(cfg, jsonStr) {
        if (!IsObject(cfg) || Trim(String(jsonStr)) = "")
            return false
        keys := ["AudioRoutingMode", "BridgePort", "ObsWsHost", "ObsWsPort", "StandbySceneName", "PanicSceneName", "QuickNudgePresets", "RunOfShowMacros", "HwMuteHotkey", "ObsMuteHotkey", "ZoomMuteHotkey", "AutoProfileRules"]
        applied := 0
        for _, k in keys {
            if (RegExMatch(jsonStr, '"' k '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)) {
                val := StrReplace(StrReplace(StrReplace(m[1], "\n", "`n"), '\"', '"'), "\\", "\")
                if (k = "AudioRoutingMode" || k = "BridgePort" || k = "ObsWsPort") {
                    if (IsInteger(val))
                        cfg.%k% := Integer(val)
                } else {
                    cfg.%k% := val
                }
                applied++
            }
        }
        return applied > 0
    }
}
