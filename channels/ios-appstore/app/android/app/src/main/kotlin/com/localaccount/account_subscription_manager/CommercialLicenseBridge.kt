package com.localaccount.account_subscription_manager

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Licensing keys and state are independent of every vault/recovery key. */
internal class CommercialLicenseBridge(private val context: android.app.Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cardock/commercial_license")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val preferences = context.getSharedPreferences("cardock.commercial.license.v2", Context.MODE_PRIVATE)
    private val keyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }
    private val identityAlias = "cardock.commercial.identity.v2"
    private val sealAlias = "cardock.commercial.cache.v2"
    private val billing = StoreBillingAdapter(context,
        { trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "google_play" },
        { readSealed("play") }, { writeSealed("play", it) },
        { check(preferences.edit().remove("play").commit()) })
    @Volatile private var disposed = false
    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    if (disposed) { result.success(false); return@execute }
                    when (call.method) {
                        "inspect" -> {
                            val trusted = trustedPackage()
                            result.success(if (!trusted) mapOf("trusted" to false) else mapOf(
                                "trusted" to true, "channel" to BuildConfig.CARDOCK_CHANNEL,
                                "applicationId" to context.packageName,
                                "installationKeySha256" to installationDigest(),
                                "websiteLicense" to if (BuildConfig.CARDOCK_CHANNEL == "website") readSealed("website") else null,
                            ))
                        }
                        "saveWebsiteLicense" -> {
                            check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "website")
                            val credential = call.argument<String>("credential") ?: error("missing")
                            check(credential.length <= 16384)
                            writeSealed("website", credential)
                            result.success(null)
                        }
                        "verifyStore" -> main.post {
                            billing.verify(call.argument<Boolean>("refresh") == true) { result.success(it) }
                        }
                        "purchaseStore" -> main.post { billing.purchase { result.success(it) } }
                        "storePrice" -> main.post { billing.price { result.success(it) } }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("LICENSE_UNAVAILABLE", "License verification unavailable", null) }
            }
        }
    }
    @Suppress("DEPRECATION")
    private fun trustedPackage(): Boolean {
        if (BuildConfig.CARDOCK_CHANNEL !in setOf("website", "google_play")) return false
        if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) return false
        val expected = BuildConfig.CARDOCK_SIGNING_SHA256.split(',').map { it.trim().lowercase() }.filter { it.matches(Regex("[a-f0-9]{64}")) }.toSet()
        if (expected.isEmpty()) return false
        val info = context.packageManager.getPackageInfo(context.packageName,
            if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
        val current = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        // Check the actual current signer, not installer name or a historical certificate.
        return current != null && current.size == 1 && sha256(current[0].toByteArray()) in expected
    }
    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun installationDigest(): String {
        if (!keyStore.containsAlias(identityAlias)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(identityAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256).build())
                generateKeyPair()
            }
        }
        val entry = keyStore.getEntry(identityAlias, null) as KeyStore.PrivateKeyEntry
        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val proof = Signature.getInstance("SHA256withECDSA").run { initSign(entry.privateKey); update(challenge); sign() }
        check(Signature.getInstance("SHA256withECDSA").run { initVerify(entry.certificate.publicKey); update(challenge); verify(proof) })
        return sha256(entry.certificate.publicKey.encoded)
    }
    private fun sealKey(): SecretKey {
        if (!keyStore.containsAlias(sealAlias)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(sealAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                generateKey()
            }
        }
        return keyStore.getKey(sealAlias, null) as SecretKey
    }
    private fun aad(slot: String) = "${context.packageName}|${BuildConfig.CARDOCK_CHANNEL}|${installationDigest()}|$slot|v2".toByteArray(Charsets.UTF_8)
    private fun writeSealed(slot: String, data: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, sealKey()); cipher.updateAAD(aad(slot))
        val bytes = cipher.iv + cipher.doFinal(data.toByteArray(Charsets.UTF_8))
        check(preferences.edit().putString(slot, Base64.getEncoder().encodeToString(bytes)).commit())
    }
    private fun readSealed(slot: String): String? = try {
        val encoded = preferences.getString(slot, null)
        if (encoded == null || encoded.length > 65536) null else {
            val data = Base64.getDecoder().decode(encoded)
            if (data.size < 29) null else {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, sealKey(), GCMParameterSpec(128, data.copyOfRange(0,12)))
                cipher.updateAAD(aad(slot)); String(cipher.doFinal(data.copyOfRange(12,data.size)), Charsets.UTF_8)
            }
        }
    } catch (_: Exception) { null }
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        billing.dispose()
        worker.shutdown()
    }
}
