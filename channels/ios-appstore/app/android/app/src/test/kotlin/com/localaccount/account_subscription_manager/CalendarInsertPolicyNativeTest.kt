package com.localaccount.account_subscription_manager

internal object CalendarInsertPolicyNativeTest {
    @JvmStatic fun main(arguments: Array<String>) {
        val base = mapOf<String,Any?>("title" to "Subscription reminder", "begin" to 1788480000000L,
            "end" to 1788566400000L,"alarmDays" to 1)
        var passed = 0
        for (alarm in listOf(null,0,1,3,7)) {
            val event = CalendarInsertPolicy.parse(base + ("alarmDays" to alarm))
            check(event.alarmDays == alarm && event.end - event.begin == 86400000L); passed++
        }
        for (invalid in listOf(
            base + ("title" to ""), base + ("title" to "injected\nbody"), base + ("title" to "x".repeat(1025)),
            base + ("begin" to -1L), base + ("begin" to 1788480000001L), base + ("end" to 1788652800000L),
            base + ("alarmDays" to 2), base + ("alarmDays" to "1"), base + ("uri" to "content://other"),
            base + ("account" to "TEST-ONLY"), base - "end"
        )) {
            check(runCatching { CalendarInsertPolicy.parse(invalid) }.isFailure); passed++
        }
        println("CalendarInsertPolicyNativeTest: $passed allowlist/date/alarm scenarios passed")
    }
}
