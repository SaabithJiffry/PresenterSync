package com.saabithjiffry.presentersync.remote.config

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class InMemorySharedPreferences : SharedPreferences {
    val store = LinkedHashMap<String, Any?>()

    override fun getAll(): MutableMap<String, *> = LinkedHashMap(store)

    override fun getString(key: String?, defValue: String?): String? =
        (store[key] as? String) ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        (store[key] as? MutableSet<String>) ?: defValues

    override fun getInt(key: String?, defValue: Int): Int =
        (store[key] as? Int) ?: defValue

    override fun getLong(key: String?, defValue: Long): Long =
        (store[key] as? Long) ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float =
        (store[key] as? Float) ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        (store[key] as? Boolean) ?: defValue

    override fun contains(key: String?): Boolean = store.containsKey(key)

    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = LinkedHashMap<String, Any?>()
        private var clearFirst = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = values?.toMutableSet()
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun remove(key: String?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = REMOVE_SENTINEL
        }

        override fun clear(): SharedPreferences.Editor = apply {
            clearFirst = true
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearFirst) store.clear()
            for ((k, v) in pending) {
                if (v === REMOVE_SENTINEL) store.remove(k) else store[k] = v
            }
        }
    }

    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    private companion object {
        val REMOVE_SENTINEL = Any()
    }
}

private class FakeVaultContext : ContextWrapper(null) {
    val namedPrefs = LinkedHashMap<String, InMemorySharedPreferences>()

    override fun getApplicationContext(): Context = this

    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
        return namedPrefs.getOrPut(name) { InMemorySharedPreferences() }
    }
}

class SecretVaultTest {

    @Test
    fun secretsPersistEncryptedInVaultPrefsWithoutPlaintextLeakage() {
        val ctx = FakeVaultContext()
        val store = RemoteConfigStore(ctx)
        val profile = SavedHostProfile(
            id = "p1",
            name = "Room 101",
            hostAddress = "192.168.1.50",
            bridgePort = 4456,
            hostPort = 4455,
            sessionPairingCode = "918-273",
            internetPairingCode = "PS-ROOM-1010",
            obsPassword = "SuperObsPassword!99",
            networkMode = NetworkMode.LAN,
            targetMicName = "Mic/Aux"
        )
        store.update {
            it.copy(
                obsPassword = "ObsMasterSecret#42",
                sessionToken = "tok_live_abc123",
                sessionPairingCode = "456-789",
                internetPairingCode = "PS-WAN-9999",
                kioskPin = "4826",
                savedProfiles = listOf(profile)
            )
        }

        val prefsMap = ctx.namedPrefs["presentersync_remote_prefs"]!!.all
        val vaultMap = ctx.namedPrefs[SecretVault.VAULT_PREFS_NAME]!!.all

        for (key in SecretVault.SECRET_KEYS) {
            assertFalse("Plaintext prefs must not retain $key", prefsMap.containsKey(key))
            val encVal = vaultMap[key] as? String
            assertTrue("Vault must store KSGCM1 ciphertext for $key", encVal != null && encVal.startsWith("KSGCM1|"))
        }

        val combinedVaultText = vaultMap.values.joinToString("\n")
        assertFalse(combinedVaultText.contains("ObsMasterSecret#42"))
        assertFalse(combinedVaultText.contains("tok_live_abc123"))
        assertFalse(combinedVaultText.contains("456-789"))
        assertFalse(combinedVaultText.contains("PS-WAN-9999"))
        assertFalse(combinedVaultText.contains("4826"))
        assertFalse(combinedVaultText.contains("SuperObsPassword!99"))

        // Reload cleanly into a fresh RemoteConfigStore instance
        val reloaded = RemoteConfigStore(ctx).current
        assertEquals("ObsMasterSecret#42", reloaded.obsPassword)
        assertEquals("tok_live_abc123", reloaded.sessionToken)
        assertEquals("456-789", reloaded.sessionPairingCode)
        assertEquals("PS-WAN-9999", reloaded.internetPairingCode)
        assertEquals("4826", reloaded.kioskPin)
        assertEquals(1, reloaded.savedProfiles.size)
        assertEquals("SuperObsPassword!99", reloaded.savedProfiles[0].obsPassword)
        assertFalse(reloaded.allowLegacyPlaintextRelay)
    }

    @Test
    fun transparentMigrationMovesLegacyPlaintextSecretsOutOfRegularPrefs() {
        val ctx = FakeVaultContext()
        val legacy = ctx.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE)
        legacy.edit()
            .putString("obsPassword", "LegacyObsPw#1")
            .putString("sessionToken", "legacy_tok_77")
            .putString("sessionPairingCode", "111-222")
            .putString("internetPairingCode", "PS-LEG-8888")
            .putBoolean("allowLegacyPlaintextRelay", true)
            .apply()

        val store = RemoteConfigStore(ctx)
        assertEquals("LegacyObsPw#1", store.current.obsPassword)
        assertEquals("legacy_tok_77", store.current.sessionToken)
        assertEquals("111-222", store.current.sessionPairingCode)
        assertEquals("PS-LEG-8888", store.current.internetPairingCode)
        assertTrue(store.current.allowLegacyPlaintextRelay)

        // Legacy plaintext keys removed from unencrypted prefs and vaulted as KSGCM1
        assertFalse(legacy.contains("obsPassword"))
        assertFalse(legacy.contains("sessionToken"))
        assertFalse(legacy.contains("sessionPairingCode"))
        assertFalse(legacy.contains("internetPairingCode"))
        val vault = ctx.namedPrefs[SecretVault.VAULT_PREFS_NAME]!!
        assertTrue(vault.getString("obsPassword", "")!!.startsWith("KSGCM1|"))
    }

    @Test
    fun guardrail2SoftFallbackClearsCorruptOrForeignKeystoreSecretsWithoutCrashing() {
        val ctx = FakeVaultContext()
        val vaultPrefs = ctx.getSharedPreferences(SecretVault.VAULT_PREFS_NAME, Context.MODE_PRIVATE)
        vaultPrefs.edit()
            .putString("obsPassword", "KSGCM1|AAAAAAAAAAAA|CORRUPT_NOT_VALID_CIPHERTEXT")
            .putString("sessionToken", "KSGCM1|AQIDBAUGBwgJCgsM|deadbeef")
            .apply()

        // Must NOT throw; must return "" and remove corrupt entries
        val store = RemoteConfigStore(ctx)
        assertEquals("", store.current.obsPassword)
        assertEquals("", store.current.sessionToken)
        assertNull(vaultPrefs.getString("obsPassword", null))
        assertNull(vaultPrefs.getString("sessionToken", null))
        assertTrue(store.vault.lastFallbackWarning.isNotBlank())

        // Simulated wrong keystore key (cipher.decrypt returns null) also fails softly
        val brokenCipher = object : SecretCipher {
            override fun encrypt(plain: String): String = "KSGCM1|iv|ct"
            override fun decrypt(stored: String): String? = null
        }
        vaultPrefs.edit().putString("internetPairingCode", "KSGCM1|iv|foreign").apply()
        val foreignStore = RemoteConfigStore(ctx, brokenCipher)
        assertEquals("", foreignStore.current.internetPairingCode)
        assertNull(vaultPrefs.getString("internetPairingCode", null))
        assertTrue(foreignStore.vault.lastFallbackWarning.contains("internetPairingCode"))
    }
}
