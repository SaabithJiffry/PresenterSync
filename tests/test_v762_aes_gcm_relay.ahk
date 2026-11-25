; ==============================================================================
; Test Suite: test_v762_aes_gcm_relay.ahk
; Description: Automated verification of v7.6.2 AES-256-GCM WAN Relay crypto,
;              cross-language deterministic vector parity, replay protection,
;              custom RelayBaseUrl normalization/INI persistence & WAN telemetry
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\RemoteBridgeClient.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"
#Include "..\Lib\HudSnakeGame.ahk"

Gdip.Startup()
OnExit((*) => (HudSnake.Stop(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

PassCount := 0
FailCount := 0
Failures := []

AssertTrue(cond, label) {
    global PassCount, FailCount, Failures
    if (cond) {
        PassCount += 1
    } else {
        FailCount += 1
        Failures.Push(label)
        FileAppend("[FAIL] " label "`n", "*")
    }
}

; Watchdog safety
SetTimer(() => (FileAppend("[FAIL] Watchdog timeout (45s)`n", "*"), ExitApp(2)), -45000)

; ------------------------------------------------------------------------------
; 1. Key Derivation (DeriveAesGcmKey32 & DeriveAesGcmKey32V2 PBKDF2-HMAC-SHA256)
; ------------------------------------------------------------------------------
k1 := DeriveAesGcmKey32("PS-TEST-7620", "ObsPass#762")
k2 := DeriveAesGcmKey32("  PS-TEST-7620  ", " ObsPass#762 ")
k3 := DeriveAesGcmKey32("PS-TEST-7620", "DifferentPass")
AssertTrue((k1 is Buffer) && k1.Size == 32, "DeriveAesGcmKey32 returns 32-byte Buffer")
AssertTrue(_BytesToHexLower(k1, 32) == _BytesToHexLower(k2, 32), "DeriveAesGcmKey32 trims whitespace deterministically")
AssertTrue(_BytesToHexLower(k1, 32) != _BytesToHexLower(k3, 32), "DeriveAesGcmKey32 changes key when secretSalt changes")
AssertTrue(_BytesToHexLower(k1, 32) == HashSHA256_Hex("PS_GCM_V1|PS-TEST-7620|ObsPass#762"), "DeriveAesGcmKey32 matches SHA-256('PS_GCM_V1|code|salt')")

kv2 := DeriveAesGcmKey32V2("PS-TEST-7620", "ObsPass#762")
kv2Trim := DeriveAesGcmKey32V2("  PS-TEST-7620 ", " ObsPass#762  ")
AssertTrue((kv2 is Buffer) && kv2.Size == 32, "DeriveAesGcmKey32V2 returns 32-byte Buffer")
AssertTrue(_BytesToHexLower(kv2, 32) == "f211f639406813ffba44cd356a3009476049103dabdec681790bbd8941e77ae5", "DeriveAesGcmKey32V2 PBKDF2-HMAC-SHA256 (10,000 iters) matches shared vector")
AssertTrue(_BytesToHexLower(kv2, 32) == _BytesToHexLower(kv2Trim, 32), "DeriveAesGcmKey32V2 trims whitespace deterministically")

; ------------------------------------------------------------------------------
; 2. Deterministic Cross-Language Test Vectors (PSGCM2 default + PSGCM1 compat)
; ------------------------------------------------------------------------------
vecCode := "PS-TEST-7620"
vecSalt := "ObsPass#762"
vecPlain := '{"v":1,"cmd":"state","isMuted":true,"scenes":["Intro","Slides"]}'
vecIv := Buffer(12, 0)
Loop 12
    NumPut("UChar", A_Index, vecIv, A_Index - 1)
expectedVecEnvV1 := "PSGCM1|AQIDBAUGBwgJCgsM|xm/rr4vlvT59lkdEHjQ+P3tWFW56lxVwSKJdXy8O2FfPGMxM/Dw1yPpLzed7CPasWvSBETWV7hXK0Z+6I0r53ydmSMcV6nLWy/c/7mu8lUk="
expectedVecEnvV2 := "PSGCM2|AQIDBAUGBwgJCgsM|A50jQz/upMirKVGolj9r2QcU7BnA4P3spHJsyqbW5/oVZfmkkl6dbkH5ZDeFvSCz4YxnPCCQ/roAdtcByzVTdVARwZnOOudwdZKIPIaMb1Y="

actualVecEnvV2 := EncryptRelayPayload(vecPlain, vecCode, vecSalt, vecIv)
actualVecEnvV1 := EncryptRelayPayloadV1(vecPlain, vecCode, vecSalt, vecIv)
actualVecEnv := actualVecEnvV1
AssertTrue(actualVecEnvV2 == expectedVecEnvV2, "Deterministic PSGCM2 (PBKDF2+AAD) vector matches shared cross-language envelope")
AssertTrue(actualVecEnvV1 == expectedVecEnvV1, "Deterministic PSGCM1 backward-compat vector matches shared cross-language envelope")

okVec2 := false
decVec2 := DecryptRelayPayload(actualVecEnvV2, vecCode, vecSalt, &okVec2)
AssertTrue(okVec2 && decVec2 == vecPlain, "DecryptRelayPayload decrypts PSGCM2 deterministic vector cleanly")

okWrongAad := true
decWrongAad := DecryptRelayPayload(actualVecEnvV2, "PS-OTHER-CODE", vecSalt, &okWrongAad)
AssertTrue(!okWrongAad && decWrongAad == "", "DecryptRelayPayload rejects PSGCM2 envelope under wrong AAD pairing code")

okVec := false
decVec := DecryptRelayPayload(actualVecEnvV1, vecCode, vecSalt, &okVec)
AssertTrue(okVec && decVec == vecPlain, "DecryptRelayPayload maintains PSGCM1 backward-compat decryption")

okNtfy := false
ntfyWrapped := '{"id":"msg1","event":"message","topic":"psync_test","message":"' actualVecEnvV2 '"}'
decNtfy := DecryptRelayPayload(ntfyWrapped, vecCode, vecSalt, &okNtfy)
AssertTrue(okNtfy && decNtfy == vecPlain, "DecryptRelayPayload extracts and decrypts PSGCM2 envelope wrapped in ntfy JSON")

; ------------------------------------------------------------------------------
; 3. Random CSPRNG IV Roundtrip & UTF-8 Support
; ------------------------------------------------------------------------------
utfPlain := '{"v":1,"cmd":"nudge","data":"Host;Wrap up — 2 min left ✓"}'
rEnv1 := EncryptRelayPayload(utfPlain, vecCode, vecSalt)
rEnv2 := EncryptRelayPayload(utfPlain, vecCode, vecSalt)
AssertTrue(InStr(rEnv1, "PSGCM2|") == 1 && InStr(rEnv2, "PSGCM2|") == 1, "Random-IV encryption defaults to PSGCM2 envelopes")
AssertTrue(rEnv1 != rEnv2, "Random CSPRNG 12B IV produces distinct envelopes for identical plaintext")
okR1 := false, okR2 := false
AssertTrue(DecryptRelayPayload(rEnv1, vecCode, vecSalt, &okR1) == utfPlain && okR1, "Random-IV PSGCM2 envelope 1 decrypts UTF-8 cleanly")
AssertTrue(DecryptRelayPayload(rEnv2, vecCode, vecSalt, &okR2) == utfPlain && okR2, "Random-IV PSGCM2 envelope 2 decrypts UTF-8 cleanly")

; CSPRNG WAN Pairing Code entropy check
pCode1 := GenerateInternetPairingCode()
pCode2 := GenerateInternetPairingCode()
AssertTrue(RegExMatch(pCode1, "^PS-[A-Z0-9]{4}-[A-Z0-9]{4}$") > 0 && pCode1 != pCode2, "GenerateInternetPairingCode generates distinct high-entropy CSPRNG codes")

; ------------------------------------------------------------------------------
; 4. Tampered Ciphertext / Tag / IV / Wrong Key Rejection
; ------------------------------------------------------------------------------
parts := StrSplit(actualVecEnv, "|")
b64Iv := parts[2]
b64Ct := parts[3]
ctRaw := _Base64ToBytes(b64Ct)
AssertTrue((ctRaw is Buffer) && ctRaw.Size > 16, "Decoded ct||tag has ciphertext + 16B tag")

; Flip byte 0 (ciphertext tamper)
ctTamper := Buffer(ctRaw.Size, 0)
DllCall("ntdll\RtlMoveMemory", "Ptr", ctTamper.Ptr, "Ptr", ctRaw.Ptr, "UPtr", ctRaw.Size)
NumPut("UChar", NumGet(ctTamper, 0, "UChar") ^ 0x01, ctTamper, 0)
okTamperCt := true
decTamperCt := DecryptRelayPayload("PSGCM1|" b64Iv "|" _BytesToBase64(ctTamper, ctTamper.Size), vecCode, vecSalt, &okTamperCt)
AssertTrue(!okTamperCt && decTamperCt == "", "Tampered ciphertext byte is rejected")

; Flip last byte (GCM auth tag tamper)
tagTamper := Buffer(ctRaw.Size, 0)
DllCall("ntdll\RtlMoveMemory", "Ptr", tagTamper.Ptr, "Ptr", ctRaw.Ptr, "UPtr", ctRaw.Size)
NumPut("UChar", NumGet(tagTamper, tagTamper.Size - 1, "UChar") ^ 0x80, tagTamper, tagTamper.Size - 1)
okTamperTag := true
decTamperTag := DecryptRelayPayload("PSGCM1|" b64Iv "|" _BytesToBase64(tagTamper, tagTamper.Size), vecCode, vecSalt, &okTamperTag)
AssertTrue(!okTamperTag && decTamperTag == "", "Tampered GCM auth tag byte is rejected")

; Flip IV byte
ivTamper := Buffer(12, 0)
DllCall("ntdll\RtlMoveMemory", "Ptr", ivTamper.Ptr, "Ptr", vecIv.Ptr, "UPtr", 12)
NumPut("UChar", NumGet(ivTamper, 0, "UChar") ^ 0xFF, ivTamper, 0)
okTamperIv := true
decTamperIv := DecryptRelayPayload("PSGCM1|" _BytesToBase64(ivTamper, 12) "|" b64Ct, vecCode, vecSalt, &okTamperIv)
AssertTrue(!okTamperIv && decTamperIv == "", "Tampered IV is rejected")

; Wrong password / salt
okWrongPw := true
decWrongPw := DecryptRelayPayload(actualVecEnv, vecCode, "WrongPass", &okWrongPw)
AssertTrue(!okWrongPw && decWrongPw == "", "Wrong secretSalt/password is rejected")

; ------------------------------------------------------------------------------
; 5. Monotonic Replay Protection, Clock Skew & Plaintext Default Rejection
; ------------------------------------------------------------------------------
guard := RelayReplayGuard(300)
nowTs := 1732210000
AssertTrue(guard.Accept("remote:sessA", 1, nowTs, nowTs), "ReplayGuard accepts initial seq=1")
AssertTrue(!guard.Accept("remote:sessA", 1, nowTs, nowTs) && guard.lastRejectReason == "replay_seq", "ReplayGuard rejects duplicate seq=1 with replay_seq")
AssertTrue(!guard.Accept("remote:sessA", 0, nowTs, nowTs) && guard.lastRejectReason == "bad_seq", "ReplayGuard rejects non-positive seq=0")
AssertTrue(guard.Accept("remote:sessA", 5, nowTs, nowTs), "ReplayGuard accepts higher monotonic seq=5")
AssertTrue(!guard.Accept("remote:sessA", 4, nowTs, nowTs) && guard.lastRejectReason == "replay_seq", "ReplayGuard rejects out-of-order lower seq=4")
AssertTrue(guard.Accept("remote:sessB", 1, nowTs, nowTs), "ReplayGuard tracks distinct sender sessions independently")
AssertTrue(!guard.Accept("remote:sessA", 6, nowTs - 600, nowTs) && guard.lastRejectReason == "clock_skew", "ReplayGuard rejects stale timestamp beyond skew window with clock_skew reason")

; End-to-end encrypted Host relay replay rejection
tmpIni := A_Temp "\ps_test_v762_" A_TickCount ".ini"
if FileExist(tmpIni)
    try FileDelete(tmpIni)

cfgHost := Config(tmpIni)
cfgHost.AudioRoutingMode := 2
cfgHost.RemoteNetworkMode := "Internet"
cfgHost.InternetPairingCode := "PS-V762-9999"
cfgHost.obsPassword := "HostSecret762"
cfgHost.EnableRelayEncryption := true

hostOut := []
stHost := {
    isMuted: false,
    obsConnected: false,
    obsWs: "",
    zoomConnected: false,
    relayConnected: true,
    relayWs: { tag: "ws762" },
    relayMockWs: { sendText: (this, txt) => hostOut.Push(txt) },
    isStandby: true,
    recState: 1,
    recElapsedSec: 187,
    streamDropWarn: true,
    voiceWhileMuted: true,
    osMicMutedDrift: true,
    lowDiskWarnLevel: 1,
    lowDiskMb: 1850,
    deadMicWarn: true,
    slideIndex: 4,
    slideTotal: 22,
    slideTitle: "Architecture Demo",
    timerState: "running",
    timerRemainingSec: 245,
    timerPresetSec: 600,
    currentSceneName: "Main Slides",
    sceneList: ["Intro", "Main Slides", "Webcam Full", "BRB", "Scene5", "Scene6", "Scene7", "Scene8", "Scene9", "Scene10", "Scene11", "Scene12"]
}

; Default AllowLegacyPlaintextRelay=false must reject unencrypted PSRELAY packets
authToken762 := GetInternetRelayAuthToken(cfgHost.InternetPairingCode, cfgHost.obsPassword)
plainToggle := FormatRelayPacket("remote", "toggle_mute", "1", authToken762)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, plainToggle)
AssertTrue(stHost.isMuted == false && cfgHost.AllowLegacyPlaintextRelay == false, "Host rejects unencrypted PSRELAY packet by default (AllowLegacyPlaintextRelay=false)")

remoteSimState := { _relayOutSeq: 0, _relaySessionId: "a1b2c3d4" }
encToggle := FormatEncryptedRelayPacket("remote", "toggle_mute", "1", cfgHost.InternetPairingCode, cfgHost.obsPassword, remoteSimState)
AssertTrue(InStr(encToggle, "PSGCM2|") == 1, "FormatEncryptedRelayPacket defaults to PSGCM2 envelope")

HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encToggle)
AssertTrue(stHost.isMuted == true, "Host accepts encrypted toggle_mute and flips mute state")

; Replay exact same captured envelope -> must be ignored!
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encToggle)
AssertTrue(stHost.isMuted == true, "Host rejects replayed encrypted toggle_mute without flipping mute state")

