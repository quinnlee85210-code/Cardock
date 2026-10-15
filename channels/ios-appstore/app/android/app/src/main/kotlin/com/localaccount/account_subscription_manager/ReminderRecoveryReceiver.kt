package com.localaccount.account_subscription_manager

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import org.json.JSONArray

internal object ReminderReliabilityPreferences {
    const val FILE_NAME = "asm_notification_reliability"
    const val LAST_RECOVERY_AT = "last_recovery_at_epoch_millis"
    const val LAST_RECOVERY_TRIGGER = "last_recovery_trigger"
    const val LAST_RECOVERY_RESULT = "last_recovery_result"
    const val RESULT_RESCHEDULED = "rescheduled"
    const val RESULT_INEXACT = "rescheduled_inexact"
    const val RESULT_FAILED = "failed"
    private const val PLUGIN_SCHEDULED_NOTIFICATIONS_FILE = "scheduled_notifications"
    private const val PLUGIN_SCHEDULED_NOTIFICATIONS_KEY = "scheduled_notifications"

    fun recordRecovery(context: Context, trigger: String, result: String) {
        context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_RECOVERY_AT, System.currentTimeMillis())
            .putString(LAST_RECOVERY_TRIGGER, trigger)
            .putString(LAST_RECOVERY_RESULT, result)
            .commit()
    }

    fun readPluginScheduleCache(context: Context): String? =
        context.getSharedPreferences(
            PLUGIN_SCHEDULED_NOTIFICATIONS_FILE, Context.MODE_PRIVATE,
        ).getString(PLUGIN_SCHEDULED_NOTIFICATIONS_KEY, null)

    fun restorePluginScheduleCache(context: Context, value: String): Boolean =
        context.getSharedPreferences(
            PLUGIN_SCHEDULED_NOTIFICATIONS_FILE, Context.MODE_PRIVATE,
        ).edit().putString(PLUGIN_SCHEDULED_NOTIFICATIONS_KEY, value).commit()
}

/** Runs entirely in Android; the vault and Flutter UI do not need to be open. */
class ReminderRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val trigger = intent.action ?: "unknown"
        val supported = setOf(
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            "android.intent.action.QUICKBOOT_POWERON", "com.htc.intent.action.QUICKBOOT_POWERON",
        )
        if (trigger !in supported) return
        val original = ReminderReliabilityPreferences.readPluginScheduleCache(context)
        var result = ReminderReliabilityPreferences.RESULT_FAILED
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
            // The plugin removes exact entries when permission is missing.
            // Rebuild their actual Android alarms in allow-while-idle mode,
            // preserving dates, ids and generic notification contents.
            val cache = JSONArray(original ?: "[]")
            fun recover(useExact: Boolean): Boolean {
                for (index in 0 until cache.length()) {
                    cache.getJSONObject(index).put(
                        "scheduleMode",
                        ReminderRecoveryPolicy.scheduleMode(useExact),
                    )
                }
                if (!ReminderReliabilityPreferences.restorePluginScheduleCache(context, cache.toString())) {
                    return false
                }
                ScheduledNotificationBootReceiver().onReceive(
                    context, Intent(Intent.ACTION_BOOT_COMPLETED),
                )
                val restored = JSONArray(
                    ReminderReliabilityPreferences.readPluginScheduleCache(context) ?: "[]",
                )
                val expectedIds = (0 until cache.length()).map { cache.getJSONObject(it).getInt("id") }.toSet()
                val restoredIds = (0 until restored.length()).map { restored.getJSONObject(it).getInt("id") }.toSet()
                return expectedIds == restoredIds
            }
            result = ReminderRecoveryPolicy.recover(exact, ::recover) {
                if (original != null) ReminderReliabilityPreferences.restorePluginScheduleCache(context, original)
            }
        } catch (_: Exception) {
            if (original != null) ReminderReliabilityPreferences.restorePluginScheduleCache(context, original)
        }
        ReminderReliabilityPreferences.recordRecovery(context, trigger, result)
    }
}

