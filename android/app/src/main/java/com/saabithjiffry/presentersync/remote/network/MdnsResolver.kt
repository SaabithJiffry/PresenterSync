package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.net.wifi.WifiManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

/**
 * Resolves `.local` mDNS hostnames reliably across Android 8-15 ROMs where standard
 * InetAddress.getByName() may fail to query mDNS multicast (224.0.0.251:5353).
 */
class MdnsResolver(private val context: Context? = null) {

    suspend fun resolveHost(host: String, timeoutMs: Int = 1200): String = withContext(Dispatchers.IO) {
        val trimmed = host.trim()
        if (!trimmed.endsWith(".local", ignoreCase = true)) {
            return@withContext trimmed
        }

        val resolvedViaMulticast = queryMdnsARecord(trimmed, timeoutMs)
        if (!resolvedViaMulticast.isNullOrBlank()) {
            return@withContext resolvedViaMulticast
        }

        // Fallback to platform DNS resolver (Android 12+ supports native .local in libc)
        try {
            val addr = InetAddress.getAllByName(trimmed)
                .firstOrNull { it is Inet4Address } ?: InetAddress.getByName(trimmed)
            val ip = addr.hostAddress
            if (!ip.isNullOrBlank()) return@withContext ip
        } catch (_: Exception) {
        }

        trimmed
    }

    internal fun queryMdnsARecord(hostname: String, timeoutMs: Int): String? {
        val wifiMgr = context?.applicationContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val multicastLock = try {
            wifiMgr?.createMulticastLock("PresenterSyncMdnsLock")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            null
        }

        var socket: DatagramSocket? = null
        return try {
            val packetBytes = buildMdnsAQuery(hostname)
            val mdnsGroup = InetAddress.getByName("224.0.0.251")
            socket = DatagramSocket().apply {
                soTimeout = timeoutMs.coerceIn(250, 3000)
                broadcast = true
            }
            socket.send(DatagramPacket(packetBytes, packetBytes.size, mdnsGroup, 5353))

            val deadline = System.currentTimeMillis() + timeoutMs
            val recvBuf = ByteArray(1500)
            while (System.currentTimeMillis() < deadline) {
                val dp = DatagramPacket(recvBuf, recvBuf.size)
                try {
                    socket.receive(dp)
                } catch (_: Exception) {
                    break
                }
                val ip = parseMdnsAResponse(dp.data, dp.length, hostname)
                if (ip != null) return ip
            }
            null
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
            try {
                if (multicastLock?.isHeld == true) multicastLock.release()
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        fun buildMdnsAQuery(hostname: String): ByteArray {
            val out = ByteArrayOutputStream()
            // DNS Header: ID=0, Flags=0, QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
            out.write(byteArrayOf(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0))
            for (label in hostname.trimEnd('.').split('.')) {
                val bytes = label.toByteArray(StandardCharsets.UTF_8)
                out.write(bytes.size and 0x3F)
                out.write(bytes)
            }
            out.write(0) // root terminator
            out.write(byteArrayOf(0, 1)) // QTYPE = A (1)
            out.write(byteArrayOf(0, 1)) // QCLASS = IN (1)
            return out.toByteArray()
        }

        fun parseMdnsAResponse(data: ByteArray, length: Int, expectedHost: String): String? {
            if (length < 12) return null
            val buf = ByteBuffer.wrap(data, 0, length)
            buf.position(4)
            val qdCount = buf.short.toInt() and 0xFFFF
            val anCount = buf.short.toInt() and 0xFFFF
            buf.short // nsCount
            buf.short // arCount

            var offset = 12
            repeat(qdCount) {
                val (_, nextOff) = readDnsName(data, length, offset) ?: return null
                offset = nextOff + 4
                if (offset > length) return null
            }

            val cleanTarget = expectedHost.trimEnd('.').lowercase()
            repeat(anCount) {
                val (rrName, nextOff) = readDnsName(data, length, offset) ?: return null
                if (nextOff + 10 > length) return null
                val type = ((data[nextOff].toInt() and 0xFF) shl 8) or (data[nextOff + 1].toInt() and 0xFF)
                val rdLength = ((data[nextOff + 8].toInt() and 0xFF) shl 8) or (data[nextOff + 9].toInt() and 0xFF)
                val rdataOff = nextOff + 10
                if (rdataOff + rdLength > length) return null
                if (type == 1 && rdLength == 4 && rrName.trimEnd('.').lowercase() == cleanTarget) {
                    return "${data[rdataOff].toInt() and 0xFF}.${data[rdataOff + 1].toInt() and 0xFF}.${data[rdataOff + 2].toInt() and 0xFF}.${data[rdataOff + 3].toInt() and 0xFF}"
                }
                offset = rdataOff + rdLength
            }
            return null
        }

        private fun readDnsName(data: ByteArray, length: Int, startOffset: Int): Pair<String, Int>? {
            val parts = mutableListOf<String>()
            var pos = startOffset
            var endOffset = -1
            var jumps = 0
            while (pos < length && jumps < 16) {
                val len = data[pos].toInt() and 0xFF
                if (len == 0) {
                    if (endOffset == -1) endOffset = pos + 1
                    return parts.joinToString(".") to endOffset
                }
                if ((len and 0xC0) == 0xC0) {
                    if (pos + 1 >= length) return null
                    if (endOffset == -1) endOffset = pos + 2
                    val ptr = ((len and 0x3F) shl 8) or (data[pos + 1].toInt() and 0xFF)
                    pos = ptr
                    jumps++
                } else {
                    pos++
                    if (pos + len > length) return null
                    parts += String(data, pos, len, StandardCharsets.UTF_8)
                    pos += len
                }
            }
            return null
        }
    }
}
