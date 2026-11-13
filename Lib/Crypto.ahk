; ==============================================================================
; Module: Crypto.ahk
; Description: SHA-256 + Base64 cryptography engine for OBS WebSocket v5 auth
; ==============================================================================

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

