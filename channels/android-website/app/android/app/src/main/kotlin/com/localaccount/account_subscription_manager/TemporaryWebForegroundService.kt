package com.localaccount.account_subscription_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.annotation.RequiresApi
import androidx.annotation.StringRes
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

internal fun releaseRuntimeResources(
    releaseWifi: () -> Unit,
    releaseWake: () -> Unit,
) {
    var firstFailure: RuntimeException? = null
    try {
        releaseWifi()
    } catch (error: RuntimeException) {
        firstFailure = error
    }
    try {
        releaseWake()
    } catch (error: RuntimeException) {
        val existingFailure = firstFailure
        if (existingFailure == null) {
            firstFailure = error
        } else {
            existingFailure.addSuppressed(error)
        }
    }
    firstFailure?.let { throw it }
}

internal fun acquireRuntimeResources(
    acquire: () -> Unit,
    releaseAfterFailure: () -> Unit,
) {
    try {
        acquire()
    } catch (acquireFailure: RuntimeException) {
        try {
            releaseAfterFailure()
        } catch (releaseFailure: RuntimeException) {
            acquireFailure.addSuppressed(releaseFailure)
        }
        throw acquireFailure
    }
}

internal fun completeRuntimeShutdown(
    vararg steps: () -> Unit,
) {
    var firstFailure: RuntimeException? = null
    for (step in steps) {
        try {
            step()
        } catch (error: RuntimeException) {
            val existingFailure = firstFailure
            if (existingFailure == null) {
                firstFailure = error
            } else {
                existingFailure.addSuppressed(error)
            }
        }
    }
    firstFailure?.let { throw it }
}

class TemporaryWebForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "cardock_temporary_web_runtime"
        private const val NOTIFICATION_ID = 42117
        private const val LANGUAGE_PREFERENCES = "asm_platform_language"
        private const val PREF_LANGUAGE = "language"
        private const val LANGUAGE_SIMPLIFIED_CHINESE = "zh_CN"
        private const val LANGUAGE_ENGLISH = "en"
        private const val LANGUAGE_JAPANESE = "ja"
        private const val WAKE_LOCK_TIMEOUT_MILLIS = 30 * 60 * 1000L

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, TemporaryWebForegroundService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, TemporaryWebForegroundService::class.java),
            )
        }
    }

    private var runtimeWakeLock: PowerManager.WakeLock? = null
    private var runtimeWifiLock: WifiManager.WifiLock? = null
    private val runtimeTimeoutHandler = Handler(Looper.getMainLooper())
    private val runtimeTimeout = Runnable {
        completeRuntimeShutdown(
            ::releaseRuntimeLocks,
            { stopForeground(STOP_FOREGROUND_REMOVE) },
            ::stopSelf,
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        acquireRuntimeLocks()
        runtimeTimeoutHandler.removeCallbacks(runtimeTimeout)
        runtimeTimeoutHandler.postDelayed(
            runtimeTimeout,
            WAKE_LOCK_TIMEOUT_MILLIS,
        )
        return START_NOT_STICKY
    }

    @RequiresApi(35)
    override fun onTimeout(startId: Int, fgsType: Int) {
        completeRuntimeShutdown(
            ::releaseRuntimeLocks,
            { stopForeground(STOP_FOREGROUND_REMOVE) },
            { stopSelf(startId) },
        )
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        completeRuntimeShutdown(
            ::releaseRuntimeLocks,
            { stopForeground(STOP_FOREGROUND_REMOVE) },
            ::stopSelf,
            { super.onTaskRemoved(rootIntent) },
        )
    }

    override fun onDestroy() {
        completeRuntimeShutdown(
            ::releaseRuntimeLocks,
            { stopForeground(STOP_FOREGROUND_REMOVE) },
            { super.onDestroy() },
        )
    }

    private fun acquireRuntimeWakeLock() {
        val lock = runtimeWakeLock ?: (
            getSystemService(Context.POWER_SERVICE) as PowerManager
        ).newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:temporary-web-session",
        ).also {
            it.setReferenceCounted(false)
            runtimeWakeLock = it
        }
        if (!lock.isHeld) {
            lock.acquire(WAKE_LOCK_TIMEOUT_MILLIS)
        }
    }

    private fun acquireRuntimeLocks() {
        acquireRuntimeResources(
            acquire = {
                acquireRuntimeWakeLock()
                acquireRuntimeWifiLock()
            },
            releaseAfterFailure = ::releaseRuntimeLocks,
        )
    }

    @Suppress("DEPRECATION")
    private fun acquireRuntimeWifiLock() {
        val lock = runtimeWifiLock ?: (
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        ).createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "$packageName:temporary-web-session",
        ).also {
            it.setReferenceCounted(false)
            runtimeWifiLock = it
        }
        if (!lock.isHeld) {
            lock.acquire()
        }
    }

    private fun releaseRuntimeLocks() {
        runtimeTimeoutHandler.removeCallbacks(runtimeTimeout)
        releaseRuntimeResources(
            releaseWifi = ::releaseRuntimeWifiLock,
            releaseWake = ::releaseRuntimeWakeLock,
        )
    }

    private fun releaseRuntimeWifiLock() {
        val lock = runtimeWifiLock
        runtimeWifiLock = null
        if (lock?.isHeld == true) {
            lock.release()
        }
    }

    private fun releaseRuntimeWakeLock() {
        val lock = runtimeWakeLock
        runtimeWakeLock = null
        if (lock?.isHeld == true) {
            lock.release()
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            localizedString(R.string.temporary_web_service_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = localizedString(
                R.string.temporary_web_service_channel_description,
            )
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            enableVibration(false)
            setSound(null, null)
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(
                localizedString(R.string.temporary_web_service_notification_title),
            )
            .setContentText(
                localizedString(R.string.temporary_web_service_notification_text),
            )
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    private fun localizedString(@StringRes resourceId: Int): String {
        val language = getSharedPreferences(
            LANGUAGE_PREFERENCES,
            Context.MODE_PRIVATE,
        ).getString(PREF_LANGUAGE, LANGUAGE_SIMPLIFIED_CHINESE)
        val locale = when (language) {
            LANGUAGE_ENGLISH -> Locale.ENGLISH
            LANGUAGE_JAPANESE -> Locale.JAPANESE
            else -> Locale.SIMPLIFIED_CHINESE
        }
        val configuration = Configuration(resources.configuration)
        configuration.setLocale(locale)
        return createConfigurationContext(configuration).getString(resourceId)
    }
}
