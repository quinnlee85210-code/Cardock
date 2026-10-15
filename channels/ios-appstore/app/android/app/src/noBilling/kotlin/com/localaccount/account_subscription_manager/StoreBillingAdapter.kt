package com.localaccount.account_subscription_manager

/** Website/development builds neither link the Play SDK nor request its billing permission. */
@Suppress("UNUSED_PARAMETER")
internal class StoreBillingAdapter(activity: android.app.Activity, trusted: () -> Boolean,
    readCache: () -> String?, saveCache: (String) -> Unit, clearCache: () -> Unit) {
    fun verify(refresh: Boolean, done: (Boolean) -> Unit) = done(false)
    fun purchase(done: (String) -> Unit) = done("unavailable")
    fun price(done: (String?) -> Unit) = done(null)
    fun dispose() { }
}