; Tampered encrypted envelope -> must be ignored!
tParts := StrSplit(encToggle, "|")
tBytes := _Base64ToBytes(tParts[3])
NumPut("UChar", NumGet(tBytes, tBytes.Size - 1, "UChar") ^ 0x01, tBytes, tBytes.Size - 1)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, "PSGCM2|" tParts[2] "|" _BytesToBase64(tBytes, tBytes.Size))
AssertTrue(stHost.isMuted == true, "Host rejects tampered encrypted packet without modifying state")

; Encrypted ppt_next, ppt_prev, slide_start dispatch paths accepted cleanly without crashing
encPptNext := FormatEncryptedRelayPacket("remote", "ppt_next", "1", cfgHost.InternetPairingCode, cfgHost.obsPassword, remoteSimState)
encPptPrev := FormatEncryptedRelayPacket("remote", "ppt_prev", "1", cfgHost.InternetPairingCode, cfgHost.obsPassword, remoteSimState)
encSlideStart := FormatEncryptedRelayPacket("remote", "slide_start", "1", cfgHost.InternetPairingCode, cfgHost.obsPassword, remoteSimState)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encPptNext)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encPptPrev)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encSlideStart)
AssertTrue(stHost.isMuted == true, "Host processes encrypted ppt_next/ppt_prev/slide_start commands cleanly over WAN")

