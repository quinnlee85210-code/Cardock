package com.localaccount.account_subscription_manager

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64
import org.json.JSONObject

/** Short-lived process memory only; external Intents never become saved state. */
internal object OfflinePurchaseIntake {
    const val action = "cardock.OFFLINE_INTAKE"
    private var pending: Map<String, String>? = null
    private var received = 0L
    private const val grantFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

    @Synchronized fun replace(kind: String, text: String) {
        pending = mapOf("kind" to kind, "text" to text)
        received = android.os.SystemClock.elapsedRealtime()
    }
    @Synchronized fun consume(): Map<String, String>? {
        val item = pending
        pending = null
        return if (android.os.SystemClock.elapsedRealtime() - received in 0 until 300000) item else null
    }
    @Synchronized fun clear() { pending = null }

    private fun decode(value: String, max: Int): String {
        require(value.length <= (max * 4 + 2) / 3 && value.matches(Regex("[A-Za-z0-9_-]+")))
        val raw = Base64.getUrlDecoder().decode(value)
        require(raw.size <= max && Base64.getUrlEncoder().withoutPadding().encodeToString(raw) == value)
        return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString()
    }

    fun receive(source: Intent) {
        try {
            require(BuildConfig.CARDOCK_CHANNEL == "website")
            require(source.action == Intent.ACTION_VIEW && source.type == null && source.selector == null)
            require(source.flags and grantFlags == 0 && source.clipData == null)
            val uri = source.data ?: error("missing route")
            require(uri.scheme == "cardock" && uri.host == "offline" && uri.port == -1 &&
                uri.userInfo == null && uri.query == null)
            val path = uri.path
            if (path == "/activate" && uri.encodedFragment != null) {
                val fragment = uri.encodedFragment!!
                require(fragment.startsWith("activation=") && uri.toString().length <= 36000)
                val text = decode(fragment.removePrefix("activation="), 24576)
                require(text.startsWith(OfflinePurchasePolicy.bundlePrefix))
                replace("activation", text)
                return
            }
            require(uri.fragment == null)
            val keys = source.extras?.keySet().orEmpty()
            when (path) {
                "/activate", "/proof" -> {
                    val name = if (path == "/activate") "cardock_offline_activation" else "cardock_offline_challenge"
                    require(keys == setOf(name))
                    val encoded = source.extras?.get(name)
                    require(encoded is String)
                    val text = decode(encoded, if (path == "/activate") 24576 else 8192)
                    if (path == "/activate") require(text.startsWith(OfflinePurchasePolicy.bundlePrefix))
                    replace(if (path == "/activate") "activation" else "challenge", text)
                }
                "/request" -> {
                    require(keys == setOf("cardock_offline_purpose", "cardock_offline_reference"))
                    val purpose = source.extras?.get("cardock_offline_purpose")
                    val reference = source.extras?.get("cardock_offline_reference")
                    require(purpose is String && reference is String)
                    OfflinePurchasePolicy.validatePurpose(purpose, reference)
                    // This untrusted request only opens a confirmation. It cannot sign.
                    replace("request", JSONObject(mapOf("purpose" to purpose, "reference" to reference)).toString())
                }
                else -> error("unsupported route")
            }
        } catch (_: Exception) {
            replace("error", "离线材料格式无效，请从官网原订单页重新打开。")
        }
    }

    fun receiveShareIfActivation(source: Intent): Boolean {
        if (BuildConfig.CARDOCK_CHANNEL != "website") return false
        val text = runCatching { source.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() }.getOrNull() ?: return false
        if (!text.startsWith(OfflinePurchasePolicy.bundlePrefix)) return false
        try {
            require(source.action == Intent.ACTION_SEND && source.type == "text/plain" && source.selector == null && source.data == null)
            require(source.flags and grantFlags == 0 && text.toByteArray(Charsets.UTF_8).size <= 24576)
            val allowed = setOf(Intent.EXTRA_TEXT, Intent.EXTRA_SUBJECT, Intent.EXTRA_TITLE)
            val keys = source.extras?.keySet().orEmpty()
            require(keys.all { it in allowed && source.extras?.get(it) is CharSequence })
            source.clipData?.let { clip ->
                require(clip.itemCount == 1)
                val item = clip.getItemAt(0)
                require(item.uri == null && item.intent == null && item.htmlText == null &&
                    item.text?.toString() == text)
            }
            replace("activation", text)
        } catch (_: Exception) {
            replace("error", "分享内容不是完整的Cardock离线授权，请重新复制完整授权。")
        }
        return true
    }
}

class OfflinePurchaseReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        OfflinePurchaseIntake.receive(intent)
        intent.apply { action = null; data = null; clipData = null; selector = null; replaceExtras(Bundle()) }
        startActivity(Intent(this, MainActivity::class.java).apply {
            action = OfflinePurchaseIntake.action
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        })
        finish()
    }
}
