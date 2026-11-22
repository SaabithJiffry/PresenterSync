; ==============================================================================
; Module: Crypto.ahk
; Description: SHA-256 / SHA-1 + Base64 / Hex cryptography & CSPRNG helpers
;              for OBS WebSocket v5 auth, RFC 6455 server handshake, & Pairing
; ==============================================================================

#DllLoad bcrypt.dll
#DllLoad crypt32.dll

_HashCryptRaw(algId, hashLen, stringToHash) {
    size := StrPut(stringToHash, "UTF-8") - 1
    buf := Buffer(Max(1, size), 0)
    if (size > 0)
        StrPut(stringToHash, buf, "UTF-8")

    hashBuf := Buffer(hashLen, 0)
    hAlg := 0
    hHash := 0
    try {
        if (DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", algId, "Ptr", 0, "UInt", 0, "Int") != 0)
            return hashBuf
        if (DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "Int") != 0)
            return hashBuf
        if (size > 0)
            DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", size, "UInt", 0, "Int")
        DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hashBuf, "UInt", hashLen, "UInt", 0, "Int")
    } finally {
        if (hHash)
            try DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
        if (hAlg)
            try DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    }

    return hashBuf
}

_BytesToBase64(buf, byteLen) {
    b64Len := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", byteLen, "UInt", 0x40000001, "Ptr", 0, "UInt*", &b64Len)
    b64Buf := Buffer(b64Len * 2, 0)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", byteLen, "UInt", 0x40000001, "Ptr", b64Buf, "UInt*", &b64Len)
    return StrGet(b64Buf)
}

HashSHA256_Base64(stringToHash) {
    hashBuf := _HashCryptRaw("SHA256", 32, stringToHash)
    return _BytesToBase64(hashBuf, 32)
}

HashSHA1_Base64(stringToHash) {
    hashBuf := _HashCryptRaw("SHA1", 20, stringToHash)
    return _BytesToBase64(hashBuf, 20)
}

_BytesToHexLower(buf, byteLen) {
    hex := ""
    Loop byteLen
        hex .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return hex
}

HashSHA256_Hex(stringToHash) {
    hashBuf := _HashCryptRaw("SHA256", 32, stringToHash)
    return _BytesToHexLower(hashBuf, 32)
}

HashFileSHA256_Hex(filePath) {
    if (!FileExist(filePath))
        return ""
    f := ""
    hAlg := 0
    hHash := 0
    try {
        f := FileOpen(filePath, "r")
        if (!IsObject(f))
            return ""
        if (DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", "SHA256", "Ptr", 0, "UInt", 0) != 0)
            return ""
        if (DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0) != 0)
            return ""

        buf := Buffer(65536, 0)
        while ((bytesRead := f.RawRead(buf, 65536)) > 0) {
            if (DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", bytesRead, "UInt", 0) != 0)
                return ""
        }

        hashBuf := Buffer(32, 0)
        if (DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hashBuf, "UInt", 32, "UInt", 0) != 0)
            return ""
        return _BytesToHexLower(hashBuf, 32)
    } catch {
        return ""
    } finally {
        if (IsObject(f))
            try f.Close()
        if (hHash)
            try DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
        if (hAlg)
            try DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    }
}

GenerateRandomBytes(byteCount) {
    buf := Buffer(Max(1, byteCount), 0)
    DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", buf, "UInt", byteCount, "UInt", 2)
    return buf
}

GenerateSessionPairingCode() {
    static alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    buf := GenerateRandomBytes(6)
    code := ""
    Loop 6 {
        idx := Mod(NumGet(buf, A_Index - 1, "UChar"), 32) + 1
        code .= SubStr(alphabet, idx, 1)
    }
    return SubStr(code, 1, 3) "-" SubStr(code, 4, 3)
}

NormalizePairingCode(rawCode) {
    return StrUpper(RegExReplace(Trim(String(rawCode)), "[\s-]+", ""))
}

