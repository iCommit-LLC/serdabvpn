package app.serdabvpn

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The config at rest, so the tunnel can come back without the app's UI
 * (after a reboot, or when Android's Always-on VPN asks for it).
 *
 * AES-GCM in the app's private files, under a key that is generated inside the
 * Android Keystore and never leaves it: same promise as the Dart side's store.
 */
object Vault {
    private const val ALIAS = "serdab-config"
    private const val FILE = "serdab.conf.enc"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    fun save(context: Context, text: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        File(context.filesDir, FILE).writeBytes(byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + sealed)
    }

    fun load(context: Context): String? {
        val f = File(context.filesDir, FILE)
        if (!f.exists()) return null
        return try {
            val b = f.readBytes()
            val n = b[0].toInt()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, b.copyOfRange(1, 1 + n)))
            }
            String(cipher.doFinal(b.copyOfRange(1 + n, b.size)), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }

    fun clear(context: Context) {
        File(context.filesDir, FILE).delete()
    }
}
