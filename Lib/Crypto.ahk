; ==============================================================================
; Module: Crypto.ahk
; Description: SHA-256 + Base64 cryptography engine for OBS WebSocket v5 auth
; ==============================================================================

#DllLoad bcrypt.dll
#DllLoad crypt32.dll

HashSHA256_Base64(stringToHash) {
    size := StrPut(stringToHash, "UTF-8") - 1
    buf := Buffer(Max(1, size), 0)
    if (size > 0)
        StrPut(stringToHash, buf, "UTF-8")

    hAlg := 0
    hHash := 0
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "Str", "SHA256", "Ptr", 0, "UInt", 0)
    DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0)
    if (size > 0)
        DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", size, "UInt", 0)

    hashBuf := Buffer(32, 0)
    DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hashBuf, "UInt", 32, "UInt", 0)

    if (hHash)
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
    if (hAlg)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)

    b64Len := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", hashBuf, "UInt", 32, "UInt", 0x40000001, "Ptr", 0, "UInt*", &b64Len)
    b64Buf := Buffer(b64Len * 2, 0)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", hashBuf, "UInt", 32, "UInt", 0x40000001, "Ptr", b64Buf, "UInt*", &b64Len)

    return StrGet(b64Buf)
}
