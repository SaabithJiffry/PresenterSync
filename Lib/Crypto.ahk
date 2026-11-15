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

    hAlg := 0
    hHash := 0
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", algId, "Ptr", 0, "UInt", 0)
    DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0)
    if (size > 0)
        DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", size, "UInt", 0)

    hashBuf := Buffer(hashLen, 0)
    DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hashBuf, "UInt", hashLen, "UInt", 0)

    if (hHash)
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
    if (hAlg)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)

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

HashSHA256_Hex(stringToHash) {
    hashBuf := _HashCryptRaw("SHA256", 32, stringToHash)
    hex := ""
    Loop 32
        hex .= Format("{:02x}", NumGet(hashBuf, A_Index - 1, "UChar"))
    return hex
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
