package com.hutong.oneplusagent.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object BleSecretStore {
    private const val KEY_ALIAS = "oneplus-connect-ble-secret"
    private const val PREFS = "ble_pairing"
    private const val CIPHERTEXT = "secret"
    private const val IV = "iv"

    fun read(context: Context): String {
        return runCatching {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val encoded = preferences.getString(CIPHERTEXT, null)
            if (encoded == null) return ""
            val iv = Base64.decode(preferences.getString(IV, ""), Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)), Charsets.UTF_8)
        }.getOrDefault("")
    }

    fun provision(context: Context, secret: String): Boolean {
        if (secret.toByteArray(Charsets.UTF_8).size < 32) return false
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val encrypted = Base64.encodeToString(cipher.doFinal(secret.toByteArray()), Base64.NO_WRAP)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(CIPHERTEXT, encrypted)
                .putString(IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .commit()
        }.getOrDefault(false)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }
}
