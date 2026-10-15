package com.localaccount.account_subscription_manager

internal object ReminderRecoveryPolicyNativeTest {
    @JvmStatic
    fun main(arguments: Array<String>) {
        var restores = 0
        val calls = mutableListOf<Boolean>()
        fun run(allowed: Boolean, outcomes: List<Boolean>): String {
            calls.clear()
            var index = 0
            return ReminderRecoveryPolicy.recover(allowed, {
                calls += it
                outcomes[index++]
            }, { restores++ })
        }
        check(run(false, listOf(true)) == ReminderRecoveryPolicy.INEXACT)
        check(calls == listOf(false))
        check(restores == 0)
        check(run(true, listOf(true)) == ReminderRecoveryPolicy.EXACT)
        check(calls == listOf(true))
        // Simulate the plugin removing exact entries after permission revocation.
        check(run(true, listOf(false, true)) == ReminderRecoveryPolicy.INEXACT)
        check(calls == listOf(true, false))
        check(restores == 0)
        check(run(true, listOf(false, false)) == ReminderRecoveryPolicy.FAILED)
        check(restores == 1)
        check(run(false, listOf(false)) == ReminderRecoveryPolicy.FAILED)
        check(calls == listOf(false))
        check(restores == 2)
        val result = ReminderRecoveryPolicy.recover(true, {
            if (it) throw SecurityException("TEST-ONLY-REVOKED")
            true
        }, { error("cache should not need restoring") })
        check(result == ReminderRecoveryPolicy.INEXACT)
        check(ReminderRecoveryPolicy.scheduleMode(false) == "inexactAllowWhileIdle")
        check(ReminderRecoveryPolicy.scheduleMode(true) == "exactAllowWhileIdle")
        println("ReminderRecoveryPolicyNativeTest: 6 recovery scenarios passed")
    }
}
