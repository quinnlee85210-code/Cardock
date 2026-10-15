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
import org.json.JSONObject

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
    @Volatile private var websiteAccessAllowed = false
    @Volatile private var websiteAccessEpoch = 0L

    private fun requireWebsiteAccess(epoch: Long) {
        check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "website")
        check(websiteAccessAllowed && websiteAccessEpoch == epoch)
    }

    private fun canonical(value: JSONObject): String = value.keys().asSequence().toList().sorted()
        .joinToString(",", "{", "}") { key ->
            val item = value.get(key)
            JSONObject.quote(key) + ":" + if (item is String) JSONObject.quote(item).replace("\\/", "/") else item.toString()
        }

    private fun beginOfflineRequest(purpose: String, reference: String, epoch: Long): Map<String, Any> {
        requireWebsiteAccess(epoch)
        OfflinePurchasePolicy.validatePurpose(purpose, reference)
        val request = mapOf<String, Any>(
            "version" to 1, "application_id" to context.packageName, "channel" to "website",
            "installation_key_sha256" to installationDigest(),
            "request_id" to Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }),
            "purpose" to purpose, "reference" to reference)
        val resolve = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://maskden.com/cardock/offline"))
            .addCategory(android.content.Intent.CATEGORY_BROWSABLE)
        val browser = context.packageManager.resolveActivity(resolve, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        val pending = JSONObject().apply {
            put("request", JSONObject(request))
            put("created_at", System.currentTimeMillis() / 1000)
            put("elapsed", android.os.SystemClock.elapsedRealtime())
            if (browser != null && browser != context.packageName && browser != "android") put("browser", browser)
        }
        requireWebsiteAccess(epoch)
        writeSealed("offline-request", pending.toString())
        return request
    }

    private fun startOfflinePurchase(expectedInstallation: String, epoch: Long, result: MethodChannel.Result) {
        requireWebsiteAccess(epoch)
        val installation = installationDigest()
        check(installation == expectedInstallation)
        val encoder = Base64.getUrlEncoder().withoutPadding()
        val requestId = encoder.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) })
        val payload = canonical(JSONObject(WebsiteCheckoutRequest.payload(installation, requestId, System.currentTimeMillis() / 1000)))
        val entry = keyStore.getEntry(identityAlias, null) as KeyStore.PrivateKeyEntry
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(entry.privateKey)
            update((WebsiteCheckoutRequest.context + payload).toByteArray(Charsets.UTF_8))
            sign()
        }
        val envelope = "{\"payload\":" + payload + ",\"public_key\":" +
            JSONObject.quote(encoder.encodeToString(entry.certificate.publicKey.encoded)) + ",\"signature\":" +
            JSONObject.quote(encoder.encodeToString(signature)) + "}"
        // Build and launch the exact signed URL here; no platform-map/URI round trip.
        val uri = android.net.Uri.parse("https://maskden.com/cardock/buy#purchase=" +
            encoder.encodeToString(envelope.toByteArray(Charsets.UTF_8)))
        requireWebsiteAccess(epoch)
        main.post {
            try {
                requireWebsiteAccess(epoch)
                context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, uri)
                    .addCategory(android.content.Intent.CATEGORY_BROWSABLE))
                result.success(true)
            } catch (_: android.content.ActivityNotFoundException) {
                result.error("CHECKOUT_BROWSER", "External browser unavailable", null)
            } catch (_: Exception) {
                result.error("CHECKOUT_ACCESS", "Purchase access changed", null)
            }
        }
    }

    private fun signOfflineChallenge(payload: String, epoch: Long): Map<String, String> {
        requireWebsiteAccess(epoch)
        check(payload.toByteArray(Charsets.UTF_8).size <= 8192)
        val stored = readSealed("offline-request") ?: error("No locally initiated request")
        val pending = JSONObject(stored)
        val now = System.currentTimeMillis() / 1000
        val age = android.os.SystemClock.elapsedRealtime() - pending.getLong("elapsed")
        check(age in 0L until 600000L && now - pending.getLong("created_at") in 0L until 600L)
        val value = JSONObject(payload)
        val request = pending.getJSONObject("request")
        OfflinePurchasePolicy.validateChallenge(
            value.keys().asSequence().associateWith { value.get(it) },
            request.keys().asSequence().associateWith { request.get(it) },
            installationDigest(), now)
        check(payload == canonical(value))
        val fingerprint = sha256(payload.toByteArray(Charsets.UTF_8))
        if (pending.has("challenge_hash")) {
            check(pending.getString("challenge_hash") == fingerprint)
            val result = pending.getJSONObject("proof")
            requireWebsiteAccess(epoch)
            return result.keys().asSequence().associateWith { result.getString(it) }
        }
        val entry = keyStore.getEntry(identityAlias, null) as KeyStore.PrivateKeyEntry
        val signed = Signature.getInstance("SHA256withECDSA").run {
            initSign(entry.privateKey)
            update((OfflinePurchasePolicy.proofContext + payload).toByteArray(Charsets.UTF_8))
            sign()
        }
        val encode = Base64.getUrlEncoder().withoutPadding()
        val proof = mapOf("challenge_id" to value.getString("challenge_id"),
            "public_key" to encode.encodeToString(entry.certificate.publicKey.encoded),
            "signature" to encode.encodeToString(signed))
        pending.put("challenge_hash", fingerprint)
        pending.put("proof", JSONObject(proof))
        requireWebsiteAccess(epoch)
        writeSealed("offline-request", pending.toString())
        requireWebsiteAccess(epoch)
        return proof
    }

    private fun openOfflineBrowser(url: String, epoch: Long, result: MethodChannel.Result) {
        requireWebsiteAccess(epoch)
        check(url.length <= 16384)
        val uri = android.net.Uri.parse(url)
        check(uri.scheme == "https" && uri.host == "maskden.com" && uri.port == -1 && uri.userInfo == null)
        val rememberedOrders = uri.path == "/orders" && uri.encodedQuery == "view=remembered" && uri.fragment == null
        val browser = if (rememberedOrders) {
            // Read the browser's remembered orders without starting another authorization.
            ""
        } else {
            check(uri.query == null && uri.path in setOf("/cardock/offline", "/cardock/offline/return"))
            val pending = JSONObject(readSealed("offline-request") ?: error("No local request"))
            val fragment = uri.encodedFragment ?: error("Missing offline fragment")
            check(if (uri.path == "/cardock/offline") fragment.startsWith("request=") else fragment.startsWith("proof="))
            pending.optString("browser")
        }
        main.post {
            try {
                requireWebsiteAccess(epoch)
                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, uri).apply {
                    addCategory(android.content.Intent.CATEGORY_BROWSABLE)
                    if (browser.isNotEmpty()) setPackage(browser)
                }
                context.startActivity(intent)
                result.success(true)
            } catch (_: Exception) { result.success(false) }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "setWebsiteAccess") {
                val allowed = call.argument<Boolean>("allowed") == true && BuildConfig.CARDOCK_CHANNEL == "website"
                if (allowed != websiteAccessAllowed) websiteAccessEpoch++
                websiteAccessAllowed = allowed
                result.success(null)
                return@setMethodCallHandler
            }
            val accessEpoch = websiteAccessEpoch
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
                        "startOfflinePurchase" -> {
                            startOfflinePurchase(call.argument<String>("installationKeySha256") ?: error("missing installation"), accessEpoch, result)
                        }
                        "beginOfflineRequest" -> {
                            result.success(beginOfflineRequest(
                                call.argument<String>("purpose") ?: error("missing purpose"),
                                call.argument<String>("reference") ?: "", accessEpoch))
                        }
                        "signOfflineChallenge" -> {
                            result.success(signOfflineChallenge(call.argument<String>("payload") ?: error("missing payload"), accessEpoch))
                        }
                        "openOfflineBrowser" -> {
                            openOfflineBrowser(call.argument<String>("url") ?: error("missing url"), accessEpoch, result)
                        }
                        "clearOfflineRequest" -> {
                            check(preferences.edit().remove("offline-request").commit())
                            result.success(null)
                        }
                        "saveWebsiteLicense" -> {
                            check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "website")
                            val credential = call.argument<String>("credential") ?: error("missing")
                            check(credential.toByteArray(Charsets.UTF_8).size <= 24576)
                            requireWebsiteAccess(accessEpoch)
                            val previous = preferences.getString("website", null)
                            try {
                                requireWebsiteAccess(accessEpoch)
                                writeSealed("website", credential)
                                check(readSealed("website") == credential)
                                requireWebsiteAccess(accessEpoch)
                            } catch (failure: Exception) {
                                // Restore the prior encrypted value on write/readback failure.
                                val editor = preferences.edit()
                                if (previous == null) editor.remove("website") else editor.putString("website", previous)
                                check(editor.commit())
                                throw failure
                            }
                            result.success(null)
                        }
                        "removeWebsiteLicense" -> {
                            requireWebsiteAccess(accessEpoch)
                            val expected = call.argument<String>("expectedCredential") ?: error("missing credential")
                            check(expected.toByteArray(Charsets.UTF_8).size <= 24576)
                            check(readSealed("website") == expected)
                            // This single encrypted preference is independent of every vault and installation key.
                            // Keep a local encrypted recovery copy before removing the active authorization.
                            val keys = listOf("website", "website-removed", "offline-request")
                            val previous = keys.associateWith { preferences.getString(it, null) }
                            val previousTime = preferences.getLong("website-removed-at", 0L)
                            val identity = installationDigest()
                            try {
                                requireWebsiteAccess(accessEpoch)
                                check(preferences.edit()
                                    .putString("website-removed", previous["website"])
                                    .putLong("website-removed-at", System.currentTimeMillis())
                                    .remove("website").remove("offline-request").commit())
                                check(readSealed("website") == null && installationDigest() == identity)
                                requireWebsiteAccess(accessEpoch)
                                OfflinePurchaseIntake.clear()
                            } catch (failure: Exception) {
                                val editor = preferences.edit()
                                for ((key, value) in previous) {
                                    if (value == null) editor.remove(key) else editor.putString(key, value)
                                }
                                if (previousTime == 0L) editor.remove("website-removed-at") else editor.putLong("website-removed-at", previousTime)
                                check(editor.commit())
                                throw failure
                            }
                            result.success(null)
                        }
                        "readReviewAccess" -> {
                            check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "google_play")
                            result.success(readSealed("review-access"))
                        }
                        "saveReviewAccess" -> {
                            check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "google_play")
                            val credential = call.argument<String>("credential") ?: error("missing")
                            check(credential.length == 191 && credential.matches(Regex("CR1[0-9A-HJKMNP-TV-Z]{188}")))
                            // This stores a signed source credential, never a purchased boolean.
                            // Dart verifies its dedicated Ed25519 signature before save and on read.
                            writeSealed("review-access", credential)
                            result.success(null)
                        }
                        "removeReviewAccess" -> {
                            check(trustedPackage() && BuildConfig.CARDOCK_CHANNEL == "google_play")
                            check(preferences.edit().remove("review-access").commit())
                            result.success(null)
                        }
                        "verifyStore" -> main.post {
                            billing.verify(call.argument<Boolean>("refresh") == true) { result.success(it) }
                        }
                        "purchaseStore" -> main.post { billing.purchase { result.success(it) } }
                        "storePrice" -> main.post { billing.price { result.success(it) } }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error(if (call.method == "startOfflinePurchase") "CHECKOUT_PREPARE" else "LICENSE_UNAVAILABLE",
                        "Local verification unavailable", null)
                }
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
