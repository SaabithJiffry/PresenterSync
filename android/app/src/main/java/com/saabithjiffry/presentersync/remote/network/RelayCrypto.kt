package com.saabithjiffry.presentersync.remote.network

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.abs

data class RelayPacket(
    val src: String,
    val cmd: String,
    val data: String,
    val auth: String
)

data class RelayTelemetryState(
    val isMuted: Boolean? = null,
    val isStandby: Boolean = false,
    val recState: Int = 0,
    val recSeconds: Int = 0,
    val streamDropWarn: Boolean = false,
    val voiceWhileMuted: Boolean = false,
    val osMicMutedDrift: Boolean = false,
    val lowDiskWarnLevel: Int = 0,
    val lowDiskMb: Int = -1,
    val deadMicWarn: Boolean = false,
    val slideIndex: Int = 0,
    val slideTotal: Int = 0,
    val slideTitle: String = "",
    val timerState: String = "stopped",
    val timerRemainingSec: Int = 600,
    val timerPresetSec: Int = 600,
    val activeScene: String = "Scene",
    val scenes: List<String> = emptyList()
)

data class ParsedRelayEnvelope(
    val ok: Boolean,
    val encrypted: Boolean,
    val authError: Boolean = false,
    val replayRejected: Boolean = false,
    val clockSkewRejected: Boolean = false,
    val error: String = "",
    val src: String = "",
    val cmd: String = "",
    val data: String = "",
    val auth: String = "",
    val seq: Long = 0L,
    val ts: Long = 0L,
    val sid: String = "",
    val telemetry: RelayTelemetryState? = null
)

class RelayReplayGuard(
    private val maxSkewSec: Long = 300L,
    private val maxSenders: Int = 64
) {
    private val lastSeqBySender = LinkedHashMap<String, Long>()
    @Volatile
    var lastRejectReason: String = ""
        private set

    @Synchronized
    fun reset() {
        lastSeqBySender.clear()
        lastRejectReason = ""
    }

    @Synchronized
    fun accept(
        senderKey: String,
        seq: Long,
        ts: Long = 0L,
        nowEpochSec: Long = System.currentTimeMillis() / 1000L
    ): Boolean {
        lastRejectReason = ""
        if (seq <= 0L) {
            lastRejectReason = "bad_seq"
            return false
        }
        val key = senderKey.trim().ifEmpty { "default" }
        val prev = lastSeqBySender[key]
        if (prev != null && seq <= prev) {
            lastRejectReason = "replay_seq"
            return false
        }
        if (ts >= 1_000_000_000L && abs(nowEpochSec - ts) > maxSkewSec) {
            lastRejectReason = "clock_skew"
            return false
        }
        if (prev == null && lastSeqBySender.size >= maxSenders) {
            val oldest = lastSeqBySender.keys.firstOrNull()
            if (oldest != null) lastSeqBySender.remove(oldest)
        }
        lastSeqBySender[key] = seq
        return true
    }
}

object RelayCrypto {
    const val DEFAULT_RELAY_BASE_URL = "https://ntfy.sh"
    const val GCM_ENVELOPE_PREFIX = "PSGCM1"
    const val GCM_V2_ENVELOPE_PREFIX = "PSGCM2"
    const val PBKDF2_ITERATIONS = 10_000
    const val GCM_IV_BYTES = 12
    const val GCM_TAG_BITS = 128

