package com.localaccount.account_subscription_manager

/** Exact allowlist; no arbitrary Intent, URI, account or provider operations. */
object CalendarInsertPolicy {
    data class Event(val title: String, val begin: Long, val end: Long, val alarmDays: Int?)
    fun parse(args: Map<*, *>): Event {
        require(args.keys == setOf("title", "begin", "end", "alarmDays"))
        val title = args["title"] as? String ?: throw IllegalArgumentException()
        val begin = (args["begin"] as? Number)?.toLong() ?: throw IllegalArgumentException()
        val end = (args["end"] as? Number)?.toLong() ?: throw IllegalArgumentException()
        val alarm = args["alarmDays"]
        require(alarm == null || alarm is Int && alarm in setOf(0,1,3,7))
        require(title.isNotBlank() && title.length <= 1024 && title.none { it.code < 32 || it.code == 127 })
        require(begin in 0L..10413791999999L && begin % 86400000L == 0L && end - begin == 86400000L)
        return Event(title, begin, end, alarm)
    }
}
