package com.localaccount.account_subscription_manager

/** Legacy exact App Link remains navigation only, never a network or signing path. */
internal object WebsitePurchasePolicy {
    const val returnUrl = "https://maskden.com/cardock/app/purchase"
    fun acceptsLink(channel: String, action: String?, raw: String?): Boolean =
        channel == "website" && action == "android.intent.action.VIEW" && raw == returnUrl
}