; ------------------------------------------------------------------------------
; 6. Full WAN Telemetry Parity v2 (size <4KB, watchdogs, slide index, clockSkewRejected)
; ------------------------------------------------------------------------------
hostOut := []
stHost.osMicMutedDrift := true
stHost.deadMicWarn := true
encSync := FormatEncryptedRelayPacket("remote", "sync_req", "0", cfgHost.InternetPairingCode, cfgHost.obsPassword, remoteSimState)
HandleHostRelayMessage(cfgHost, stHost, stHost.relayWs, encSync)
AssertTrue(hostOut.Length == 1, "Encrypted sync_req broadcasts 1 atomic encrypted state+telemetry packet")
wirePkt := hostOut[1]
AssertTrue(InStr(wirePkt, "PSGCM2|") == 1, "Host outbound packet is AES-256-GCM PSGCM2 encrypted")
AssertTrue(!InStr(wirePkt, "Main Slides") && !InStr(wirePkt, "voiceWhileMuted"), "Wire payload does not leak plaintext telemetry")
AssertTrue(StrLen(wirePkt) < 4096, "Encrypted 12-scene packet stays strictly under ntfy 4096-byte WS ceiling (len=" StrLen(wirePkt) ")")

plainV2Json := FormatRelayStatePayload(cfgHost, stHost, "state", 1, 1732210000, "h762")
AssertTrue(StrLen(plainV2Json) < 2500 && InStr(plainV2Json, '"v":2') > 0 && !InStr(plainV2Json, "Intro,Main Slides,Webcam Full"), "FormatRelayStatePayload v2 omits duplicate scenes CSV and stays under 2500 bytes")

