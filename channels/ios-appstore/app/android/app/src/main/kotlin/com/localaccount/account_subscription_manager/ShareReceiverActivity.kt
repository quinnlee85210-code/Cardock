package com.localaccount.account_subscription_manager

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.os.Bundle

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val validation = runCatching { validateIncomingIntent(intent) }.getOrElse {
            ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_TEXT)
        }
        ShareIntakeStore.replace(validation)
        clearIncomingIntent(intent)
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_OPEN_SHARED_TEXT
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
        finish()
    }

    private fun validateIncomingIntent(source: Intent): ShareIntentValidation {
        val allowedExtraKeys = setOf(
            Intent.EXTRA_TEXT,
            Intent.EXTRA_SUBJECT,
            Intent.EXTRA_TITLE,
        )
        val extraKeys = source.extras?.keySet()?.toSet().orEmpty()
        val clipData = source.clipData
        val hasUnsupportedExtraValue = extraKeys.any { key ->
            key in allowedExtraKeys &&
                source.extras?.getCharSequence(key) == null
        }
        return ShareIntentPolicy.validate(
            ShareIntentCandidate(
                action = source.action,
                mimeType = source.type,
                componentPackage = source.component?.packageName,
                componentClassName = source.component?.className,
                dataScheme = source.data?.scheme,
                hasStreamExtra = source.hasExtra(Intent.EXTRA_STREAM),
                hasHtmlExtra = source.hasExtra(Intent.EXTRA_HTML_TEXT),
                hasNestedIntent = source.selector != null,
                hasUnsupportedExtras = extraKeys.any { it !in allowedExtraKeys } ||
                    hasUnsupportedExtraValue,
                hasGrantUriPermission = source.flags and URI_GRANT_FLAGS != 0,
                text = source.safeCharSequenceExtra(Intent.EXTRA_TEXT),
                subject = source.safeCharSequenceExtra(Intent.EXTRA_SUBJECT),
                title = source.safeCharSequenceExtra(Intent.EXTRA_TITLE),
                clipMimeTypes = clipData?.mimeTypes().orEmpty(),
                clipItems = clipData?.safeItems().orEmpty(),
            ),
        )
    }

    private fun Intent.safeCharSequenceExtra(name: String): String? {
        return extras?.getCharSequence(name)?.toString()
    }

    private fun ClipData.mimeTypes(): List<String> = buildList {
        for (index in 0 until description.mimeTypeCount) {
            add(description.getMimeType(index))
        }
    }

    private fun ClipData.safeItems(): List<ShareClipCandidate> = buildList {
        for (index in 0 until itemCount) {
            val item = getItemAt(index)
            add(
                ShareClipCandidate(
                    text = item.text?.toString(),
                    uriScheme = item.uri?.scheme,
                    hasNestedIntent = item.intent != null,
                    hasHtmlText = item.htmlText != null,
                ),
            )
        }
    }

    private fun clearIncomingIntent(source: Intent) {
        source.action = null
        source.type = null
        source.data = null
        source.clipData = null
        source.selector = null
        source.replaceExtras(Bundle())
    }

    private companion object {
        const val URI_GRANT_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
    }
}