_Base64ToBytes(b64Str) {
    clean := Trim(String(b64Str))
    if (clean = "" || RegExMatch(clean, "[^A-Za-z0-9+/=]"))
        return ""
    cbBin := 0
    if (!DllCall("crypt32\CryptStringToBinaryW", "Str", clean, "UInt", StrLen(clean), "UInt", 1, "Ptr", 0, "UInt*", &cbBin, "Ptr", 0, "Ptr", 0))
        return ""
    if (cbBin == 0)
        return Buffer(0)
    outBuf := Buffer(cbBin, 0)
    if (!DllCall("crypt32\CryptStringToBinaryW", "Str", clean, "UInt", StrLen(clean), "UInt", 1, "Ptr", outBuf, "UInt*", &cbBin, "Ptr", 0, "Ptr", 0))
        return ""
    if (cbBin != outBuf.Size) {
        trimmed := Buffer(cbBin, 0)
        if (cbBin > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", trimmed.Ptr, "Ptr", outBuf.Ptr, "UPtr", cbBin)
        return trimmed
    }
    return outBuf
}

GetCurrentUnixEpochSec() {
    return DateDiff(A_NowUTC, "19700101000000", "Seconds")
}

GenerateRelaySessionId() {
    return _BytesToHexLower(GenerateRandomBytes(4), 4)
}

DeriveAesGcmKey32(pairingCode, secretSalt := "") {
    material := "PS_GCM_V1|" Trim(String(pairingCode)) "|" Trim(String(secretSalt))
    return _HashCryptRaw("SHA256", 32, material)
}

_BuildGcmAuthInfo(ivBuf, tagBuf) {
    if (A_PtrSize == 8) {
        ; 64-bit Windows SDK BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO (sizeof = 88):
        ; +0 cbSize(4), +4 dwInfoVersion(4), +8 pbNonce(8), +16 cbNonce(4),
        ; +24 pbAuthData(8), +32 cbAuthData(4), +40 pbTag(8), +48 cbTag(4),
        ; +56 pbMacContext(8), +64 cbMacContext(4), +68 cbAAD(4), +72 cbData(8), +80 dwFlags(4)
        info := Buffer(88, 0)
        NumPut("UInt", 88, info, 0)
        NumPut("UInt", 1, info, 4)
        NumPut("Ptr", ivBuf.Ptr, info, 8)
        NumPut("UInt", ivBuf.Size, info, 16)
        NumPut("Ptr", 0, info, 24)
        NumPut("UInt", 0, info, 32)
        NumPut("Ptr", tagBuf.Ptr, info, 40)
        NumPut("UInt", tagBuf.Size, info, 48)
        return info
    }
    ; 32-bit fallback (sizeof = 64)
    info := Buffer(64, 0)
    NumPut("UInt", 64, info, 0)
    NumPut("UInt", 1, info, 4)
    NumPut("Ptr", ivBuf.Ptr, info, 8)
    NumPut("UInt", ivBuf.Size, info, 12)
    NumPut("Ptr", 0, info, 16)
    NumPut("UInt", 0, info, 20)
    NumPut("Ptr", tagBuf.Ptr, info, 24)
    NumPut("UInt", tagBuf.Size, info, 28)
    return info
}

AesGcmEncryptBytes(plaintextStr, keyBuf, ivOverrideBuf := "") {
    if (!(keyBuf is Buffer) || keyBuf.Size != 32)
        return ""
    ivBuf := ""
    if (ivOverrideBuf is Buffer) {
        if (ivOverrideBuf.Size != 12)
            return ""
        ivBuf := ivOverrideBuf
    } else if (ivOverrideBuf != "") {
        ivBuf := _Base64ToBytes(ivOverrideBuf)
        if (!(ivBuf is Buffer) || ivBuf.Size != 12)
            return ""
    } else {
        ivBuf := GenerateRandomBytes(12)
    }

    ptStr := String(plaintextStr)
    ptLen := StrPut(ptStr, "UTF-8") - 1
    ptBuf := Buffer(Max(1, ptLen), 0)
    if (ptLen > 0)
        StrPut(ptStr, ptBuf, "UTF-8")

    hAlg := 0
    hKey := 0
    try {
        if (DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", "AES", "Ptr", 0, "UInt", 0, "Int") != 0)
            return ""
        modeName := "ChainingModeGCM"
        if (DllCall("bcrypt\BCryptSetProperty", "Ptr", hAlg, "Str", "ChainingMode", "Str", modeName, "UInt", (StrLen(modeName) + 1) * 2, "UInt", 0, "Int") != 0)
            return ""

        objLenBuf := Buffer(4, 0)
        cbObj := 0
        if (DllCall("bcrypt\BCryptGetProperty", "Ptr", hAlg, "Str", "ObjectLength", "Ptr", objLenBuf, "UInt", 4, "UInt*", &cbObj, "UInt", 0, "Int") != 0)
            return ""
        objLen := NumGet(objLenBuf, 0, "UInt")
        keyObjBuf := Buffer(Max(1, objLen), 0)

        if (DllCall("bcrypt\BCryptGenerateSymmetricKey", "Ptr", hAlg, "Ptr*", &hKey, "Ptr", keyObjBuf, "UInt", objLen, "Ptr", keyBuf, "UInt", 32, "UInt", 0, "Int") != 0)
            return ""

        tagBuf := Buffer(16, 0)
        ctBuf := Buffer(Max(1, ptLen), 0)
        authInfo := _BuildGcmAuthInfo(ivBuf, tagBuf)
        cbResult := 0
        st := DllCall("bcrypt\BCryptEncrypt",
            "Ptr", hKey,
            "Ptr", ptBuf.Ptr, "UInt", ptLen,
            "Ptr", authInfo.Ptr,
            "Ptr", 0, "UInt", 0,
            "Ptr", ctBuf.Ptr, "UInt", ptLen,
            "UInt*", &cbResult,
            "UInt", 0, "Int")
        if (st != 0 || cbResult != ptLen)
            return ""

        ctAndTag := Buffer(ptLen + 16, 0)
        if (ptLen > 0)
            DllCall("ntdll\RtlMoveMemory", "Ptr", ctAndTag.Ptr, "Ptr", ctBuf.Ptr, "UPtr", ptLen)
        DllCall("ntdll\RtlMoveMemory", "Ptr", ctAndTag.Ptr + ptLen, "Ptr", tagBuf.Ptr, "UPtr", 16)

        return {
            iv: _BytesToBase64(ivBuf, 12),
            ct: _BytesToBase64(ctAndTag, ptLen + 16)
        }
    } catch {
        return ""
    } finally {
        if (hKey)
            try DllCall("bcrypt\BCryptDestroyKey", "Ptr", hKey)
        if (hAlg)
            try DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    }
}

AesGcmDecryptBytes(b64Iv, b64CtAndTag, keyBuf, &ok := "") {
    ok := false
    if (!(keyBuf is Buffer) || keyBuf.Size != 32)
        return ""
    ivBuf := _Base64ToBytes(b64Iv)
    if (!(ivBuf is Buffer) || ivBuf.Size != 12)
        return ""
    ctAndTag := _Base64ToBytes(b64CtAndTag)
    if (!(ctAndTag is Buffer) || ctAndTag.Size < 16)
        return ""

    ctLen := ctAndTag.Size - 16
    ctBuf := Buffer(Max(1, ctLen), 0)
    if (ctLen > 0)
        DllCall("ntdll\RtlMoveMemory", "Ptr", ctBuf.Ptr, "Ptr", ctAndTag.Ptr, "UPtr", ctLen)
    tagBuf := Buffer(16, 0)
    DllCall("ntdll\RtlMoveMemory", "Ptr", tagBuf.Ptr, "Ptr", ctAndTag.Ptr + ctLen, "UPtr", 16)

    hAlg := 0
    hKey := 0
    try {
        if (DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", "AES", "Ptr", 0, "UInt", 0, "Int") != 0)
            return ""
        modeName := "ChainingModeGCM"
        if (DllCall("bcrypt\BCryptSetProperty", "Ptr", hAlg, "Str", "ChainingMode", "Str", modeName, "UInt", (StrLen(modeName) + 1) * 2, "UInt", 0, "Int") != 0)
            return ""

        objLenBuf := Buffer(4, 0)
        cbObj := 0
        if (DllCall("bcrypt\BCryptGetProperty", "Ptr", hAlg, "Str", "ObjectLength", "Ptr", objLenBuf, "UInt", 4, "UInt*", &cbObj, "UInt", 0, "Int") != 0)
            return ""
        objLen := NumGet(objLenBuf, 0, "UInt")
        keyObjBuf := Buffer(Max(1, objLen), 0)

        if (DllCall("bcrypt\BCryptGenerateSymmetricKey", "Ptr", hAlg, "Ptr*", &hKey, "Ptr", keyObjBuf, "UInt", objLen, "Ptr", keyBuf, "UInt", 32, "UInt", 0, "Int") != 0)
            return ""

        ptBuf := Buffer(Max(1, ctLen), 0)
        authInfo := _BuildGcmAuthInfo(ivBuf, tagBuf)
        cbResult := 0
        st := DllCall("bcrypt\BCryptDecrypt",
            "Ptr", hKey,
            "Ptr", ctBuf.Ptr, "UInt", ctLen,
            "Ptr", authInfo.Ptr,
            "Ptr", 0, "UInt", 0,
            "Ptr", ptBuf.Ptr, "UInt", ctLen,
            "UInt*", &cbResult,
            "UInt", 0, "Int")
        if (st != 0)
            return ""

        ok := true
        return (cbResult > 0) ? StrGet(ptBuf, cbResult, "UTF-8") : ""
    } catch {
        return ""
    } finally {
        if (hKey)
            try DllCall("bcrypt\BCryptDestroyKey", "Ptr", hKey)
        if (hAlg)
            try DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    }
}

EncryptRelayPayload(plainJson, pairingCode, secretSalt := "", ivOverride := "") {
    keyBuf := DeriveAesGcmKey32(pairingCode, secretSalt)
    enc := AesGcmEncryptBytes(plainJson, keyBuf, ivOverride)
    if (!IsObject(enc))
        return ""
    return "PSGCM1|" enc.iv "|" enc.ct
}

DecryptRelayPayload(envelope, pairingCode, secretSalt := "", &ok := "") {
    ok := false
    raw := (Type(envelope) == "Buffer") ? StrGet(envelope, "UTF-8") : String(envelope)
    raw := StrReplace(raw, "\/", "/")
    if (!RegExMatch(raw, "PSGCM1\|([A-Za-z0-9+/=]+)\|([A-Za-z0-9+/=]+)", &m))
        return ""
    keyBuf := DeriveAesGcmKey32(pairingCode, secretSalt)
    return AesGcmDecryptBytes(m[1], m[2], keyBuf, &ok)
}

class RelayReplayGuard {
    maxSkewSec := 300
    maxSenders := 64
    _lastSeq := ""
    _order := ""

    __New(maxSkewSec := 300, maxSenders := 64) {
        this.maxSkewSec := Max(5, Integer(maxSkewSec))
        this.maxSenders := Max(4, Integer(maxSenders))
        this._lastSeq := Map()
        this._order := []
    }

    Reset() {
        this._lastSeq := Map()
        this._order := []
    }

    Accept(senderKey, seq, ts := 0, nowEpochSec := "") {
        sKey := Trim(String(senderKey))
        if (sKey = "")
            sKey := "default"
        if (!IsInteger(seq))
            return false
        seqNum := Integer(seq)
        if (seqNum <= 0)
            return false

        if (this._lastSeq.Has(sKey) && seqNum <= this._lastSeq[sKey])
            return false

        if (ts != "" && IsInteger(ts)) {
            tsNum := Integer(ts)
            if (tsNum >= 1000000000) {
                nowSec := (nowEpochSec != "" && IsInteger(nowEpochSec)) ? Integer(nowEpochSec) : GetCurrentUnixEpochSec()
                if (Abs(nowSec - tsNum) > this.maxSkewSec)
                    return false
            }
        }

        if (!this._lastSeq.Has(sKey)) {
            while (this._lastSeq.Count >= this.maxSenders && this._order.Length > 0) {
                evictKey := this._order.RemoveAt(1)
                if (this._lastSeq.Has(evictKey))
                    this._lastSeq.Delete(evictKey)
            }
            this._order.Push(sKey)
        }
        this._lastSeq[sKey] := seqNum
        return true
    }
}
