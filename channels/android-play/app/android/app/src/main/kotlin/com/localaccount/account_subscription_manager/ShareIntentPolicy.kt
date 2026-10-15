package com.localaccount.account_subscription_manager

internal enum class ShareIntakeErrorCode {
    INVALID_ACTION,
    INVALID_MIME_TYPE,
    INVALID_COMPONENT,
    UNSUPPORTED_EXTRA,
    UNSUPPORTED_CLIP_DATA,
    UNSUPPORTED_URI,
    UNSUPPORTED_EXECUTABLE_CONTENT,
    INVALID_TEXT,
    TEXT_TOO_LONG,
    EXPIRED,
}

internal data class ShareClipCandidate(
    val text: String?,
    val uriScheme: String? = null,
    val hasNestedIntent: Boolean = false,
    val hasHtmlText: Boolean = false,
)

internal data class ShareIntentCandidate(
    val action: String?,
    val mimeType: String?,
    val componentPackage: String?,
    val componentClassName: String?,
    val dataScheme: String? = null,
    val hasStreamExtra: Boolean = false,
    val hasHtmlExtra: Boolean = false,
    val hasNestedIntent: Boolean = false,
    val hasUnsupportedExtras: Boolean = false,
    val hasGrantUriPermission: Boolean = false,
    val text: String? = null,
    val subject: String? = null,
    val title: String? = null,
    val clipMimeTypes: List<String> = emptyList(),
    val clipItems: List<ShareClipCandidate> = emptyList(),
)

internal sealed interface ShareIntentValidation {
    data class Accepted(
        val text: String,
        val subject: String?,
        val title: String?,
    ) : ShareIntentValidation

    data class Rejected(val error: ShareIntakeErrorCode) : ShareIntentValidation
}

internal object ShareIntentPolicy {
    const val ACTION_SEND = "android.intent.action.SEND"
    const val MIME_TEXT_PLAIN = "text/plain"
    const val RECEIVER_CLASS =
        "com.localaccount.account_subscription_manager.ShareReceiverActivity"
    const val PACKAGE_NAME = "com.localaccount.account_subscription_manager"
    const val MAX_TEXT_LENGTH = 20_000
    private const val MAX_METADATA_LENGTH = 512

    private val forbiddenScheme = Regex(
        pattern = "\\b(?:content|file|intent|javascript|android-app):" +
            "|\\bdata:(?:[a-z][a-z0-9.+-]*/|[a-z][a-z0-9.+-]*;|,)",
        option = RegexOption.IGNORE_CASE,
    )

    fun validate(candidate: ShareIntentCandidate): ShareIntentValidation {
        if (candidate.action != ACTION_SEND) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_ACTION)
        }
        if (candidate.mimeType != MIME_TEXT_PLAIN ||
            candidate.clipMimeTypes.any { it != MIME_TEXT_PLAIN }
        ) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_MIME_TYPE)
        }
        if (candidate.componentPackage != PACKAGE_NAME ||
            candidate.componentClassName != RECEIVER_CLASS
        ) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_COMPONENT)
        }
        if (candidate.hasStreamExtra ||
            candidate.hasHtmlExtra ||
            candidate.hasNestedIntent ||
            candidate.hasUnsupportedExtras
        ) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.UNSUPPORTED_EXTRA)
        }
        if (candidate.dataScheme != null || candidate.hasGrantUriPermission) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.UNSUPPORTED_URI)
        }
        if (candidate.clipItems.size > 1 ||
            candidate.clipItems.any {
                it.uriScheme != null || it.hasNestedIntent || it.hasHtmlText
            }
        ) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.UNSUPPORTED_CLIP_DATA)
        }

        val directText = candidate.text
        val clipText = candidate.clipItems.singleOrNull()?.text
        if (directText != null && clipText != null && directText != clipText) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.UNSUPPORTED_CLIP_DATA)
        }
        val text = (directText ?: clipText)?.trim()
        if (text.isNullOrEmpty() || !hasOnlyAllowedCharacters(text)) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_TEXT)
        }
        if (text.length > MAX_TEXT_LENGTH) {
            return ShareIntentValidation.Rejected(ShareIntakeErrorCode.TEXT_TOO_LONG)
        }
        if (forbiddenScheme.containsMatchIn(text)) {
            return ShareIntentValidation.Rejected(
                ShareIntakeErrorCode.UNSUPPORTED_EXECUTABLE_CONTENT,
            )
        }

        val subject = normalizeMetadata(candidate.subject)
            ?: if (candidate.subject.isNullOrBlank()) null else {
                return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_TEXT)
            }
        val title = normalizeMetadata(candidate.title)
            ?: if (candidate.title.isNullOrBlank()) null else {
                return ShareIntentValidation.Rejected(ShareIntakeErrorCode.INVALID_TEXT)
            }
        return ShareIntentValidation.Accepted(
            text = text,
            subject = subject,
            title = title,
        )
    }

    private fun normalizeMetadata(value: String?): String? {
        val normalized = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (normalized.length > MAX_METADATA_LENGTH ||
            !hasOnlyAllowedCharacters(normalized) ||
            forbiddenScheme.containsMatchIn(normalized)
        ) {
            return null
        }
        return normalized
    }

    private fun hasOnlyAllowedCharacters(value: String): Boolean {
        var offset = 0
        while (offset < value.length) {
            val codePoint = value.codePointAt(offset)
            val allowedWhitespace = codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D
            if ((codePoint in 0x00..0x1F && !allowedWhitespace) ||
                codePoint in 0x7F..0x9F ||
                codePoint in 0x202A..0x202E ||
                codePoint in 0x2066..0x2069
            ) {
                return false
            }
            offset += Character.charCount(codePoint)
        }
        return true
    }
}
