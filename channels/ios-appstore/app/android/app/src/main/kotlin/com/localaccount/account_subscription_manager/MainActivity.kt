package com.localaccount.account_subscription_manager

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.PersistableBundle
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.annotation.StringRes
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.Locale
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val SENSITIVE_CLIPBOARD_CHANNEL =
            "account_subscription_manager/sensitive_clipboard"
        private const val QUICK_UNLOCK_CHANNEL =
            "account_subscription_manager/quick_unlock_v2"
        private const val RECOVERY_DEVICE_SECRET_CHANNEL =
            "account_subscription_manager/recovery_device_secret_v1"
        private const val UNLOCK_CLOCK_CHANNEL =
            "account_subscription_manager/unlock_clock_v1"
        private const val LAUNCHER_ICON_CHANNEL = "cardock/launcher_icon"
        private const val SCREEN_PROTECTION_CHANNEL = "cardock/screen_protection"
        private const val NOTIFICATION_RELIABILITY_CHANNEL =
            "cardock/notification_reliability"
        private const val PLATFORM_LANGUAGE_CHANNEL = "cardock/platform_language"
        private const val TEMPORARY_WEB_RUNTIME_CHANNEL =
            "cardock/temporary_web_runtime"
        private const val SHARE_INTAKE_CHANNEL = "cardock/share_intake"
        const val ACTION_OPEN_SHARED_TEXT =
            "com.localaccount.account_subscription_manager.action.OPEN_SHARED_TEXT"
        private const val REMINDER_NOTIFICATION_CHANNEL_ID =
            "local_subscription_reminders"
        private const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"

        private const val PRIVACY_PREFERENCES = "asm_privacy_preferences"
        private const val PREF_SECURE_WINDOW_ENABLED = "secure_window_enabled"
        private const val LANGUAGE_PREFERENCES = "asm_platform_language"
        private const val PREF_LANGUAGE = "language"
        private const val LANGUAGE_SIMPLIFIED_CHINESE = "zh_CN"
        private const val LANGUAGE_ENGLISH = "en"
        private const val LANGUAGE_JAPANESE = "ja"

        private const val LAUNCHER_CERAMIC_BLUE = "ceramicBlue"
        private const val LAUNCHER_SAKURA_MIST = "sakuraMist"
        private const val LAUNCHER_PAPER_ARCHIVE = "paperArchive"
        private const val LAUNCHER_LILAC_MOON = "lilacMoon"
        private const val LAUNCHER_GLACIER_BLUE = "glacierBlue"
        private const val LAUNCHER_MIST_CORAL = "mistCoral"
        private const val LAUNCHER_NEON_ZERO = "neonZero"
        private const val LAUNCHER_OBSIDIAN_GOLD = "obsidianGold"
        private const val LEGACY_LAUNCHER_STANDARD = "standard"
        private const val LEGACY_LAUNCHER_PRIME = "prime"
        private const val LEGACY_LAUNCHER_VIVID = "vivid"
        private val LAUNCHER_MANIFEST_DEFAULTS = linkedMapOf(
            LAUNCHER_CERAMIC_BLUE to false,
            LAUNCHER_SAKURA_MIST to false,
            LAUNCHER_PAPER_ARCHIVE to true,
            LAUNCHER_LILAC_MOON to false,
            LAUNCHER_GLACIER_BLUE to false,
            LAUNCHER_MIST_CORAL to false,
            LAUNCHER_NEON_ZERO to false,
            LAUNCHER_OBSIDIAN_GOLD to false,
            LEGACY_LAUNCHER_STANDARD to false,
            LEGACY_LAUNCHER_PRIME to false,
            LEGACY_LAUNCHER_VIVID to false,
        )

        private const val QUICK_UNLOCK_PREFS = "asm_quick_unlock_v2"
        private const val QUICK_UNLOCK_KEY_ALIAS =
            "com.localaccount.account_subscription_manager.quick_unlock_v2"
        private const val PREF_CONFIGURED = "configured"
        private const val PREF_VERSION = "version"
        private const val PREF_CIPHERTEXT = "ciphertext"
        private const val PREF_IV = "iv"
        private const val QUICK_UNLOCK_VERSION = 2
        private const val MAX_SECRET_BYTES = 4096
        private const val RECOVERY_DEVICE_SECRET_PREFS = "asm_recovery_device_secret_v1"
        private const val RECOVERY_DEVICE_SECRET_KEY_ALIAS =
            "com.localaccount.account_subscription_manager.recovery_device_secret_v1"
        private const val RECOVERY_DEVICE_SECRET_PREF_CONFIGURED = "configured"
        private const val RECOVERY_DEVICE_SECRET_PREF_VERSION = "version"
        private const val RECOVERY_DEVICE_SECRET_PREF_CIPHERTEXT = "ciphertext"
        private const val RECOVERY_DEVICE_SECRET_PREF_IV = "iv"
        private const val RECOVERY_DEVICE_SECRET_VERSION = 1
        private const val RECOVERY_DEVICE_SECRET_MAX_BYTES = 4096
        private const val RECOVERY_DEVICE_SECRET_MAX_METADATA_BYTES = 512
        private val RECOVERY_DEVICE_SECRET_PAYLOAD_KEYS = setOf(
            "version",
            "vaultInstanceId",
            "slotId",
            "deviceBindingId",
            "deviceSecret",
        )
        private const val GCM_TAG_BITS = 128
        private const val PROMPT_READY_RETRY_DELAY_MS = 50L
        private const val PROMPT_READY_MAX_ATTEMPTS = 40
        private const val PROMPT_TIMEOUT_MS = 45_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var nextQuickUnlockOperationId = 0L
    private var activeQuickUnlockOperationId: Long? = null
    private var activeQuickUnlockPrompt: BiometricPrompt? = null
    private var activeQuickUnlockResult: MethodChannel.Result? = null
    private var activeQuickUnlockCleanup: (() -> Unit)? = null
    private var activeQuickUnlockLaunchRunnable: Runnable? = null
    private var activeQuickUnlockTimeoutRunnable: Runnable? = null
    private var nextRecoveryDeviceSecretOperationId = 0L
    private var activeRecoveryDeviceSecretOperationId: Long? = null
    private var activeRecoveryDeviceSecretPrompt: BiometricPrompt? = null
    private var activeRecoveryDeviceSecretResult: MethodChannel.Result? = null
    private var activeRecoveryDeviceSecretCleanup: (() -> Unit)? = null
    private var activeRecoveryDeviceSecretLaunchRunnable: Runnable? = null
    private var activeRecoveryDeviceSecretTimeoutRunnable: Runnable? = null
    private var shareIntakeChannel: MethodChannel? = null
    private var documentStorageBridge: DocumentStorageBridge? = null
    private var calendarInsertBridge: CalendarInsertBridge? = null
    private var vaultRebuildBridge: VaultRebuildBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Fail closed before Flutter can render its first frame. The stored
        // value is intentionally non-sensitive because it must be available
        // before the vault, decoy vault, or lock screen is initialized.
        applySecureWindowProtection(readSecureWindowPreference())
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_OPEN_SHARED_TEXT) {
            shareIntakeChannel?.invokeMethod("pendingAvailable", null)
        }
        setIntent(
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
            },
        )
    }

    private var commercialLicenseBridge: CommercialLicenseBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        commercialLicenseBridge = try { CommercialLicenseBridge(this, flutterEngine.dartExecutor.binaryMessenger) } catch (_: Exception) { null }
        documentStorageBridge = DocumentStorageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        calendarInsertBridge = CalendarInsertBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        vaultRebuildBridge = VaultRebuildBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        configurePlatformLanguageChannel(flutterEngine)
        configureSensitiveClipboardChannel(flutterEngine)
        configureQuickUnlockChannel(flutterEngine)
        configureRecoveryDeviceSecretChannel(flutterEngine)
        configureUnlockClockChannel(flutterEngine)
        configureLauncherIconChannel(flutterEngine)
        configureScreenProtectionChannel(flutterEngine)
        configureNotificationReliabilityChannel(flutterEngine)
        configureTemporaryWebRuntimeChannel(flutterEngine)
        configureShareIntakeChannel(flutterEngine)
    }

    private fun configureShareIntakeChannel(flutterEngine: FlutterEngine) {
        shareIntakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_INTAKE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePending" -> {
                        val value = ShareIntakeStore.consume()
                        val errorCode = value?.get("errorCode") as? String
                        result.success(
                            if (errorCode == null) {
                                value
                            } else {
                                value + ("message" to localizedShareError(errorCode))
                            },
                        )
                    }
                    "clearPending" -> {
                        ShareIntakeStore.clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun localizedShareError(errorCode: String): String = when (errorCode) {
        ShareIntakeErrorCode.EXPIRED.name -> localizedString(R.string.share_error_expired)
        ShareIntakeErrorCode.TEXT_TOO_LONG.name ->
            localizedString(R.string.share_error_text_too_long)
        else -> localizedString(R.string.share_error_unsupported)
    }

    private fun configureTemporaryWebRuntimeChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TEMPORARY_WEB_RUNTIME_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        TemporaryWebForegroundService.start(applicationContext)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error(
                            "temporary_web_service_start_failed",
                            localizedString(R.string.temporary_web_service_start_failed),
                            null,
                        )
                    }
                }
                "stop" -> {
                    try {
                        TemporaryWebForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error(
                            "temporary_web_service_stop_failed",
                            localizedString(R.string.temporary_web_service_stop_failed),
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun configurePlatformLanguageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLATFORM_LANGUAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLanguage" -> {
                    val language = call.argument<String>("language")
                    if (language !in setOf(
                            LANGUAGE_SIMPLIFIED_CHINESE,
                            LANGUAGE_ENGLISH,
                            LANGUAGE_JAPANESE,
                        )
                    ) {
                        result.error(
                            "invalid_language",
                            localizedString(R.string.invalid_language),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    getSharedPreferences(LANGUAGE_PREFERENCES, Context.MODE_PRIVATE)
                        .edit()
                        .putString(PREF_LANGUAGE, language)
                        .apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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

    private fun configureNotificationReliabilityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_RELIABILITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> result.success(notificationReliabilityStatus())
                "openSettings" -> {
                    val target = call.argument<String>("target")
                    if (target == null) {
                        result.error(
                            "INVALID_NOTIFICATION_SETTINGS_TARGET",
                            localizedString(R.string.invalid_notification_settings_target),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    result.success(openNotificationSettings(target))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun lastSystemStopAt(): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(packageName, 0, 20)
                .filter {
                    it.reason == ApplicationExitInfo.REASON_USER_REQUESTED ||
                        it.reason == ApplicationExitInfo.REASON_USER_STOPPED
                }.maxOfOrNull { it.timestamp }
        } catch (_: Exception) { null }
    }

    private fun notificationReliabilityStatus(): Map<String, Any?> {
        val channelEnabled: Boolean?
        val channelImportance: Int?
        val channelSoundEnabled: Boolean?
        val channelVibrationEnabled: Boolean?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val reminderChannel = manager.getNotificationChannel(
                REMINDER_NOTIFICATION_CHANNEL_ID,
            )
            channelEnabled = reminderChannel?.let {
                it.importance != NotificationManager.IMPORTANCE_NONE
            }
            channelImportance = reminderChannel?.importance
            channelSoundEnabled = reminderChannel?.let { it.sound != null }
            channelVibrationEnabled = reminderChannel?.shouldVibrate()
        } else {
            channelEnabled = true
            channelImportance = null
            channelSoundEnabled = null
            channelVibrationEnabled = null
        }
        val batteryOptimizationExempt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
        val exactAlarmsAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
        val preferences = getSharedPreferences(
            ReminderReliabilityPreferences.FILE_NAME,
            Context.MODE_PRIVATE,
        )
        val recoveryAt = preferences.getLong(
            ReminderReliabilityPreferences.LAST_RECOVERY_AT,
            0L,
        )
        return mapOf(
            "applicationNotificationsEnabled" to
                NotificationManagerCompat.from(this).areNotificationsEnabled(),
            "reminderChannelEnabled" to channelEnabled,
            "reminderChannelImportance" to channelImportance,
            "reminderChannelSoundEnabled" to channelSoundEnabled,
            "reminderChannelVibrationEnabled" to channelVibrationEnabled,
            "batteryOptimizationExempt" to batteryOptimizationExempt,
            "exactAlarmsAllowed" to exactAlarmsAllowed,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidApiLevel" to Build.VERSION.SDK_INT,
            "lastSystemStopAtEpochMillis" to lastSystemStopAt(),
            "lastRecoveryAtEpochMillis" to recoveryAt.takeIf { it > 0L },
            "lastRecoveryTrigger" to preferences.getString(
                ReminderReliabilityPreferences.LAST_RECOVERY_TRIGGER,
                null,
            ),
            "lastRecoveryResult" to preferences.getString(
                ReminderReliabilityPreferences.LAST_RECOVERY_RESULT,
                null,
            ),
        )
    }

    private fun openNotificationSettings(target: String): Boolean {
        val opened = when (target) {
            "applicationNotifications" -> openApplicationNotificationSettings()
            "reminderChannel" -> openReminderChannelSettings()
            "batteryOptimization" -> openBatteryOptimizationSettings()
            "exactAlarms" -> openExactAlarmSettings()
            "vendorBackground" -> openVendorBackgroundSettings()
            else -> false
        }
        return opened || openApplicationDetailsSettings()
    }

    private fun openApplicationNotificationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return openApplicationDetailsSettings()
        }
        return startSettingsIntent(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            },
        )
    }

    private fun openReminderChannelSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return openApplicationNotificationSettings()
        }
        return startSettingsIntent(
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, REMINDER_NOTIFICATION_CHANNEL_ID)
            },
        )
    }

    private fun openBatteryOptimizationSettings(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startSettingsIntent(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } else {
            openApplicationDetailsSettings()
        }

    private fun openExactAlarmSettings(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            startSettingsIntent(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName"),
                ),
            )
        } else {
            openApplicationDetailsSettings()
        }

    private fun openVendorBackgroundSettings(): Boolean {
        for (componentName in vendorBackgroundComponents()) {
            val opened = startSettingsIntent(
                Intent().apply { component = componentName },
            )
            if (opened) return true
        }
        return false
    }

    private fun vendorBackgroundComponents(): List<ComponentName> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val flattened = when {
            manufacturer.contains("huawei") -> listOf(
                "com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager/.optimize.process.ProtectActivity",
            )
            manufacturer.contains("honor") -> listOf(
                "com.hihonor.systemmanager/.startupmgr.ui.StartupNormalAppListActivity",
            )
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> listOf(
                "com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity",
                "com.miui.powerkeeper/.ui.HiddenAppsConfigActivity",
            )
            manufacturer.contains("oppo") ||
                manufacturer.contains("oneplus") ||
                manufacturer.contains("realme") -> listOf(
                "com.coloros.safecenter/.startupapp.StartupAppListActivity",
                "com.oplus.battery/com.oplus.powermanager.fuelgaue.PowerUsageModelActivity",
            )
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> listOf(
                "com.vivo.permissionmanager/.activity.BgStartUpManagerActivity",
                "com.iqoo.secure/.ui.phoneoptimize.AddWhiteListActivity",
            )
            manufacturer.contains("samsung") -> listOf(
                "com.samsung.android.lool/com.samsung.android.sm.ui.battery.BatteryActivity",
            )
            else -> emptyList()
        }
        return flattened.mapNotNull(ComponentName::unflattenFromString)
    }

    private fun openApplicationDetailsSettings(): Boolean = startSettingsIntent(
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        ),
    )

    private fun startSettingsIntent(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun configureScreenProtectionChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_PROTECTION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSecureFlag" -> result.success(readSecureWindowPreference())
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error(
                            "INVALID_SECURE_FLAG",
                            localizedString(R.string.invalid_screen_protection_argument),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val committed = getSharedPreferences(
                        PRIVACY_PREFERENCES,
                        Context.MODE_PRIVATE,
                    ).edit()
                        .putBoolean(PREF_SECURE_WINDOW_ENABLED, enabled)
                        .commit()
                    if (!committed) {
                        result.error(
                            "SECURE_FLAG_SAVE_FAILED",
                            localizedString(R.string.screen_protection_save_failed),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    applySecureWindowProtection(enabled)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readSecureWindowPreference(): Boolean =
        getSharedPreferences(PRIVACY_PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(PREF_SECURE_WINDOW_ENABLED, true)

    private fun applySecureWindowProtection(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private val launcherAliases: LinkedHashMap<String, ComponentName>
        get() = linkedMapOf(
            LAUNCHER_CERAMIC_BLUE to ComponentName(
                this,
                "$packageName.launcher.CeramicBlueAlias",
            ),
            LAUNCHER_SAKURA_MIST to ComponentName(
                this,
                "$packageName.launcher.SakuraMistAlias",
            ),
            LAUNCHER_PAPER_ARCHIVE to ComponentName(
                this,
                "$packageName.launcher.PaperArchiveAlias",
            ),
            LAUNCHER_LILAC_MOON to ComponentName(
                this,
                "$packageName.launcher.LilacMoonAlias",
            ),
            LAUNCHER_GLACIER_BLUE to ComponentName(
                this,
                "$packageName.launcher.GlacierBlueAlias",
            ),
            LAUNCHER_MIST_CORAL to ComponentName(
                this,
                "$packageName.launcher.MistCoralAlias",
            ),
            LAUNCHER_NEON_ZERO to ComponentName(
                this,
                "$packageName.launcher.NeonZeroAlias",
            ),
            LAUNCHER_OBSIDIAN_GOLD to ComponentName(
                this,
                "$packageName.launcher.ObsidianGoldAlias",
            ),
            LEGACY_LAUNCHER_STANDARD to ComponentName(
                this,
                "$packageName.launcher.StandardAlias",
            ),
            LEGACY_LAUNCHER_PRIME to ComponentName(
                this,
                "$packageName.launcher.PrimeAlias",
            ),
            LEGACY_LAUNCHER_VIVID to ComponentName(
                this,
                "$packageName.launcher.VividAlias",
            ),
        )

    private fun configureLauncherIconChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAUNCHER_ICON_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLauncherIcon" -> {
                    val selected = call.argument<String>("variant")
                    if (selected == null || !launcherAliases.containsKey(selected)) {
                        result.error(
                            "INVALID_VARIANT",
                            localizedString(R.string.unknown_launcher_icon_color),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        setLauncherAlias(selected)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "ICON_SWITCH_FAILED",
                            localizedString(R.string.launcher_icon_switch_failed),
                            mapOf("exceptionType" to error.javaClass.simpleName),
                        )
                    }
                }
                "getLauncherIcon" -> {
                    try {
                        val enabled = enabledLauncherVariants(launcherAliases)
                        when (enabled.size) {
                            1 -> result.success(enabled.single())
                            0 -> result.error(
                                "NO_ENABLED_ALIAS",
                                localizedString(R.string.no_launcher_entry),
                                null,
                            )
                            else -> result.error(
                                "MULTIPLE_ENABLED_ALIASES",
                                localizedString(R.string.multiple_launcher_entries),
                                enabled,
                            )
                        }
                    } catch (error: Exception) {
                        result.error(
                            "ICON_STATE_READ_FAILED",
                            localizedString(R.string.launcher_icon_read_failed),
                            mapOf("exceptionType" to error.javaClass.simpleName),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setLauncherAlias(selected: String) {
        val aliases = launcherAliases
        require(aliases.containsKey(selected))
        val enabledBefore = enabledLauncherVariants(aliases)
        if (enabledBefore.size == 1 && enabledBefore.single() == selected) {
            return
        }
        val fallback = enabledBefore.singleOrNull()
            ?: enabledBefore.firstOrNull()
            ?: LAUNCHER_PAPER_ARCHIVE

        try {
            val selectedComponent = aliases.getValue(selected)
            setLauncherComponentEnabled(selectedComponent, enabled = true)
            check(isLauncherAliasEnabled(selected, selectedComponent)) {
                "Selected launcher alias was not enabled"
            }

            aliases.forEach { (variant, component) ->
                if (variant != selected) {
                    setLauncherComponentEnabled(component, enabled = false)
                }
            }

            check(enabledLauncherVariants(aliases) == listOf(selected)) {
                "Launcher alias invariant was not restored"
            }
        } catch (error: Exception) {
            restoreLauncherFallback(aliases, fallback)
            throw error
        }
    }

    private fun enabledLauncherVariants(
        aliases: LinkedHashMap<String, ComponentName>,
    ): List<String> = aliases.entries
        .filter { (variant, component) ->
            isLauncherAliasEnabled(variant, component)
        }
        .map { it.key }

    private fun isLauncherAliasEnabled(
        variant: String,
        component: ComponentName,
    ): Boolean = when (packageManager.getComponentEnabledSetting(component)) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED,
        -> false
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ->
            LAUNCHER_MANIFEST_DEFAULTS.getValue(variant)
        else -> false
    }

    private fun setLauncherComponentEnabled(
        component: ComponentName,
        enabled: Boolean,
    ) {
        packageManager.setComponentEnabledSetting(
            component,
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun restoreLauncherFallback(
        aliases: LinkedHashMap<String, ComponentName>,
        preferred: String,
    ) {
        val candidates = linkedSetOf<String>().apply {
            add(preferred)
            add(LAUNCHER_CERAMIC_BLUE)
            addAll(aliases.keys)
        }
        for (candidate in candidates) {
            val component = aliases[candidate] ?: continue
            val recovered = runCatching {
                setLauncherComponentEnabled(component, enabled = true)
                isLauncherAliasEnabled(candidate, component)
            }.getOrDefault(false)
            if (!recovered) {
                continue
            }
            aliases.forEach { (variant, otherComponent) ->
                if (variant != candidate) {
                    runCatching {
                        setLauncherComponentEnabled(otherComponent, enabled = false)
                    }
                }
            }
            return
        }
    }

    private fun configureSensitiveClipboardChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SENSITIVE_CLIPBOARD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "copySensitive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text")
            if (text.isNullOrEmpty()) {
                result.error(
                    "invalid_text",
                    localizedString(R.string.sensitive_text_empty),
                    null,
                )
                return@setMethodCallHandler
            }
            val requestedSeconds = call.argument<Int>("clearAfterSeconds") ?: 45
            val clearAfterSeconds = requestedSeconds.coerceIn(15, 120)
            copySensitiveText(text, clearAfterSeconds)
            result.success(null)
        }
    }

    private fun configureQuickUnlockChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QUICK_UNLOCK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isConfigured" -> result.success(isQuickUnlockV2Configured())
                "write" -> {
                    val encodedSecret = call.argument<String>("secret")
                    if (encodedSecret.isNullOrEmpty()) {
                        result.error(
                            "invalid_secret",
                            localizedString(R.string.invalid_quick_unlock_secret),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val secretBytes = encodedSecret.toByteArray(StandardCharsets.UTF_8)
                    if (secretBytes.size > MAX_SECRET_BYTES) {
                        secretBytes.fill(0)
                        result.error(
                            "invalid_secret",
                            localizedString(R.string.invalid_quick_unlock_secret),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    writeQuickUnlockV2(secretBytes, result)
                }
                "read" -> readQuickUnlockV2(result)
                "delete" -> deleteQuickUnlockV2(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun configureRecoveryDeviceSecretChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOVERY_DEVICE_SECRET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isConfigured" -> result.success(isRecoveryDeviceSecretV1Configured())
                "write" -> {
                    val encodedPayload = call.argument<String>("payload")
                    if (encodedPayload.isNullOrEmpty()) {
                        result.error(
                            "invalid_secret",
                            localizedString(R.string.invalid_recovery_secret),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val payloadBytes = encodedPayload.toByteArray(StandardCharsets.UTF_8)
                    if (payloadBytes.size > RECOVERY_DEVICE_SECRET_MAX_BYTES) {
                        payloadBytes.fill(0)
                        result.error(
                            "invalid_secret",
                            localizedString(R.string.invalid_recovery_secret),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    if (!isValidRecoveryDeviceSecretPayload(encodedPayload)) {
                        payloadBytes.fill(0)
                        result.error(
                            "invalid_secret",
                            localizedString(R.string.invalid_recovery_secret),
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    writeRecoveryDeviceSecretV1(payloadBytes, result)
                }
                "read" -> readRecoveryDeviceSecretV1(result)
                "delete" -> deleteRecoveryDeviceSecretV1(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun isValidRecoveryDeviceSecretPayload(encodedPayload: String): Boolean {
        val payload = try {
            JSONObject(encodedPayload)
        } catch (_: Exception) {
            return false
        }
        val keys = mutableSetOf<String>()
        val keyIterator = payload.keys()
        while (keyIterator.hasNext()) {
            keys.add(keyIterator.next())
        }
        if (keys != RECOVERY_DEVICE_SECRET_PAYLOAD_KEYS ||
            payload.opt("version") != RECOVERY_DEVICE_SECRET_VERSION
        ) {
            return false
        }
        for (metadataKey in listOf("vaultInstanceId", "slotId", "deviceBindingId")) {
            val value = payload.opt(metadataKey)
            if (value !is String ||
                value.isEmpty() ||
                value.toByteArray(StandardCharsets.UTF_8).size >
                RECOVERY_DEVICE_SECRET_MAX_METADATA_BYTES
            ) {
                return false
            }
        }
        val encodedSecret = payload.opt("deviceSecret") as? String ?: return false
        val decodedSecret = try {
            Base64.decode(encodedSecret, Base64.NO_WRAP)
        } catch (_: Exception) {
            return false
        }
        return try {
            decodedSecret.size == 32
        } finally {
            decodedSecret.fill(0)
        }
    }

    private fun configureUnlockClockChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UNLOCK_CLOCK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(
                    mapOf(
                        "bootCount" to Settings.Global.getInt(
                            contentResolver,
                            Settings.Global.BOOT_COUNT,
                            0,
                        ),
                        "elapsedRealtimeMilliseconds" to SystemClock.elapsedRealtime(),
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    /** Reads only a non-sensitive marker. This method never touches KeyStore. */
    private fun isQuickUnlockV2Configured(): Boolean {
        val preferences = getSharedPreferences(QUICK_UNLOCK_PREFS, Context.MODE_PRIVATE)
        return preferences.getBoolean(PREF_CONFIGURED, false) &&
            preferences.getInt(PREF_VERSION, 0) == QUICK_UNLOCK_VERSION
    }

    private fun writeQuickUnlockV2(
        secretBytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (activeQuickUnlockOperationId != null) {
            secretBytes.fill(0)
            result.error(
                "auth_in_progress",
                localizedString(R.string.biometric_auth_in_progress),
                null,
            )
            return
        }
        // Enabling is a replacement transaction. Never reuse a key left by a
        // cancelled, invalidated, or partially committed earlier attempt.
        if (!clearQuickUnlockV2State()) {
            secretBytes.fill(0)
            result.error(
                "key_cleanup_failed",
                localizedString(R.string.quick_unlock_cleanup_failed),
                diagnosticDetails("key_cleanup"),
            )
            return
        }
        if (!ensureStrongBiometricAvailable(result)) {
            secretBytes.fill(0)
            return
        }
        val freshKey = try {
            createFreshQuickUnlockV2Key()
        } catch (error: Exception) {
            secretBytes.fill(0)
            clearQuickUnlockV2State()
            result.error(
                "key_generation_failed",
                localizedString(R.string.biometric_key_create_failed),
                diagnosticDetails("key_generation", error),
            )
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.ENCRYPT_MODE, freshKey)
            }
        } catch (error: Exception) {
            secretBytes.fill(0)
            clearQuickUnlockV2State()
            result.error(
                "cipher_init_failed",
                localizedString(R.string.biometric_encrypt_init_failed),
                diagnosticDetails("cipher_init", error),
            )
            return
        }

        var writeCommitted = false
        authenticateWithCipher(
            cipher = cipher,
            result = result,
            cleanup = {
                secretBytes.fill(0)
                if (!writeCommitted) {
                    clearQuickUnlockV2State()
                }
            },
        ) { authenticatedCipher, channelResult ->
            try {
                val ciphertext = authenticatedCipher.doFinal(secretBytes)
                val iv = authenticatedCipher.iv
                val committed = getSharedPreferences(
                    QUICK_UNLOCK_PREFS,
                    Context.MODE_PRIVATE,
                ).edit()
                    .putInt(PREF_VERSION, QUICK_UNLOCK_VERSION)
                    .putString(PREF_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                    .putString(PREF_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
                    .putBoolean(PREF_CONFIGURED, true)
                    .commit()
                ciphertext.fill(0)
                if (!committed) {
                    clearQuickUnlockV2State()
                    channelResult.error(
                        "storage_error",
                        localizedString(R.string.quick_unlock_save_failed),
                        null,
                    )
                } else {
                    writeCommitted = true
                    channelResult.success(null)
                }
            } catch (error: Exception) {
                clearQuickUnlockV2State()
                completeCryptoOperationError(error, channelResult)
            }
        }
    }

    private fun readQuickUnlockV2(result: MethodChannel.Result) {
        val preferences = getSharedPreferences(QUICK_UNLOCK_PREFS, Context.MODE_PRIVATE)
        if (!isQuickUnlockV2Configured()) {
            result.error(
                "not_configured",
                localizedString(R.string.quick_unlock_not_configured),
                null,
            )
            return
        }
        if (!ensureStrongBiometricAvailable(result)) {
            return
        }

        val ciphertext = try {
            Base64.decode(preferences.getString(PREF_CIPHERTEXT, null), Base64.NO_WRAP)
        } catch (_: Exception) {
            result.error(
                "corrupted_secret",
                localizedString(R.string.quick_unlock_secret_corrupted),
                null,
            )
            return
        }
        val iv = try {
            Base64.decode(preferences.getString(PREF_IV, null), Base64.NO_WRAP)
        } catch (_: Exception) {
            ciphertext.fill(0)
            result.error(
                "corrupted_secret",
                localizedString(R.string.quick_unlock_secret_corrupted),
                null,
            )
            return
        }
        if (ciphertext.isEmpty() || iv.size !in 12..16) {
            ciphertext.fill(0)
            iv.fill(0)
            result.error(
                "corrupted_secret",
                localizedString(R.string.quick_unlock_secret_corrupted),
                null,
            )
            return
        }

        val existingKey = try {
            getExistingQuickUnlockV2Key()
        } catch (error: Exception) {
            ciphertext.fill(0)
            iv.fill(0)
            completeKeyLoadError(error, result)
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(
                    Cipher.DECRYPT_MODE,
                    existingKey,
                    GCMParameterSpec(GCM_TAG_BITS, iv),
                )
            }
        } catch (error: Exception) {
            ciphertext.fill(0)
            iv.fill(0)
            if (error is KeyPermanentlyInvalidatedException) {
                result.error(
                    "key_invalidated",
                    localizedString(R.string.biometric_key_invalidated),
                    diagnosticDetails("cipher_init", error),
                )
            } else {
                result.error(
                    "cipher_init_failed",
                    localizedString(R.string.biometric_decrypt_init_failed),
                    diagnosticDetails("cipher_init", error),
                )
            }
            return
        }
        iv.fill(0)

        authenticateWithCipher(
            cipher = cipher,
            result = result,
            cleanup = { ciphertext.fill(0) },
        ) { authenticatedCipher, channelResult ->
            var plaintext: ByteArray? = null
            try {
                plaintext = authenticatedCipher.doFinal(ciphertext)
                channelResult.success(String(plaintext, StandardCharsets.UTF_8))
            } catch (error: Exception) {
                completeCryptoOperationError(error, channelResult)
            } finally {
                plaintext?.fill(0)
            }
        }
    }

    /** Removes v2 state without decrypting it or authenticating the old user. */
    private fun deleteQuickUnlockV2(result: MethodChannel.Result) {
        if (activeQuickUnlockOperationId != null) {
            result.error(
                "auth_in_progress",
                localizedString(R.string.biometric_auth_in_progress),
                null,
            )
            return
        }
        if (!clearQuickUnlockV2State()) {
            result.error(
                "key_cleanup_failed",
                localizedString(R.string.quick_unlock_remove_failed),
                diagnosticDetails("key_cleanup"),
            )
        } else {
            result.success(null)
        }
    }

    private fun clearQuickUnlockV2State(): Boolean {
        val preferencesCleared = getSharedPreferences(
            QUICK_UNLOCK_PREFS,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        var keyCleared = true
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(QUICK_UNLOCK_KEY_ALIAS)) {
                keyStore.deleteEntry(QUICK_UNLOCK_KEY_ALIAS)
            }
        } catch (_: Exception) {
            keyCleared = false
        }
        return preferencesCleared && keyCleared
    }

    private fun createFreshQuickUnlockV2Key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(QUICK_UNLOCK_KEY_ALIAS)) {
            keyStore.deleteEntry(QUICK_UNLOCK_KEY_ALIAS)
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val builder = KeyGenParameterSpec.Builder(
            QUICK_UNLOCK_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun getExistingQuickUnlockV2Key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return keyStore.getKey(QUICK_UNLOCK_KEY_ALIAS, null) as? SecretKey
            ?: throw QuickUnlockKeyMissingException()
    }

    /** Reads only a non-sensitive marker. This method never touches KeyStore. */
    private fun isRecoveryDeviceSecretV1Configured(): Boolean {
        val preferences = getSharedPreferences(
            RECOVERY_DEVICE_SECRET_PREFS,
            Context.MODE_PRIVATE,
        )
        return preferences.getBoolean(RECOVERY_DEVICE_SECRET_PREF_CONFIGURED, false) &&
            preferences.getInt(
                RECOVERY_DEVICE_SECRET_PREF_VERSION,
                0,
            ) == RECOVERY_DEVICE_SECRET_VERSION
    }

    private fun writeRecoveryDeviceSecretV1(
        payloadBytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (activeRecoveryDeviceSecretOperationId != null) {
            payloadBytes.fill(0)
            result.error(
                "auth_in_progress",
                localizedString(R.string.recovery_auth_in_progress),
                null,
            )
            return
        }
        if (!ensureStrongBiometricAvailable(result)) {
            payloadBytes.fill(0)
            return
        }

        // A configured write reuses its dedicated Keystore key, so the old
        // ciphertext remains readable until the new preferences commit wins.
        val replacingConfiguredSecret = isRecoveryDeviceSecretV1Configured()
        val recoveryKey = try {
            if (replacingConfiguredSecret) {
                getExistingRecoveryDeviceSecretV1Key()
            } else {
                if (!clearRecoveryDeviceSecretV1State()) {
                    throw RecoveryDeviceSecretCleanupException()
                }
                createFreshRecoveryDeviceSecretV1Key()
            }
        } catch (error: Exception) {
            payloadBytes.fill(0)
            if (error is RecoveryDeviceSecretCleanupException) {
                result.error(
                    "key_cleanup_failed",
                    localizedString(R.string.recovery_cleanup_failed),
                    diagnosticDetails("recovery_device_secret_key_cleanup", error),
                )
            } else if (replacingConfiguredSecret) {
                completeRecoveryDeviceSecretKeyLoadError(error, result)
            } else {
                clearRecoveryDeviceSecretV1State()
                result.error(
                    "key_generation_failed",
                    localizedString(R.string.recovery_key_create_failed),
                    diagnosticDetails("recovery_device_secret_key_generation", error),
                )
            }
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.ENCRYPT_MODE, recoveryKey)
            }
        } catch (error: Exception) {
            payloadBytes.fill(0)
            if (!replacingConfiguredSecret) {
                clearRecoveryDeviceSecretV1State()
            }
            result.error(
                if (error is KeyPermanentlyInvalidatedException) {
                    "key_invalidated"
                } else {
                    "cipher_init_failed"
                },
                localizedString(R.string.recovery_encrypt_init_failed),
                diagnosticDetails("recovery_device_secret_cipher_init", error),
            )
            return
        }

        var writeCommitted = false
        authenticateRecoveryDeviceSecretWithCipher(
            cipher = cipher,
            result = result,
            cleanup = {
                payloadBytes.fill(0)
                if (!writeCommitted && !replacingConfiguredSecret) {
                    clearRecoveryDeviceSecretV1State()
                }
            },
        ) { authenticatedCipher, channelResult ->
            try {
                val ciphertext = authenticatedCipher.doFinal(payloadBytes)
                val iv = authenticatedCipher.iv
                val committed = getSharedPreferences(
                    RECOVERY_DEVICE_SECRET_PREFS,
                    Context.MODE_PRIVATE,
                ).edit()
                    .putInt(
                        RECOVERY_DEVICE_SECRET_PREF_VERSION,
                        RECOVERY_DEVICE_SECRET_VERSION,
                    )
                    .putString(
                        RECOVERY_DEVICE_SECRET_PREF_CIPHERTEXT,
                        Base64.encodeToString(ciphertext, Base64.NO_WRAP),
                    )
                    .putString(
                        RECOVERY_DEVICE_SECRET_PREF_IV,
                        Base64.encodeToString(iv, Base64.NO_WRAP),
                    )
                    .putBoolean(RECOVERY_DEVICE_SECRET_PREF_CONFIGURED, true)
                    .commit()
                ciphertext.fill(0)
                if (!committed) {
                    if (!replacingConfiguredSecret) {
                        clearRecoveryDeviceSecretV1State()
                    }
                    channelResult.error(
                        "storage_error",
                        localizedString(R.string.recovery_save_failed),
                        null,
                    )
                } else {
                    writeCommitted = true
                    channelResult.success(null)
                }
            } catch (error: Exception) {
                if (!replacingConfiguredSecret) {
                    clearRecoveryDeviceSecretV1State()
                }
                completeRecoveryDeviceSecretCryptoOperationError(error, channelResult)
            }
        }
    }

    private fun readRecoveryDeviceSecretV1(result: MethodChannel.Result) {
        val preferences = getSharedPreferences(
            RECOVERY_DEVICE_SECRET_PREFS,
            Context.MODE_PRIVATE,
        )
        if (!isRecoveryDeviceSecretV1Configured()) {
            result.error(
                "not_configured",
                localizedString(R.string.recovery_not_configured),
                null,
            )
            return
        }
        if (!ensureStrongBiometricAvailable(result)) {
            return
        }

        val ciphertext = try {
            Base64.decode(
                preferences.getString(RECOVERY_DEVICE_SECRET_PREF_CIPHERTEXT, null),
                Base64.NO_WRAP,
            )
        } catch (_: Exception) {
            result.error(
                "corrupted_secret",
                localizedString(R.string.recovery_secret_corrupted),
                null,
            )
            return
        }
        val iv = try {
            Base64.decode(
                preferences.getString(RECOVERY_DEVICE_SECRET_PREF_IV, null),
                Base64.NO_WRAP,
            )
        } catch (_: Exception) {
            ciphertext.fill(0)
            result.error(
                "corrupted_secret",
                localizedString(R.string.recovery_secret_corrupted),
                null,
            )
            return
        }
        if (
            ciphertext.isEmpty() ||
            ciphertext.size > RECOVERY_DEVICE_SECRET_MAX_BYTES + 32 ||
            iv.size !in 12..16
        ) {
            ciphertext.fill(0)
            iv.fill(0)
            result.error(
                "corrupted_secret",
                localizedString(R.string.recovery_secret_corrupted),
                null,
            )
            return
        }

        val existingKey = try {
            getExistingRecoveryDeviceSecretV1Key()
        } catch (error: Exception) {
            ciphertext.fill(0)
            iv.fill(0)
            completeRecoveryDeviceSecretKeyLoadError(error, result)
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(
                    Cipher.DECRYPT_MODE,
                    existingKey,
                    GCMParameterSpec(GCM_TAG_BITS, iv),
                )
            }
        } catch (error: Exception) {
            ciphertext.fill(0)
            iv.fill(0)
            if (error is KeyPermanentlyInvalidatedException) {
                result.error(
                    "key_invalidated",
                    localizedString(R.string.recovery_key_invalidated),
                    diagnosticDetails("recovery_device_secret_cipher_init", error),
                )
            } else {
                result.error(
                    "cipher_init_failed",
                    localizedString(R.string.recovery_decrypt_init_failed),
                    diagnosticDetails("recovery_device_secret_cipher_init", error),
                )
            }
            return
        }
        iv.fill(0)

        authenticateRecoveryDeviceSecretWithCipher(
            cipher = cipher,
            result = result,
            cleanup = { ciphertext.fill(0) },
        ) { authenticatedCipher, channelResult ->
            var plaintext: ByteArray? = null
            try {
                plaintext = authenticatedCipher.doFinal(ciphertext)
                channelResult.success(String(plaintext, StandardCharsets.UTF_8))
            } catch (error: Exception) {
                completeRecoveryDeviceSecretCryptoOperationError(error, channelResult)
            } finally {
                plaintext?.fill(0)
            }
        }
    }

    /** Removes configured recovery state only after a fresh strong biometric. */
    private fun deleteRecoveryDeviceSecretV1(result: MethodChannel.Result) {
        if (activeRecoveryDeviceSecretOperationId != null) {
            result.error(
                "auth_in_progress",
                localizedString(R.string.recovery_auth_in_progress),
                null,
            )
            return
        }
        if (!isRecoveryDeviceSecretV1Configured()) {
            if (clearRecoveryDeviceSecretV1State()) {
                result.success(null)
            } else {
                result.error(
                    "key_cleanup_failed",
                    localizedString(R.string.recovery_cleanup_failed),
                    diagnosticDetails("recovery_device_secret_key_cleanup"),
                )
            }
            return
        }
        val existingKey = try {
            getExistingRecoveryDeviceSecretV1Key()
        } catch (error: Exception) {
            if (error is RecoveryDeviceSecretKeyMissingException &&
                clearRecoveryDeviceSecretV1State()
            ) {
                result.success(null)
            } else {
                completeRecoveryDeviceSecretKeyLoadError(error, result)
            }
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.ENCRYPT_MODE, existingKey)
            }
        } catch (error: Exception) {
            if (error is KeyPermanentlyInvalidatedException &&
                clearRecoveryDeviceSecretV1State()
            ) {
                result.success(null)
            } else {
                result.error(
                    if (error is KeyPermanentlyInvalidatedException) {
                        "key_cleanup_failed"
                    } else {
                        "cipher_init_failed"
                    },
                    localizedString(R.string.recovery_auth_init_failed),
                    diagnosticDetails("recovery_device_secret_delete_cipher_init", error),
                )
            }
            return
        }
        if (!ensureStrongBiometricAvailable(result)) {
            return
        }
        authenticateRecoveryDeviceSecretWithCipher(
            cipher = cipher,
            result = result,
            cleanup = {},
        ) { _, channelResult ->
            if (clearRecoveryDeviceSecretV1State()) {
                channelResult.success(null)
            } else {
                channelResult.error(
                    "key_cleanup_failed",
                    localizedString(R.string.recovery_remove_failed),
                    diagnosticDetails("recovery_device_secret_key_cleanup"),
                )
            }
        }
    }

    private fun clearRecoveryDeviceSecretV1State(): Boolean {
        val preferencesCleared = getSharedPreferences(
            RECOVERY_DEVICE_SECRET_PREFS,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        var keyCleared = true
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(RECOVERY_DEVICE_SECRET_KEY_ALIAS)) {
                keyStore.deleteEntry(RECOVERY_DEVICE_SECRET_KEY_ALIAS)
            }
        } catch (_: Exception) {
            keyCleared = false
        }
        return preferencesCleared && keyCleared
    }

    private fun createFreshRecoveryDeviceSecretV1Key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        check(!keyStore.containsAlias(RECOVERY_DEVICE_SECRET_KEY_ALIAS))

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val builder = KeyGenParameterSpec.Builder(
            RECOVERY_DEVICE_SECRET_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun getExistingRecoveryDeviceSecretV1Key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return keyStore.getKey(RECOVERY_DEVICE_SECRET_KEY_ALIAS, null) as? SecretKey
            ?: throw RecoveryDeviceSecretKeyMissingException()
    }

    private fun ensureStrongBiometricAvailable(result: MethodChannel.Result): Boolean {
        val status = BiometricManager.from(this).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG,
        )
        return when (status) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> {
                result.error(
                    "not_enrolled",
                    localizedString(R.string.biometric_not_enrolled),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> {
                result.error(
                    "hardware_unavailable",
                    localizedString(R.string.biometric_hardware_unavailable),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> {
                result.error(
                    "unavailable",
                    localizedString(R.string.biometric_unsupported),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> {
                result.error(
                    "biometric_security_update_required",
                    localizedString(R.string.biometric_sensor_disabled),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED -> {
                result.error(
                    "biometric_unsupported",
                    localizedString(R.string.biometric_configuration_unsupported),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN -> {
                result.error(
                    "biometric_status_unknown",
                    localizedString(R.string.biometric_status_unknown),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
            else -> {
                result.error(
                    "biometric_unavailable",
                    localizedString(R.string.biometric_unavailable),
                    diagnosticDetails("can_authenticate", status = status),
                )
                false
            }
        }
    }

    private fun authenticateWithCipher(
        cipher: Cipher,
        result: MethodChannel.Result,
        cleanup: () -> Unit,
        onAuthenticated: (Cipher, MethodChannel.Result) -> Unit,
    ) {
        if (activeQuickUnlockOperationId != null) {
            cleanup()
            result.error(
                "auth_in_progress",
                localizedString(R.string.biometric_auth_in_progress),
                null,
            )
            return
        }

        val operationId = ++nextQuickUnlockOperationId
        activeQuickUnlockOperationId = operationId
        activeQuickUnlockResult = result
        activeQuickUnlockCleanup = cleanup
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    val authenticatedCipher = authenticationResult.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        completeQuickUnlockOperation(
                            operationId,
                            cleanupBeforeCompletion = true,
                        ) { channelResult ->
                            channelResult.error(
                                "crypto_error",
                                localizedString(R.string.biometric_key_result_missing),
                                null,
                            )
                        }
                        return
                    }
                    completeQuickUnlockOperation(operationId) { channelResult ->
                        onAuthenticated(authenticatedCipher, channelResult)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    completeQuickUnlockOperation(
                        operationId,
                        cleanupBeforeCompletion = true,
                    ) { channelResult ->
                        val mapped = mapBiometricError(errorCode)
                        channelResult.error(mapped.first, mapped.second, null)
                    }
                }

                override fun onAuthenticationFailed() {
                    // The system prompt stays open and permits another biometric attempt.
                }
            },
        )
        activeQuickUnlockPrompt = prompt

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(localizedString(R.string.quick_unlock_prompt_title))
            .setSubtitle(localizedString(R.string.biometric_prompt_subtitle))
            .setNegativeButtonText(localizedString(R.string.use_master_password))
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        startBiometricPromptWhenReady(
            operationId = operationId,
            prompt = prompt,
            promptInfo = promptInfo,
            cipher = cipher,
            attemptsRemaining = PROMPT_READY_MAX_ATTEMPTS,
        )
    }

    private fun startBiometricPromptWhenReady(
        operationId: Long,
        prompt: BiometricPrompt,
        promptInfo: BiometricPrompt.PromptInfo,
        cipher: Cipher,
        attemptsRemaining: Int,
    ) {
        if (activeQuickUnlockOperationId != operationId) {
            return
        }
        activeQuickUnlockLaunchRunnable = null
        val activityReady = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
            !supportFragmentManager.isStateSaved
        if (!activityReady) {
            if (attemptsRemaining <= 0) {
                completeQuickUnlockOperation(
                    operationId,
                    cleanupBeforeCompletion = true,
                ) { channelResult ->
                    channelResult.error(
                        "activity_not_resumed",
                        localizedString(R.string.biometric_activity_not_ready),
                        diagnosticDetails("activity_ready"),
                    )
                }
                return
            }
            val launchRunnable = Runnable {
                startBiometricPromptWhenReady(
                    operationId = operationId,
                    prompt = prompt,
                    promptInfo = promptInfo,
                    cipher = cipher,
                    attemptsRemaining = attemptsRemaining - 1,
                )
            }
            activeQuickUnlockLaunchRunnable = launchRunnable
            mainHandler.postDelayed(launchRunnable, PROMPT_READY_RETRY_DELAY_MS)
            return
        }

        val timeoutRunnable = Runnable {
            if (activeQuickUnlockOperationId != operationId) {
                return@Runnable
            }
            completeQuickUnlockOperation(
                operationId,
                cleanupBeforeCompletion = true,
            ) { channelResult ->
                channelResult.error(
                    "prompt_timeout",
                    localizedString(R.string.biometric_prompt_timeout),
                    diagnosticDetails("prompt_timeout"),
                )
            }
            prompt.cancelAuthentication()
        }
        activeQuickUnlockTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, PROMPT_TIMEOUT_MS)

        try {
            prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
        } catch (error: Exception) {
            completeQuickUnlockOperation(
                operationId,
                cleanupBeforeCompletion = true,
            ) { channelResult ->
                channelResult.error(
                    "prompt_start_failed",
                    localizedString(R.string.biometric_prompt_start_failed),
                    diagnosticDetails("prompt_start", error),
                )
            }
        }
    }

    private fun completeQuickUnlockOperation(
        operationId: Long,
        cleanupBeforeCompletion: Boolean = false,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        if (activeQuickUnlockOperationId != operationId) {
            return
        }
        val result = activeQuickUnlockResult ?: return
        val cleanup = activeQuickUnlockCleanup ?: {}
        activeQuickUnlockLaunchRunnable?.let(mainHandler::removeCallbacks)
        activeQuickUnlockTimeoutRunnable?.let(mainHandler::removeCallbacks)
        activeQuickUnlockOperationId = null
        activeQuickUnlockPrompt = null
        activeQuickUnlockResult = null
        activeQuickUnlockCleanup = null
        activeQuickUnlockLaunchRunnable = null
        activeQuickUnlockTimeoutRunnable = null
        if (cleanupBeforeCompletion) {
            try {
                cleanup()
            } finally {
                completion(result)
            }
        } else {
            try {
                completion(result)
            } finally {
                cleanup()
            }
        }
    }

    private fun authenticateRecoveryDeviceSecretWithCipher(
        cipher: Cipher,
        result: MethodChannel.Result,
        cleanup: () -> Unit,
        onAuthenticated: (Cipher, MethodChannel.Result) -> Unit,
    ) {
        if (activeRecoveryDeviceSecretOperationId != null) {
            cleanup()
            result.error(
                "auth_in_progress",
                localizedString(R.string.recovery_auth_in_progress),
                null,
            )
            return
        }

        val operationId = ++nextRecoveryDeviceSecretOperationId
        activeRecoveryDeviceSecretOperationId = operationId
        activeRecoveryDeviceSecretResult = result
        activeRecoveryDeviceSecretCleanup = cleanup
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    val authenticatedCipher = authenticationResult.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        completeRecoveryDeviceSecretOperation(
                            operationId,
                            cleanupBeforeCompletion = true,
                        ) { channelResult ->
                            channelResult.error(
                                "crypto_error",
                                localizedString(R.string.recovery_key_result_missing),
                                null,
                            )
                        }
                        return
                    }
                    completeRecoveryDeviceSecretOperation(operationId) { channelResult ->
                        onAuthenticated(authenticatedCipher, channelResult)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    completeRecoveryDeviceSecretOperation(
                        operationId,
                        cleanupBeforeCompletion = true,
                    ) { channelResult ->
                        val mapped = mapBiometricError(errorCode)
                        channelResult.error(mapped.first, mapped.second, null)
                    }
                }

                override fun onAuthenticationFailed() {
                    // The system prompt remains open for another strong biometric attempt.
                }
            },
        )
        activeRecoveryDeviceSecretPrompt = prompt

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(localizedString(R.string.recovery_prompt_title))
            .setSubtitle(localizedString(R.string.biometric_prompt_subtitle))
            .setNegativeButtonText(localizedString(R.string.cancel))
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        startRecoveryDeviceSecretPromptWhenReady(
            operationId = operationId,
            prompt = prompt,
            promptInfo = promptInfo,
            cipher = cipher,
            attemptsRemaining = PROMPT_READY_MAX_ATTEMPTS,
        )
    }

    private fun startRecoveryDeviceSecretPromptWhenReady(
        operationId: Long,
        prompt: BiometricPrompt,
        promptInfo: BiometricPrompt.PromptInfo,
        cipher: Cipher,
        attemptsRemaining: Int,
    ) {
        if (activeRecoveryDeviceSecretOperationId != operationId) {
            return
        }
        activeRecoveryDeviceSecretLaunchRunnable = null
        val activityReady = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
            !supportFragmentManager.isStateSaved
        if (!activityReady) {
            if (attemptsRemaining <= 0) {
                completeRecoveryDeviceSecretOperation(
                    operationId,
                    cleanupBeforeCompletion = true,
                ) { channelResult ->
                    channelResult.error(
                        "activity_not_resumed",
                        localizedString(R.string.biometric_activity_not_ready),
                        diagnosticDetails("recovery_device_secret_activity_ready"),
                    )
                }
                return
            }
            val launchRunnable = Runnable {
                startRecoveryDeviceSecretPromptWhenReady(
                    operationId = operationId,
                    prompt = prompt,
                    promptInfo = promptInfo,
                    cipher = cipher,
                    attemptsRemaining = attemptsRemaining - 1,
                )
            }
            activeRecoveryDeviceSecretLaunchRunnable = launchRunnable
            mainHandler.postDelayed(launchRunnable, PROMPT_READY_RETRY_DELAY_MS)
            return
        }

        val timeoutRunnable = Runnable {
            if (activeRecoveryDeviceSecretOperationId != operationId) {
                return@Runnable
            }
            completeRecoveryDeviceSecretOperation(
                operationId,
                cleanupBeforeCompletion = true,
            ) { channelResult ->
                channelResult.error(
                    "prompt_timeout",
                    localizedString(R.string.biometric_prompt_timeout),
                    diagnosticDetails("recovery_device_secret_prompt_timeout"),
                )
            }
            prompt.cancelAuthentication()
        }
        activeRecoveryDeviceSecretTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, PROMPT_TIMEOUT_MS)

        try {
            prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
        } catch (error: Exception) {
            completeRecoveryDeviceSecretOperation(
                operationId,
                cleanupBeforeCompletion = true,
            ) { channelResult ->
                channelResult.error(
                    "prompt_start_failed",
                    localizedString(R.string.biometric_prompt_start_failed),
                    diagnosticDetails("recovery_device_secret_prompt_start", error),
                )
            }
        }
    }

    private fun completeRecoveryDeviceSecretOperation(
        operationId: Long,
        cleanupBeforeCompletion: Boolean = false,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        if (activeRecoveryDeviceSecretOperationId != operationId) {
            return
        }
        val result = activeRecoveryDeviceSecretResult ?: return
        val cleanup = activeRecoveryDeviceSecretCleanup ?: {}
        activeRecoveryDeviceSecretLaunchRunnable?.let(mainHandler::removeCallbacks)
        activeRecoveryDeviceSecretTimeoutRunnable?.let(mainHandler::removeCallbacks)
        activeRecoveryDeviceSecretOperationId = null
        activeRecoveryDeviceSecretPrompt = null
        activeRecoveryDeviceSecretResult = null
        activeRecoveryDeviceSecretCleanup = null
        activeRecoveryDeviceSecretLaunchRunnable = null
        activeRecoveryDeviceSecretTimeoutRunnable = null
        if (cleanupBeforeCompletion) {
            try {
                cleanup()
            } finally {
                completion(result)
            }
        } else {
            try {
                completion(result)
            } finally {
                cleanup()
            }
        }
    }

    private fun mapBiometricError(errorCode: Int): Pair<String, String> = when (errorCode) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        -> "user_canceled" to localizedString(R.string.biometric_canceled)
        BiometricPrompt.ERROR_LOCKOUT ->
            "temporary_lockout" to localizedString(R.string.biometric_temporary_lockout)
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
            "biometric_lockout" to localizedString(R.string.biometric_lockout)
        BiometricPrompt.ERROR_NO_BIOMETRICS ->
            "not_enrolled" to localizedString(R.string.biometric_not_enrolled)
        BiometricPrompt.ERROR_HW_UNAVAILABLE ->
            "hardware_unavailable" to localizedString(R.string.biometric_hardware_unavailable)
        BiometricPrompt.ERROR_HW_NOT_PRESENT ->
            "unavailable" to localizedString(R.string.biometric_unsupported)
        BiometricPrompt.ERROR_TIMEOUT ->
            "timeout" to localizedString(R.string.biometric_timed_out)
        BiometricPrompt.ERROR_CANCELED ->
            "lifecycle_canceled" to localizedString(R.string.biometric_lifecycle_canceled)
        BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED ->
            "biometric_security_update_required" to localizedString(R.string.biometric_sensor_disabled)
        BiometricPrompt.ERROR_UNABLE_TO_PROCESS ->
            "biometric_unable_to_process" to localizedString(R.string.biometric_unable_to_process)
        BiometricPrompt.ERROR_NO_SPACE ->
            "biometric_no_space" to localizedString(R.string.biometric_no_space)
        BiometricPrompt.ERROR_VENDOR ->
            "biometric_vendor_error" to localizedString(R.string.biometric_vendor_error)
        else -> "biometric_error" to localizedString(R.string.biometric_incomplete)
    }

    private fun completeKeyLoadError(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        when (error) {
            is KeyPermanentlyInvalidatedException -> result.error(
                "key_invalidated",
                localizedString(R.string.biometric_key_invalidated),
                diagnosticDetails("key_load", error),
            )
            is QuickUnlockKeyMissingException -> result.error(
                "key_missing",
                localizedString(R.string.biometric_key_missing),
                diagnosticDetails("key_load", error),
            )
            else -> result.error(
                "key_load_failed",
                localizedString(R.string.biometric_key_read_failed),
                diagnosticDetails("key_load", error),
            )
        }
    }

    private fun completeCryptoOperationError(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        when (error) {
            is KeyPermanentlyInvalidatedException -> result.error(
                "key_invalidated",
                localizedString(R.string.biometric_key_invalidated),
                diagnosticDetails("crypto_operation", error),
            )
            is AEADBadTagException -> result.error(
                "corrupted_secret",
                localizedString(R.string.quick_unlock_secret_corrupted),
                diagnosticDetails("crypto_operation", error),
            )
            else -> result.error(
                "crypto_error",
                localizedString(R.string.quick_unlock_process_failed),
                diagnosticDetails("crypto_operation", error),
            )
        }
    }

    private fun completeRecoveryDeviceSecretKeyLoadError(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        when (error) {
            is KeyPermanentlyInvalidatedException -> result.error(
                "key_invalidated",
                localizedString(R.string.recovery_key_invalidated),
                diagnosticDetails("recovery_device_secret_key_load", error),
            )
            is RecoveryDeviceSecretKeyMissingException -> result.error(
                "key_missing",
                localizedString(R.string.recovery_key_missing),
                diagnosticDetails("recovery_device_secret_key_load", error),
            )
            else -> result.error(
                "key_load_failed",
                localizedString(R.string.recovery_key_read_failed),
                diagnosticDetails("recovery_device_secret_key_load", error),
            )
        }
    }

    private fun completeRecoveryDeviceSecretCryptoOperationError(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        when (error) {
            is KeyPermanentlyInvalidatedException -> result.error(
                "key_invalidated",
                localizedString(R.string.recovery_key_invalidated),
                diagnosticDetails("recovery_device_secret_crypto_operation", error),
            )
            is AEADBadTagException -> result.error(
                "corrupted_secret",
                localizedString(R.string.recovery_secret_corrupted),
                diagnosticDetails("recovery_device_secret_crypto_operation", error),
            )
            else -> result.error(
                "crypto_error",
                localizedString(R.string.recovery_process_failed),
                diagnosticDetails("recovery_device_secret_crypto_operation", error),
            )
        }
    }

    private fun diagnosticDetails(
        stage: String,
        error: Exception? = null,
        status: Int? = null,
    ): Map<String, Any> {
        val details = mutableMapOf<String, Any>(
            "stage" to stage,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
        if (error != null) {
            details["exceptionType"] = error.javaClass.simpleName
        }
        if (status != null) {
            details["status"] = status
        }
        return details
    }

    private fun cancelActiveQuickUnlockForLifecycle(stage: String) {
        val operationId = activeQuickUnlockOperationId ?: return
        val prompt = activeQuickUnlockPrompt
        completeQuickUnlockOperation(
            operationId,
            cleanupBeforeCompletion = true,
        ) { result ->
            result.error(
                "lifecycle_canceled",
                localizedString(R.string.biometric_lifecycle_canceled),
                diagnosticDetails(stage),
            )
        }
        prompt?.cancelAuthentication()
    }

    private fun cancelActiveRecoveryDeviceSecretForLifecycle(stage: String) {
        val operationId = activeRecoveryDeviceSecretOperationId ?: return
        val prompt = activeRecoveryDeviceSecretPrompt
        completeRecoveryDeviceSecretOperation(
            operationId,
            cleanupBeforeCompletion = true,
        ) { result ->
            result.error(
                "lifecycle_canceled",
                localizedString(R.string.recovery_lifecycle_canceled),
                diagnosticDetails(stage),
            )
        }
        prompt?.cancelAuthentication()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (vaultRebuildBridge?.onActivityResult(requestCode, resultCode) == true) return
        if (documentStorageBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onStop() {
        cancelActiveQuickUnlockForLifecycle("activity_stopped")
        cancelActiveRecoveryDeviceSecretForLifecycle("activity_stopped")
        super.onStop()
    }

    override fun onDestroy() {
        commercialLicenseBridge?.dispose()
        commercialLicenseBridge = null
        calendarInsertBridge?.close()
        calendarInsertBridge = null
        vaultRebuildBridge?.close()
        vaultRebuildBridge = null
        documentStorageBridge?.close()
        documentStorageBridge = null
        cancelActiveQuickUnlockForLifecycle("activity_destroyed")
        cancelActiveRecoveryDeviceSecretForLifecycle("activity_destroyed")
        shareIntakeChannel?.setMethodCallHandler(null)
        shareIntakeChannel = null
        ShareIntakeStore.clear()
        // The Dart controller normally stops this service first. This native
        // fallback prevents an orphan foreground notification if the Flutter
        // engine is destroyed before its asynchronous stop call is delivered.
        TemporaryWebForegroundService.stop(applicationContext)
        super.onDestroy()
    }

    private class QuickUnlockKeyMissingException : Exception()
    private class RecoveryDeviceSecretKeyMissingException : Exception()
    private class RecoveryDeviceSecretCleanupException : Exception()

    private fun copySensitiveText(text: String, clearAfterSeconds: Int) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText(
            localizedString(R.string.sensitive_clipboard_label),
            text,
        )
        clip.description.extras = PersistableBundle().apply {
            putBoolean(EXTRA_IS_SENSITIVE, true)
        }
        clipboard.setPrimaryClip(clip)

        mainHandler.postDelayed({
            val currentText = clipboard.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(this)
                ?.toString()
            if (currentText != text) {
                return@postDelayed
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }, clearAfterSeconds * 1000L)
    }
}