    private val secureRandom = SecureRandom()
    private val nonAlnumRegex = Regex("[^a-zA-Z0-9]")
    private val relayPacketRegex = Regex("""PSRELAY\|([^|"]*)\|([^|"]*)\|([^|"]*)\|([^|"\r\n\s}]*)""")
    private val gcmEnvelopeRegex = Regex("""PSGCM1\|([A-Za-z0-9+/=]+)\|([A-Za-z0-9+/=]+)""")
    private val gcmV2EnvelopeRegex = Regex("""PSGCM2\|([A-Za-z0-9+/=]+)\|([A-Za-z0-9+/=]+)""")
    private val strictBase64Regex = Regex("""^[A-Za-z0-9+/=]+$""")
    private val validHttpBaseRegex = Regex("""^https?://[^\s/?#]+.*$""", RegexOption.IGNORE_CASE)
    private val v2KeyCache = object : LinkedHashMap<String, ByteArray>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?): Boolean = size > 32
    }

    fun sha256Base64(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray(StandardCharsets.UTF_8))
        return Base64.getEncoder().encodeToString(digest)
    }

    fun computeObsAuthResponse(password: String, salt: String, challenge: String): String {
        val secret = sha256Base64(password + salt)
        return sha256Base64(secret + challenge)
    }

    fun normalizeRelayBaseUrl(rawUrl: String?): String {
        var clean = rawUrl?.trim().orEmpty()
        if (clean.isEmpty()) return DEFAULT_RELAY_BASE_URL
        clean = when {
            clean.startsWith("wss://", ignoreCase = true) -> "https://" + clean.substring(6)
            clean.startsWith("ws://", ignoreCase = true) -> "http://" + clean.substring(5)
            clean.startsWith("https://", ignoreCase = true) || clean.startsWith("http://", ignoreCase = true) -> clean
            else -> "https://$clean"
        }
        clean = clean.trimEnd('/')
        if (clean.any { it.isWhitespace() } || !validHttpBaseRegex.matches(clean)) {
            return DEFAULT_RELAY_BASE_URL
        }
        return clean
    }

    fun buildRelayWsUrl(baseUrl: String?, topic: String): String {
        val cleanTopic = topic.trim().trim('/')
        if (cleanTopic.isEmpty()) return ""
        val httpBase = normalizeRelayBaseUrl(baseUrl)
        val wsBase = when {
            httpBase.startsWith("https://", ignoreCase = true) -> "wss://" + httpBase.substring(8)
            httpBase.startsWith("http://", ignoreCase = true) -> "ws://" + httpBase.substring(7)
            else -> "wss://ntfy.sh"
        }
        return "$wsBase/$cleanTopic/ws"
    }

    fun buildRelayPublishUrl(baseUrl: String?, topic: String): String {
        val cleanTopic = topic.trim().trim('/')
        if (cleanTopic.isEmpty()) return ""
        return "${normalizeRelayBaseUrl(baseUrl)}/$cleanTopic"
    }

    fun generateSessionId(): String {
        val bytes = ByteArray(4)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    fun deriveAesGcmKey32(pairingCode: String, secretSalt: String = ""): ByteArray {
        val material = "PS_GCM_V1|${pairingCode.trim()}|${secretSalt.trim()}"
        return MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(StandardCharsets.UTF_8))
    }

    fun deriveAesGcmKey32V2(
        pairingCode: String,
        secretSalt: String = "",
        iterations: Int = PBKDF2_ITERATIONS
    ): ByteArray {
        val cleanCode = pairingCode.trim()
        val cleanSalt = secretSalt.trim()
        val safeIter = iterations.coerceAtLeast(1000)
        val cacheKey = "$safeIter|$cleanCode|$cleanSalt"
        synchronized(v2KeyCache) {
            v2KeyCache[cacheKey]?.let { return it.copyOf() }
        }
        val pwChars = "$cleanCode|$cleanSalt".toCharArray()
        val saltBytes = "PS_GCM_V2_SALT|$cleanCode".toByteArray(StandardCharsets.UTF_8)
        val derived = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec(pwChars, saltBytes, safeIter, 256))
            .encoded
        synchronized(v2KeyCache) {
            v2KeyCache[cacheKey] = derived.copyOf()
        }
        return derived
    }

    fun aesGcmEncryptBytes(
        plaintext: String,
        key32: ByteArray,
        ivOverride: ByteArray? = null,
        aad: String = ""
    ): Pair<String, String> {
        require(key32.size == 32) { "AES-256-GCM key must be exactly 32 bytes" }
        val iv = if (ivOverride != null) {
            require(ivOverride.size == GCM_IV_BYTES) { "GCM IV must be exactly 12 bytes" }
            ivOverride.copyOf()
        } else {
            ByteArray(GCM_IV_BYTES).also { secureRandom.nextBytes(it) }
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key32, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
        if (aad.isNotEmpty()) {
            cipher.updateAAD(aad.toByteArray(StandardCharsets.UTF_8))
        }
        val ctAndTag = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
        return Base64.getEncoder().encodeToString(iv) to Base64.getEncoder().encodeToString(ctAndTag)
    }

    fun aesGcmDecryptBytes(
        b64Iv: String,
        b64CtAndTag: String,
        key32: ByteArray,
        aad: String = ""
    ): String? {
        if (key32.size != 32) return null
        val ivClean = b64Iv.trim()
        val ctClean = b64CtAndTag.trim()
        if (!strictBase64Regex.matches(ivClean) || !strictBase64Regex.matches(ctClean)) return null
        return try {
            val iv = Base64.getDecoder().decode(ivClean)
            val ctAndTag = Base64.getDecoder().decode(ctClean)
            if (iv.size != GCM_IV_BYTES || ctAndTag.size < 16) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key32, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
            if (aad.isNotEmpty()) {
                cipher.updateAAD(aad.toByteArray(StandardCharsets.UTF_8))
            }
            val plain = cipher.doFinal(ctAndTag)
            String(plain, StandardCharsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    fun encryptRelayPayloadV1(
        plainJson: String,
        pairingCode: String,
        secretSalt: String = "",
        ivOverride: ByteArray? = null
    ): String {
        val key32 = deriveAesGcmKey32(pairingCode, secretSalt)
        val (b64Iv, b64CtAndTag) = aesGcmEncryptBytes(plainJson, key32, ivOverride)
        return "$GCM_ENVELOPE_PREFIX|$b64Iv|$b64CtAndTag"
    }

    fun encryptRelayPayload(
        plainJson: String,
        pairingCode: String,
        secretSalt: String = "",
        ivOverride: ByteArray? = null,
        envelopeVersion: Int = 2
    ): String {
        if (envelopeVersion == 1) {
            return encryptRelayPayloadV1(plainJson, pairingCode, secretSalt, ivOverride)
        }
        val cleanCode = pairingCode.trim()
        val key32 = deriveAesGcmKey32V2(cleanCode, secretSalt)
        val aad = "$GCM_V2_ENVELOPE_PREFIX|$cleanCode"
        val (b64Iv, b64CtAndTag) = aesGcmEncryptBytes(plainJson, key32, ivOverride, aad)
        return "$GCM_V2_ENVELOPE_PREFIX|$b64Iv|$b64CtAndTag"
    }

    fun decryptRelayPayload(
        envelope: String,
        pairingCode: String,
        secretSalt: String = ""
    ): String? {
        val normalized = envelope.replace("\\/", "/")
        val matchV2 = gcmV2EnvelopeRegex.find(normalized)
        if (matchV2 != null) {
            val cleanCode = pairingCode.trim()
            val key32 = deriveAesGcmKey32V2(cleanCode, secretSalt)
            return aesGcmDecryptBytes(matchV2.groupValues[1], matchV2.groupValues[2], key32, "$GCM_V2_ENVELOPE_PREFIX|$cleanCode")
        }
        val match = gcmEnvelopeRegex.find(normalized) ?: return null
        val key32 = deriveAesGcmKey32(pairingCode, secretSalt)
        return aesGcmDecryptBytes(match.groupValues[1], match.groupValues[2], key32)
    }

    fun formatEncryptedRelayPacket(
        src: String,
        cmd: String,
        data: String,
        pairingCode: String,
        password: String = "",
        seq: Long,
        ts: Long = System.currentTimeMillis() / 1000L,
        sid: String = "",
        ivOverride: ByteArray? = null
    ): String {
        val cleanCode = pairingCode.trim().uppercase()
        val auth = getInternetRelayAuthToken(cleanCode, password)
        val obj = JSONObject()
            .put("v", 1)
            .put("src", src)
            .put("cmd", cmd)
            .put("data", data)
            .put("seq", seq)
            .put("ts", ts)
            .put("sid", sid)
            .put("auth", auth)
        return encryptRelayPayload(obj.toString(), cleanCode, password, ivOverride)
    }

    fun parseDirStatePayload(
        data: String,
        fallback: RelayTelemetryState = RelayTelemetryState()
    ): RelayTelemetryState? {
        val parts = data.split(";")
        if (parts.size < 5) return null
        val standby = parts[0] == "1" || parts[0].equals("true", ignoreCase = true)
        val recSt = parts[1].toIntOrNull() ?: fallback.recState
        val tState = parts[2].ifBlank { "stopped" }
        val tRem = parts[3].toIntOrNull() ?: fallback.timerRemainingSec
        val tPre = (parts[4].toIntOrNull() ?: fallback.timerPresetSec).coerceAtLeast(60)
        val scene = parts.getOrNull(5)?.takeIf { it.isNotBlank() } ?: fallback.activeScene
        val recSec = parts.getOrNull(6)?.toIntOrNull()?.coerceAtLeast(0) ?: fallback.recSeconds
        val streamDrop = parts.getOrNull(7)?.let { it == "1" || it.equals("true", ignoreCase = true) }
            ?: fallback.streamDropWarn
        val voiceMuted = parts.getOrNull(8)?.let { it == "1" || it.equals("true", ignoreCase = true) }
            ?: fallback.voiceWhileMuted
        val scenes = parts.getOrNull(9)
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
        return RelayTelemetryState(
            isMuted = fallback.isMuted,
            isStandby = standby,
            recState = recSt,
            recSeconds = recSec,
            streamDropWarn = streamDrop,
            voiceWhileMuted = voiceMuted,
            timerState = tState,
            timerRemainingSec = tRem,
            timerPresetSec = tPre,
            activeScene = scene,
            scenes = scenes
        )
    }

    fun parseRelayEnvelope(
        rawMsg: String,
        pairingCode: String,
        password: String = "",
        replayGuard: RelayReplayGuard? = null,
        allowLegacy: Boolean = false,
        nowEpochSec: Long = System.currentTimeMillis() / 1000L
    ): ParsedRelayEnvelope? {
        if (rawMsg.contains("$GCM_V2_ENVELOPE_PREFIX|") || rawMsg.contains("$GCM_ENVELOPE_PREFIX|")) {
            val cleanCode = pairingCode.trim().uppercase()
            val plain = decryptRelayPayload(rawMsg, cleanCode, password)
                ?: return ParsedRelayEnvelope(
                    ok = false,
                    encrypted = true,
                    authError = true,
                    error = "decrypt_failed"
                )
            val obj = try {
                JSONObject(plain)
            } catch (_: Exception) {
                return ParsedRelayEnvelope(
                    ok = false,
                    encrypted = true,
                    authError = true,
                    error = "malformed_json"
                )
            }
            val src = obj.optString("src", "")
            val cmd = obj.optString("cmd", "")
            val data = obj.optString("data", "")
            val auth = obj.optString("auth", "")
            val sid = obj.optString("sid", "")
            val seq = obj.optLong("seq", 0L)
            val ts = obj.optLong("ts", 0L)
            if (src.isEmpty() || cmd.isEmpty()) {
                return ParsedRelayEnvelope(
                    ok = false,
                    encrypted = true,
                    authError = true,
                    error = "malformed_json"
                )
            }
            if (replayGuard != null) {
                val senderKey = if (sid.isNotEmpty()) "$src:$sid" else src
                if (!replayGuard.accept(senderKey, seq, ts, nowEpochSec)) {
                    val isSkew = replayGuard.lastRejectReason == "clock_skew"
                    return ParsedRelayEnvelope(
                        ok = false,
                        encrypted = true,
                        replayRejected = !isSkew,
                        clockSkewRejected = isSkew,
                        error = if (isSkew) "clock_skew" else "replay_rejected",
                        src = src,
                        cmd = cmd,
                        seq = seq
                    )
                }
            }
            val hasTelemetry = obj.has("recSeconds") || obj.has("streamDropWarn") ||
                obj.has("voiceWhileMuted") || obj.has("scenes") || obj.has("activeScene") ||
                obj.has("isStandby") || obj.has("recState") ||
                obj.has("osMicMutedDrift") || obj.has("slideIndex")
            val telemetry = if (hasTelemetry) {
                val scenesList = mutableListOf<String>()
                val arr: JSONArray? = obj.optJSONArray("scenes")
                if (arr != null) {
                    for (i in 0 until arr.length()) {
                        val s = arr.optString(i, "").trim()
                        if (s.isNotEmpty()) scenesList.add(s)
                    }
                }
                RelayTelemetryState(
                    isMuted = if (obj.has("isMuted")) obj.optBoolean("isMuted", false) else null,
                    isStandby = obj.optBoolean("isStandby", false),
                    recState = obj.optInt("recState", 0),
                    recSeconds = obj.optInt("recSeconds", 0).coerceAtLeast(0),
                    streamDropWarn = obj.optBoolean("streamDropWarn", false),
                    voiceWhileMuted = obj.optBoolean("voiceWhileMuted", false),
                    osMicMutedDrift = obj.optBoolean("osMicMutedDrift", false),
                    lowDiskWarnLevel = obj.optInt("lowDiskWarnLevel", 0),
                    lowDiskMb = obj.optInt("lowDiskMb", -1),
                    deadMicWarn = obj.optBoolean("deadMicWarn", false),
                    slideIndex = obj.optInt("slideIndex", 0).coerceAtLeast(0),
                    slideTotal = obj.optInt("slideTotal", 0).coerceAtLeast(0),
                    slideTitle = obj.optString("slideTitle", ""),
                    timerState = obj.optString("timerState", "stopped").ifBlank { "stopped" },
                    timerRemainingSec = obj.optInt("timerRemainingSec", 600),
                    timerPresetSec = obj.optInt("timerPresetSec", 600).coerceAtLeast(60),
                    activeScene = obj.optString("activeScene", "Scene").ifBlank { "Scene" },
                    scenes = scenesList
                )
            } else if (cmd == "dir_state") {
                parseDirStatePayload(data)
            } else {
                null
            }
            return ParsedRelayEnvelope(
                ok = true,
                encrypted = true,
                src = src,
                cmd = cmd,
                data = data,
                auth = auth,
                seq = seq,
                ts = ts,
                sid = sid,
                telemetry = telemetry
            )
        }

        if (!allowLegacy) return null
        val pkt = parseRelayPacket(rawMsg) ?: return null
        return ParsedRelayEnvelope(
            ok = true,
            encrypted = false,
            src = pkt.src,
            cmd = pkt.cmd,
            data = pkt.data,
            auth = pkt.auth,
            telemetry = if (pkt.cmd == "dir_state") parseDirStatePayload(pkt.data) else null
        )
    }

    fun getInternetRelayTopic(pairingCode: String): String {
        val clean = pairingCode.trim().uppercase()
        if (clean.isEmpty()) return ""
        val hash = sha256Base64("PresenterSync_RelayTopic_v1|$clean")
        val safe = nonAlnumRegex.replace(hash, "")
        return "psync_" + safe.take(28)
    }

    fun getInternetRelayAuthToken(pairingCode: String, password: String = ""): String {
        val clean = pairingCode.trim().uppercase()
        val hash = sha256Base64("PresenterSync_RelayAuth_v1|$clean|$password")
        return nonAlnumRegex.replace(hash, "")
    }

    fun formatRelayPacket(src: String, cmd: String, data: String, authToken: String): String {
        return "PSRELAY|$src|$cmd|$data|$authToken"
    }

    fun parseRelayPacket(rawMsg: String): RelayPacket? {
        val match = relayPacketRegex.find(rawMsg) ?: return null
        return RelayPacket(
            src = match.groupValues[1],
            cmd = match.groupValues[2],
            data = match.groupValues[3],
            auth = match.groupValues[4]
        )
    }
}