remGuard := RelayReplayGuard()
parsedTel := ParseRelayEnvelope(wirePkt, cfgHost.InternetPairingCode, cfgHost.obsPassword, remGuard, false)
AssertTrue(IsObject(parsedTel) && parsedTel.ok && parsedTel.encrypted, "Remote decrypts Host PSGCM2 packet")
AssertTrue(parsedTel.src == "host" && parsedTel.cmd == "state" && parsedTel.isMuted == true, "Decrypted envelope preserves src, cmd & isMuted")
AssertTrue(parsedTel.hasTelemetry && parsedTel.recState == 1 && parsedTel.recSeconds == 187, "WAN telemetry parity: recState & recSeconds")
AssertTrue(parsedTel.streamDropWarn == true && parsedTel.voiceWhileMuted == true, "WAN telemetry parity: streamDropWarn & voiceWhileMuted")
AssertTrue(parsedTel.osMicMutedDrift == true && parsedTel.lowDiskWarnLevel == 1 && parsedTel.lowDiskMb == 1850 && parsedTel.deadMicWarn == true, "WAN telemetry parity: watchdog states (osMicMutedDrift, lowDiskWarn, deadMic)")
AssertTrue(parsedTel.slideIndex == 4 && parsedTel.slideTotal == 22 && parsedTel.slideTitle == "Architecture Demo", "WAN telemetry parity: slideIndex, slideTotal & slideTitle")
AssertTrue(parsedTel.isStandby == true && parsedTel.timerState == "running" && parsedTel.timerRemainingSec == 245 && parsedTel.timerPresetSec == 600, "WAN telemetry parity: standby & timer fields")
AssertTrue(parsedTel.activeScene == "Main Slides" && parsedTel.scenes.Length == 12 && parsedTel.scenes[1] == "Intro" && parsedTel.scenes[12] == "Scene12", "WAN telemetry parity: activeScene & full 12 scenes array")

