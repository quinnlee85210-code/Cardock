package com.localaccount.account_subscription_manager

import java.util.UUID

internal object ShareIntakeStore {
    private const val TIME_TO_LIVE_MILLISECONDS = 5 * 60 * 1000L

    private sealed interface StoredItem {
        val receivedAtElapsedRealtime: Long

        data class Accepted(
            val token: String,
            val text: String,
            val subject: String?,
            val title: String?,
            override val receivedAtElapsedRealtime: Long,
        ) : StoredItem

        data class Rejected(
            val error: ShareIntakeErrorCode,
            override val receivedAtElapsedRealtime: Long,
        ) : StoredItem
    }

    private var pending: StoredItem? = null

    fun replace(validation: ShareIntentValidation) {
        replaceAt(validation, monotonicMilliseconds())
    }

    @Synchronized
    internal fun replaceAt(validation: ShareIntentValidation, now: Long) {
        pending = when (validation) {
            is ShareIntentValidation.Accepted -> StoredItem.Accepted(
                token = UUID.randomUUID().toString(),
                text = validation.text,
                subject = validation.subject,
                title = validation.title,
                receivedAtElapsedRealtime = now,
            )
            is ShareIntentValidation.Rejected -> StoredItem.Rejected(
                error = validation.error,
                receivedAtElapsedRealtime = now,
            )
        }
    }

    fun consume(): Map<String, Any?>? = consumeAt(monotonicMilliseconds())

    @Synchronized
    internal fun consumeAt(now: Long): Map<String, Any?>? {
        val item = pending ?: return null
        pending = null
        val age = (now - item.receivedAtElapsedRealtime)
            .coerceAtLeast(0L)
        if (age >= TIME_TO_LIVE_MILLISECONDS) {
            return errorResult(ShareIntakeErrorCode.EXPIRED)
        }
        return when (item) {
            is StoredItem.Accepted -> mapOf(
                "status" to "accepted",
                "token" to item.token,
                "text" to item.text,
                "subject" to item.subject,
                "title" to item.title,
                "remainingLifetimeMilliseconds" to
                    (TIME_TO_LIVE_MILLISECONDS - age),
            )
            is StoredItem.Rejected -> errorResult(item.error)
        }
    }

    @Synchronized
    fun clear() {
        pending = null
    }

    private fun monotonicMilliseconds(): Long = System.nanoTime() / 1_000_000L

    private fun errorResult(error: ShareIntakeErrorCode): Map<String, Any?> = mapOf(
        "status" to "rejected",
        "errorCode" to error.name,
    )
}
