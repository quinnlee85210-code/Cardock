package com.localaccount.account_subscription_manager

import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec

object WebsitePurchasePolicyNativeTest {
    @JvmStatic
    fun main(arguments: Array<String>) {
        val now = 1789000000L
        val app = "com.localaccount.account_subscription_manager"
        val digest = "a".repeat(64)
        val request = mapOf<String, Any>("version" to 1, "purpose" to "order_lookup",
            "application_id" to app, "channel" to "website", "installation_key_sha256" to digest,
            "request_id" to "r".repeat(43), "reference" to "")
        val valid = request + mapOf("kind" to "cardock.offline-installation-challenge",
            "environment" to "production", "key_id" to "synthetic", "challenge_id" to "c".repeat(32),
            "nonce" to "n".repeat(43), "issued_at" to now, "expires_at" to now + 300,
            "audience" to "https://maskden.com", "browser_path" to "/cardock/offline/return",
            "browser_context" to "b".repeat(43))
        var checks = 0
        for (purpose in OfflinePurchasePolicy.purposes) {
            val reference = if (purpose in setOf("order_manage", "license_read")) "20260914001" else ""
            val own = request + mapOf("purpose" to purpose, "reference" to reference)
            OfflinePurchasePolicy.validateChallenge(valid + own, own, digest, now)
            checks++
        }
        for ((field,value) in mapOf("version" to 2, "purpose" to "recovery", "application_id" to "other",
                "channel" to "google_play", "installation_key_sha256" to "b".repeat(64),
                "request_id" to "q".repeat(43), "reference" to "20260914001",
                "kind" to "maskden.website.purchase-read-proof", "environment" to "test",
                "key_id" to "bad/key", "challenge_id" to "short", "nonce" to "short",
                "issued_at" to now + 61, "expires_at" to now, "audience" to "https://other.example",
                "browser_path" to "/orders", "browser_context" to "short", "extra" to "unknown")) {
            check(runCatching { OfflinePurchasePolicy.validateChallenge(valid + (field to value), request, digest, now) }.isFailure)
            checks++
        }
        for (field in OfflinePurchasePolicy.fields) {
            check(runCatching { OfflinePurchasePolicy.validateChallenge(valid - field, request, digest, now) }.isFailure)
            checks++
        }
        for (field in listOf("issued_at", "expires_at", "version")) for (value in listOf<Any>(true, "1", 1.0)) {
            check(runCatching { OfflinePurchasePolicy.validateChallenge(valid + (field to value), request, digest, now) }.isFailure)
            checks++
        }
        check(runCatching { OfflinePurchasePolicy.validateChallenge(valid, request - "request_id", digest, now) }.isFailure)
        checks++
        check(WebsitePurchasePolicy.acceptsLink("website", "android.intent.action.VIEW", WebsitePurchasePolicy.returnUrl))
        checks++
        for (raw in listOf(null, "http://maskden.com/cardock/app/purchase",
            "https://maskden.com:443/cardock/app/purchase", "https://user@maskden.com/cardock/app/purchase",
            "https://maskden.com/orders", "https://maskden.com/admin", "https://maskden.com/cardock/buy",
            "https://maskden.com/cardock/app/purchase/", "https://maskden.com/cardock/app/%70urchase",
            "https://maskden.com.evil.example/cardock/app/purchase",
            WebsitePurchasePolicy.returnUrl + "?paid=true", WebsitePurchasePolicy.returnUrl + "?x=1&x=2",
            WebsitePurchasePolicy.returnUrl + "#credential=fake", "x".repeat(65536))) {
            check(!WebsitePurchasePolicy.acceptsLink("website", "android.intent.action.VIEW", raw))
            checks++
        }
        for (channel in listOf("google_play", "app_store", "development")) {
            check(!WebsitePurchasePolicy.acceptsLink(channel, "android.intent.action.VIEW", WebsitePurchasePolicy.returnUrl))
            checks++
        }
        val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val message = (OfflinePurchasePolicy.proofContext + "synthetic-payload").toByteArray()
        val proof = Signature.getInstance("SHA256withECDSA").run { initSign(pair.private); update(message); sign() }
        check(Signature.getInstance("SHA256withECDSA").run { initVerify(pair.public); update(message); verify(proof) })
        check(!Signature.getInstance("SHA256withECDSA").run {
            initVerify(pair.public); update("maskden.website.installation-proof.v2\nsynthetic-payload".toByteArray()); verify(proof)
        })
        checks += 2
        println("Website purchase policy: $checks checks passed")
    }
}
