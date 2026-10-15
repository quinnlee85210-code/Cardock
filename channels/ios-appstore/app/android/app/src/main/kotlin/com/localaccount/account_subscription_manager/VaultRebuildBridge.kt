package com.localaccount.account_subscription_manager

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.UUID
import org.json.JSONObject

class VaultRebuildBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { const val REQUEST = 7351 }
    private var result: MethodChannel.Result? = null
    private var token: String? = null
    private var issuedAt = 0L
    private var unsecured = false
    private var holdAt: Long? = null
    init {
        MethodChannel(messenger, "cardock/vault_rebuild_v1").setMethodCallHandler { call, reply ->
            try {
                when (call.method) {
                    "authorize" -> {
                        check(result == null); token = null; holdAt = null
                        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        unsecured = !keyguard.isDeviceSecure
                        if (unsecured) { reply.success(issue()) }
                        else {
                            val intent = keyguard.createConfirmDeviceCredentialIntent(
                                call.argument<String>("title"), call.argument<String>("message"))
                                ?: throw IllegalStateException()
                            result = reply; activity.startActivityForResult(intent, REQUEST)
                        }
                    }
                    "beginHold" -> { check(valid(call.argument<String>("token")) && unsecured); holdAt = SystemClock.elapsedRealtime(); reply.success(null) }
                    "cancelHold" -> { if (call.argument<String>("token") == token) holdAt = null; reply.success(null) }
                    "consume" -> {
                        val allowed = valid(call.argument<String>("token")) &&
                            call.argument<String>("phrase") == "删除本机卡坞数据" &&
                            (!unsecured || (call.argument<String>("secondPhrase") == "我理解没有备份将无法恢复" &&
                                holdAt != null && SystemClock.elapsedRealtime() - holdAt!! >= 3000))
                        token = null; holdAt = null; reply.success(allowed)
                    }
                    "clearCommitted" -> {
                        // Startup replay is permitted only with a committed local
                        // journal, never from a cancelled authentication dialog.
                        val journal = File(activity.filesDir, "cardock_rebuild_v1.json")
                        check(journal.isFile && journal.length() <= 256)
                        val intent = JSONObject(journal.readText())
                        check(intent.getInt("version") == 1 && intent.getString("phase") == "committed")
                        ShareIntakeStore.clear()
                        TemporaryWebForegroundService.stop(activity.applicationContext)
                        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                        for (alias in listOf(
                            "com.localaccount.account_subscription_manager.quick_unlock_v2",
                            "com.localaccount.account_subscription_manager.recovery_device_secret_v1")) {
                            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
                            check(!keyStore.containsAlias(alias))
                        }
                        for (name in listOf("asm_quick_unlock_v2", "asm_recovery_device_secret_v1",
                            "asm_notification_reliability", "scheduled_notifications")) {
                            val prefs = activity.getSharedPreferences(name, Context.MODE_PRIVATE)
                            check(prefs.edit().clear().commit()); check(prefs.all.isEmpty())
                        }
                        (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                        // Non-sensitive appearance, language and signed activation
                        // storage are deliberately outside this exact allowlist.
                        reply.success(null)
                    }
                    else -> reply.notImplemented()
                }
            } catch (_: Exception) { result = null; reply.error("rebuild_unavailable", "", null) }
        }
    }
    private fun valid(value: String?) = token != null && value == token && SystemClock.elapsedRealtime() - issuedAt in 0..120_000
    private fun issue(): Map<String, Any> {
        token = UUID.randomUUID().toString(); issuedAt = SystemClock.elapsedRealtime()
        return mapOf("token" to token!!, "unsecured" to unsecured)
    }
    fun onActivityResult(request: Int, code: Int): Boolean {
        if (request != REQUEST) return false
        val reply = result; result = null
        if (code == Activity.RESULT_OK) reply?.success(issue()) else { token = null; reply?.success(null) }
        return true
    }
    fun close() { result?.success(null); result = null; token = null; holdAt = null }
}
