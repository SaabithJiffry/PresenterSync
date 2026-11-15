package com.saabithjiffry.presentersync.remote.network

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64

data class RelayPacket(
    val src: String,
    val cmd: String,
    val data: String,
    val auth: String
)

object RelayCrypto {
    private val nonAlnumRegex = Regex("[^a-zA-Z0-9]")
    private val relayPacketRegex = Regex("""PSRELAY\|([^|"]*)\|([^|"]*)\|([^|"]*)\|([^|"\r\n\s}]*)""")

    fun sha256Base64(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray(StandardCharsets.UTF_8))
        return Base64.getEncoder().encodeToString(digest)
    }

    fun computeObsAuthResponse(password: String, salt: String, challenge: String): String {
        val secret = sha256Base64(password + salt)
        return sha256Base64(secret + challenge)
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
