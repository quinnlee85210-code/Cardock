package com.localaccount.account_subscription_manager

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.*
import org.json.JSONObject

/** One non-consumable product. All callbacks and sealed-cache updates run on main. */
internal class StoreBillingAdapter(private val activity: Activity, private val trusted: () -> Boolean,
    private val readCache: () -> String?, private val saveCache: (String) -> Unit, private val clearCache: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val productId get() = BuildConfig.CARDOCK_STORE_PRODUCT_ID
    private var disposed = false
    private var purchaseDone: ((String) -> Unit)? = null
    private var purchaseTimeout: Runnable? = null
    private val connectionWaiters = mutableListOf<(Boolean) -> Unit>()
    private var connecting = false
    private val billing = BillingClient.newBuilder(activity)
        .setListener { result, purchases -> main.post {
            if (disposed) return@post
            when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> process(purchases.orEmpty()) { finishPurchase(if (it) "purchased" else if (purchases.orEmpty().any { p -> productId in p.products && p.purchaseState == Purchase.PurchaseState.PENDING }) "pending" else "unavailable") }
                BillingClient.BillingResponseCode.USER_CANCELED -> finishPurchase("cancelled")
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> verify(true) { finishPurchase(if (it) "purchased" else "unavailable") }
                else -> finishPurchase("unavailable")
            }
        } }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection().build()
    private fun configured() = !disposed && trusted() && productId.matches(Regex("[a-zA-Z0-9._]{3,128}")) && PlayBillingReceiptVerifier.configured(BuildConfig.CARDOCK_PLAY_PUBLIC_KEY)
    private fun valid(p: Purchase): Boolean = p.purchaseState == Purchase.PurchaseState.PURCHASED &&
        p.packageName == activity.packageName && p.products == listOf(productId) && p.purchaseToken.isNotBlank() &&
        p.quantity == 1 && PlayBillingReceiptVerifier.verify(BuildConfig.CARDOCK_PLAY_PUBLIC_KEY, p.originalJson, p.signature)
    private fun cached(): Boolean = try {
        val raw = readCache()
        if (raw == null) false else {
            val c = JSONObject(raw)
            c.getBoolean("acknowledged") && valid(Purchase(c.getString("data"), c.getString("signature")))
        }
    } catch (_: Exception) { false }
    private fun connect(done: (Boolean) -> Unit) {
        if (!configured()) { done(false); return }
        if (billing.isReady) { done(true); return }
        connectionWaiters.add(done)
        if (connecting) return
        connecting = true
        val timeout = Runnable { completeConnection(false) }
        main.postDelayed(timeout, 15000)
        try {
            billing.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) { main.post {
                    main.removeCallbacks(timeout); completeConnection(result.responseCode == BillingClient.BillingResponseCode.OK)
                } }
                override fun onBillingServiceDisconnected() { main.post { completeConnection(false) } }
            })
        } catch (_: Exception) { main.removeCallbacks(timeout); completeConnection(false) }
    }
    private fun completeConnection(ok: Boolean) {
        connecting = false
        val callbacks = connectionWaiters.toList(); connectionWaiters.clear()
        callbacks.forEach { it(ok && !disposed) }
    }
    fun verify(@Suppress("UNUSED_PARAMETER") refresh: Boolean, done: (Boolean) -> Unit) {
        if (!configured()) { done(false); return }
        val previous = cached()
        var completed = false
        lateinit var timeout: Runnable
        fun finish(value: Boolean) {
            if (completed) return
            completed = true
            main.removeCallbacks(timeout)
            done(value)
        }
        timeout = Runnable { finish(previous) }
        main.postDelayed(timeout, 25000)
        // Query on foreground as well as explicit restore; offline errors preserve verified cache.
        connect { ready ->
            if (completed) return@connect
            if (!ready) { finish(previous); return@connect }
            try {
                billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()) { result, purchases -> main.post {
                    if (completed) return@post
                    if (disposed) { finish(false); return@post }
                    if (result.responseCode != BillingClient.BillingResponseCode.OK) { finish(previous); return@post }
                    val hasProduct = purchases.any { productId in it.products }
                    process(purchases) { licensed ->
                        if (completed) return@process
                        val decision = BillingOwnershipPolicy.afterQuery(previous, true, hasProduct, licensed)
                        if (decision.clearCache) try { clearCache() } catch (_: Exception) { }
                        finish(decision.licensed)
                    }
                } }
            } catch (_: Exception) { finish(previous) }
        }
    }
    private fun process(purchases: List<Purchase>, done: (Boolean) -> Unit) {
        val purchase = purchases.firstOrNull { valid(it) }
        if (purchase == null) { done(false); return }
        fun persist() {
            try {
                if (!configured()) { done(false); return }
                saveCache(JSONObject().put("data", purchase.originalJson).put("signature", purchase.signature)
                    .put("acknowledged", true).toString())
                done(true)
            } catch (_: Exception) { done(false) }
        }
        if (purchase.isAcknowledged) persist()
        else billing.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()) { result -> main.post {
            if (result.responseCode == BillingClient.BillingResponseCode.OK) persist() else done(false)
        } }
    }
    private fun details(done: (ProductDetails?) -> Unit) = connect { ready ->
        if (!ready) { done(null); return@connect }
        val product = QueryProductDetailsParams.Product.newBuilder().setProductId(productId).setProductType(BillingClient.ProductType.INAPP).build()
        billing.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build()) { result, details -> main.post {
            done(if (result.responseCode == BillingClient.BillingResponseCode.OK && !disposed) details.productDetailsList.singleOrNull { it.productId == productId } else null)
        } }
    }
    // Only a configured buy option is accepted; rental/preorder offers are never used.
    private fun offer(details: ProductDetails) = details.oneTimePurchaseOfferDetailsList?.firstOrNull {
        it.rentalDetails == null && it.preorderDetails == null && it.priceAmountMicros > 0
    }
    fun price(done: (String?) -> Unit) = details { details -> done(details?.let { offer(it)?.formattedPrice }) }
    fun purchase(done: (String) -> Unit) {
        if (purchaseDone != null || !configured()) { done("unavailable"); return }
        purchaseDone = done
        purchaseTimeout = Runnable { finishPurchase("unavailable") }.also { main.postDelayed(it, 300000) }
        details { details ->
            if (purchaseDone == null) return@details
            val offer = details?.let { offer(it) }
            if (details == null || offer == null) { finishPurchase("unavailable"); return@details }
            val item = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details).apply { offer.offerToken?.let { setOfferToken(it) } }.build()
            val result = billing.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(item)).build())
            when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> Unit
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> verify(true) { finishPurchase(if (it) "purchased" else "unavailable") }
                BillingClient.BillingResponseCode.USER_CANCELED -> finishPurchase("cancelled")
                else -> finishPurchase("unavailable")
            }
        }
    }
    private fun finishPurchase(status: String) {
        purchaseTimeout?.let { main.removeCallbacks(it) }; purchaseTimeout = null
        val done = purchaseDone; purchaseDone = null; done?.invoke(status)
    }
    fun dispose() { disposed = true; finishPurchase("unavailable"); completeConnection(false); billing.endConnection() }
}
