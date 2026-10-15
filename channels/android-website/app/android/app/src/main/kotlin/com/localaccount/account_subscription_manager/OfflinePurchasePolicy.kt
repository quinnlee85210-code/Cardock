package com.localaccount.account_subscription_manager

/** Protocol-only validation; no network or Android state. */
internal object OfflinePurchasePolicy {
    const val applicationId = "com.localaccount.account_subscription_manager"
    const val bundlePrefix = "CARDOCK_OFFLINE_ACTIVATION_V1\n"
    const val proofContext = "cardock.offline-installation-proof.v1\n"
    val purposes = setOf("purchase", "order_lookup", "order_manage", "license_read", "recovery")
    val requestFields = setOf("version", "purpose", "application_id", "channel",
        "installation_key_sha256", "request_id", "reference")
    val fields = requestFields + setOf("kind", "environment", "key_id", "challenge_id",
        "nonce", "issued_at", "expires_at", "audience", "browser_path", "browser_context")

    fun validatePurpose(purpose: String, reference: String) {
        require(purpose in purposes)
        if (purpose in setOf("order_manage", "license_read")) {
            require(reference.matches(Regex("[A-Za-z0-9_-]{8,80}")))
        } else require(reference.isEmpty())
    }

    fun validateChallenge(value: Map<String, Any>, request: Map<String, Any>, installation: String, now: Long) {
        require(value.keys == fields && request.keys == requestFields)
        require(request.all { (key, item) -> value[key] == item })
        require(value["version"] == 1 && value["kind"] == "cardock.offline-installation-challenge")
        require(value["environment"] == "production" && value["channel"] == "website")
        require(value["application_id"] == applicationId && value["installation_key_sha256"] == installation)
        require(value["audience"] == "https://maskden.com" && value["browser_path"] == "/cardock/offline/return")
        require(value["key_id"] is String && (value["key_id"] as String).matches(Regex("[A-Za-z0-9_-]{1,64}")))
        validatePurpose(value["purpose"] as String, value["reference"] as String)
        for (name in listOf("nonce", "request_id", "browser_context")) {
            require(value[name] is String && (value[name] as String).matches(Regex("[A-Za-z0-9_-]{43}")))
        }
        require(value["challenge_id"] is String && (value["challenge_id"] as String).matches(Regex("[A-Za-z0-9_-]{32}")))
        val issued = value["issued_at"]
        val expires = value["expires_at"]
        require((issued is Int || issued is Long) && (expires is Int || expires is Long))
        val start = (issued as Number).toLong()
        val end = (expires as Number).toLong()
        require(start > 0 && start <= now + 60 && end > now && end - start == 300L)
    }
}
