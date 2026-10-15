package com.localaccount.account_subscription_manager

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** User edits and saves in their calendar. No Calendar Provider reads/writes. */
class CalendarInsertBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cardock/calendar_insert_v1")
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "insert") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val event = CalendarInsertPolicy.parse(call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
                val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.Events.TITLE, event.title)
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, event.begin)
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, event.end)
                    .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                    .putExtra(CalendarContract.Events.HAS_ALARM, event.alarmDays != null)
                // Calendar apps may ignore these optional reminder hints. The
                // UI explicitly asks users to verify them before saving; ICS
                // carries the selected reminder as a standards-based VALARM.
                event.alarmDays?.let { intent.putExtra(CalendarContract.Reminders.MINUTES, it * 1440) }
                activity.startActivity(intent)
                result.success("opened")
            } catch (_: ActivityNotFoundException) { result.success("unavailable")
            } catch (_: Exception) { result.error("calendar_unavailable", "", null) }
        }
    }
    fun close() { channel.setMethodCallHandler(null) }
}
