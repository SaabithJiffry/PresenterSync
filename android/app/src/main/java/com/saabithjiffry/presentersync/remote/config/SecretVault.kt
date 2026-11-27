package com.saabithjiffry.presentersync.remote.config

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

interface SecretCipher {
    fun encrypt(plain: String): String
    fun decrypt(stored: String): String?
}

/**
 * Hardware/OS-backed AndroidKeyStore AES-256-GCM cipher on Android devices (API 26+),
 * transparently falling back to an ephemeral/local AES-256-GCM cipher on host JVMs
 * (e.g., plain JUnit unit tests without an AndroidKeyStore JCE provider).
 */
class AndroidKeyStoreSecretCipher(
    private val keyAlias: String = DEFAULT_KEY_ALIAS
) : SecretCipher {

    override fun encrypt(plain: String): String {
        if (plain.isEmpty()) return ""
        val key = resolveOrCreateKey()
        val cipher = Cipher.getInstance(CIPHER_TRANSFORM)
        return if (hasAndroidKeyStoreProvider) {
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
            encodeEnvelope(iv, ct)
        } else {
            val iv = ByteArray(GCM_IV_LEN).also { rng.nextBytes(it) }
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
            val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
            encodeEnvelope(iv, ct)
        }
    }

    override fun decrypt(stored: String): String? {
        if (!stored.startsWith(PREFIX)) return null
        val parts = stored.split("|", limit = 3)
        if (parts.size != 3) return null
        return try {
            val iv = Base64.getDecoder().decode(parts[1])
            val ct = Base64.getDecoder().decode(parts[2])
            if (iv.size != GCM_IV_LEN || ct.isEmpty()) return null
            val key = resolveExistingKey() ?: return null
            val cipher = Cipher.getInstance(CIPHER_TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(ct), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun encodeEnvelope(iv: ByteArray, ct: ByteArray): String {
        val enc = Base64.getEncoder()
        return "$PREFIX${enc.encodeToString(iv)}|${enc.encodeToString(ct)}"
    }

    private fun resolveExistingKey(): SecretKey? {
        if (!hasAndroidKeyStoreProvider) return jvmTestFallbackKey(keyAlias)
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = ks.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry ?: return null
        return entry.secretKey
    }

    private fun resolveOrCreateKey(): SecretKey {
        if (!hasAndroidKeyStoreProvider) return jvmTestFallbackKey(keyAlias)
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = ks.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        kg.init(spec)
        return kg.generateKey()
    }

    companion object {
        const val PREFIX = "KSGCM1|"
        const val DEFAULT_KEY_ALIAS = "presentersync_remote_secrets_v1"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val CIPHER_TRANSFORM = "AES/GCM/NoPadding"
        private const val GCM_IV_LEN = 12
        private const val GCM_TAG_BITS = 128
        private val rng = SecureRandom()

        private val hasAndroidKeyStoreProvider: Boolean by lazy {
            try {
                KeyStore.getInstance(ANDROID_KEYSTORE)
                true
            } catch (_: Exception) {
                false
            }
        }

        private fun jvmTestFallbackKey(alias: String): SecretKey {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("PS_JVM_FALLBACK_KEY|$alias".toByteArray(Charsets.UTF_8))
            return SecretKeySpec(digest, "AES")
        }
    }
}

/**
 * Vault storing sensitive Remote secrets (`obsPassword`, `sessionToken`,
 * `sessionPairingCode`, `internetPairingCode`, `savedProfilesJson`) encrypted
 * in `presentersync_remote_vault`.
 *
 * Guardrail #2 soft-fallback: any corrupted or un-decryptable secret fails softly
 * to `""` and clears the stale ciphertext rather than throwing on startup.
 */
class SecretVault(
    private val vaultPrefs: SharedPreferences,
    private val legacyPrefs: SharedPreferences? = null,
    private val cipher: SecretCipher = AndroidKeyStoreSecretCipher()
) {
    constructor(context: Context, legacyPrefs: SharedPreferences? = null) : this(
        vaultPrefs = context.applicationContext.getSharedPreferences(VAULT_PREFS_NAME, Context.MODE_PRIVATE),
        legacyPrefs = legacyPrefs
    )

    var lastFallbackWarning: String = ""
        private set

    fun getSecret(key: String): String {
        val stored = vaultPrefs.getString(key, null)
        if (stored == null) {
            val legacy = legacyPrefs?.getString(key, null)
            if (!legacy.isNullOrEmpty()) {
                putSecret(key, legacy)
                return legacy
            }
            return ""
        }
        if (stored.isEmpty()) return ""
        if (stored.startsWith(AndroidKeyStoreSecretCipher.PREFIX)) {
            val dec = cipher.decrypt(stored)
            if (dec == null) {
                lastFallbackWarning = "Could not decrypt stored $key; cleared safely."
                runCatching { Log.w(TAG, lastFallbackWarning) }
                vaultPrefs.edit().remove(key).apply()
                return ""
            }
            return dec
        }
        // Upgrade any plaintext value that ended up inside vaultPrefs.
        putSecret(key, stored)
        return stored
    }

    fun putSecret(key: String, value: String) {
        if (value.isEmpty()) {
            vaultPrefs.edit().remove(key).apply()
        } else {
            val encrypted = try {
                cipher.encrypt(value)
            } catch (ex: Exception) {
                lastFallbackWarning = "Failed encrypting $key: ${ex.message}"
                runCatching { Log.w(TAG, lastFallbackWarning) }
                ""
            }
            if (encrypted.isEmpty()) {
                vaultPrefs.edit().remove(key).apply()
            } else {
                vaultPrefs.edit().putString(key, encrypted).apply()
            }
        }
        if (legacyPrefs != null && legacyPrefs !== vaultPrefs && legacyPrefs.contains(key)) {
            legacyPrefs.edit().remove(key).apply()
        }
    }

    companion object {
        private const val TAG = "SecretVault"
        const val VAULT_PREFS_NAME = "presentersync_remote_vault"
        val SECRET_KEYS = listOf(
            "obsPassword",
            "sessionToken",
            "sessionPairingCode",
            "internetPairingCode",
            "kioskPin",
            "savedProfilesJson"
        )
    }
}