; Replaying same host packet into remote guard must be rejected!
replayedTel := ParseRelayEnvelope(wirePkt, cfgHost.InternetPairingCode, cfgHost.obsPassword, remGuard, false)
AssertTrue(IsObject(replayedTel) && !replayedTel.ok && replayedTel.replayRejected && !replayedTel.clockSkewRejected, "Remote ReplayGuard rejects replayed Host packet without flagging clockSkewRejected")

; Skewed timestamp (>300s) triggers clockSkewRejected flag!
skewGuard := RelayReplayGuard(300)
skewedTel := ParseRelayEnvelope(wirePkt, cfgHost.InternetPairingCode, cfgHost.obsPassword, skewGuard, false, 1732210000 - 1200)
AssertTrue(IsObject(skewedTel) && !skewedTel.ok && !skewedTel.replayRejected && skewedTel.clockSkewRejected, "ParseRelayEnvelope sets clockSkewRejected=true when timestamp skew exceeds 300s")

; Plaintext ParseRelayEnvelope rejected by default, allowed ONLY with explicit allowLegacy=true
plainLegacyPkt := FormatRelayPacket("host", "state", "1", authToken762)
plainDefaultRes := ParseRelayEnvelope(plainLegacyPkt, cfgHost.InternetPairingCode, cfgHost.obsPassword, "", false)
plainOptInRes := ParseRelayEnvelope(plainLegacyPkt, cfgHost.InternetPairingCode, cfgHost.obsPassword, "", true)
AssertTrue(!IsObject(plainDefaultRes) && IsObject(plainOptInRes) && plainOptInRes.ok && !plainOptInRes.encrypted, "ParseRelayEnvelope drops plaintext PSRELAY by default and accepts only when allowLegacy=true")

