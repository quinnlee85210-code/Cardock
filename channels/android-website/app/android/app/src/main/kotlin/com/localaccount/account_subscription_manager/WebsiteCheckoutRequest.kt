package com.localaccount.account_subscription_manager

/** A short-lived purchase intent signed by this installation, never payment evidence. */
internal object WebsiteCheckoutRequest {
    const val context = "cardock.offline-checkout-request.v1\n"
    fun payload(installation: String, requestId: String, now: Long): Map<String, Any> {
        require(installation.matches(Regex("[a-f0-9]{64}")))
        require(requestId.matches(Regex("[A-Za-z0-9_-]{43}")))
        require(now in 1L..253402300199L)
        return mapOf("version" to 1, "kind" to "cardock.offline-checkout-request",
            "application_id" to OfflinePurchasePolicy.applicationId, "channel" to "website",
            "environment" to "production", "audience" to "https://maskden.com",
            "product_id" to "cardock.full.lifetime", "amount_minor" to 990, "currency" to "CNY",
            "installation_key_sha256" to installation, "request_id" to requestId,
            "purpose" to "purchase", "reference" to "", "issued_at" to now, "expires_at" to now + 600)
    }
}
