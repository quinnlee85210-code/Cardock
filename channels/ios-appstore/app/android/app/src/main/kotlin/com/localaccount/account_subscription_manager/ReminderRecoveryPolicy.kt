package com.localaccount.account_subscription_manager

internal object ReminderRecoveryPolicy {
    const val EXACT = "rescheduled"
    const val INEXACT = "rescheduled_inexact"
    const val FAILED = "failed"

    fun scheduleMode(exactAllowed: Boolean): String =
        if (exactAllowed) "exactAllowWhileIdle" else "inexactAllowWhileIdle"

    fun recover(
        exactAllowed: Boolean,
        dispatch: (Boolean) -> Boolean,
        restoreCache: () -> Unit,
    ): String {
        fun attempt(exact: Boolean): Boolean = try { dispatch(exact) } catch (_: Exception) { false }
        if (attempt(exactAllowed)) return if (exactAllowed) EXACT else INEXACT
        if (exactAllowed && attempt(false)) return INEXACT
        restoreCache()
        return FAILED
    }
}