; Extended legacy dir_state telemetry parity check
legacyDir := _BuildLegacyDirStatePayload(stHost)
parsedLegacyDir := ParseDirStatePayload(legacyDir)
AssertTrue(IsObject(parsedLegacyDir) && parsedLegacyDir.recSeconds == 187 && parsedLegacyDir.streamDropWarn && parsedLegacyDir.voiceWhileMuted && parsedLegacyDir.scenes.Length == 12, "Extended legacy dir_state carries full telemetry fields")

; ------------------------------------------------------------------------------
; 7. Custom RelayBaseUrl Normalization, WS Conversion & INI Persistence
; ------------------------------------------------------------------------------
AssertTrue(NormalizeRelayBaseUrl("") == "https://ntfy.sh", "Empty RelayBaseUrl defaults to https://ntfy.sh")
AssertTrue(NormalizeRelayBaseUrl("https://ntfy.school.edu/") == "https://ntfy.school.edu", "Trailing slash stripped on custom https RelayBaseUrl")
AssertTrue(NormalizeRelayBaseUrl("http://10.0.0.5:8080/") == "http://10.0.0.5:8080", "Self-hosted http RelayBaseUrl preserved")
AssertTrue(NormalizeRelayBaseUrl("ntfy.internal:8443") == "https://ntfy.internal:8443", "Scheme-less RelayBaseUrl defaults to https://")
AssertTrue(NormalizeRelayBaseUrl("wss://ntfy.school.edu/") == "https://ntfy.school.edu", "wss:// normalizes to https:// HTTP base")
AssertTrue(NormalizeRelayBaseUrl("ws://192.168.1.10:2586") == "http://192.168.1.10:2586", "ws:// normalizes to http:// HTTP base")
AssertTrue(NormalizeRelayBaseUrl("bad url with spaces") == "https://ntfy.sh", "Malformed RelayBaseUrl falls back safely to https://ntfy.sh")

AssertTrue(BuildRelayWsUrl("https://ntfy.school.edu/", "psync_abc123") == "wss://ntfy.school.edu/psync_abc123/ws", "BuildRelayWsUrl converts https:// -> wss://")
AssertTrue(BuildRelayWsUrl("http://10.0.0.5:8080/", "psync_abc123") == "ws://10.0.0.5:8080/psync_abc123/ws", "BuildRelayWsUrl converts http:// -> ws://")
AssertTrue(BuildRelayWsUrl("", "psync_abc123") == "wss://ntfy.sh/psync_abc123/ws", "BuildRelayWsUrl defaults to wss://ntfy.sh")

; INI Persistence + ProfileFieldSpecs + ApplyControlCenterSettings
cfgHost.Write("Settings", "RelayBaseUrl", "https://ntfy.campus.org/")
cfgHost.WriteBool("Settings", "EnableRelayEncryption", true)
cfgReload := Config(tmpIni)
AssertTrue(cfgReload.RelayBaseUrl == "https://ntfy.campus.org", "Config.Load persists & normalizes custom RelayBaseUrl from INI")
AssertTrue(cfgReload.EnableRelayEncryption == true, "Config.Load loads EnableRelayEncryption from INI")

hasRelaySpec := false
for _, sp in cfgReload.GetProfileFieldSpecs() {
    if (sp.prop == "RelayBaseUrl")
        hasRelaySpec := true
}
AssertTrue(hasRelaySpec, "GetProfileFieldSpecs includes RelayBaseUrl")

if FileExist(tmpIni)
    try FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    try FileDelete(tmpIni ".bak")

FileAppend(Format("v7.6.2 AES-GCM Relay Audit: PASS={} FAIL={}`n", PassCount, FailCount), "*")
ExitApp(FailCount > 0 ? 1 : 0)
