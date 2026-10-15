package com.localaccount.account_subscription_manager

internal object ShareIntentPolicyNativeTest {
    @JvmStatic
    fun main(arguments: Array<String>) {
        acceptedPlainTextAndOptionalMetadata()
        rejectsUnsupportedActionsAndMimeTypes()
        rejectsStreamsUrisNestedIntentsAndExecutableSchemes()
        rejectsUnsafeClipDataControlsAndOversizeText()
        enforcesSingleSlotOneShotExpiryAndClear()
        println("ShareIntentPolicyNativeTest: all checks passed")
    }

    private fun acceptedPlainTextAndOptionalMetadata() {
        val result = ShareIntentPolicy.validate(
            validCandidate(
                text = "Premium plan renews 2026-10-01 https://example.com",
                subject = "Subscription reminder",
                title = "Example",
                clipItems = listOf(
                    ShareClipCandidate(
                        text = "Premium plan renews 2026-10-01 https://example.com",
                    ),
                ),
                clipMimeTypes = listOf(ShareIntentPolicy.MIME_TEXT_PLAIN),
            ),
        )
        check(result is ShareIntentValidation.Accepted)
        check(result.subject == "Subscription reminder")
    }

    private fun rejectsUnsupportedActionsAndMimeTypes() {
        expectRejected(
            validCandidate(action = "android.intent.action.SEND_MULTIPLE"),
            ShareIntakeErrorCode.INVALID_ACTION,
        )
        expectRejected(
            validCandidate(mimeType = "text/html"),
            ShareIntakeErrorCode.INVALID_MIME_TYPE,
        )
        expectRejected(
            validCandidate(mimeType = "text/*"),
            ShareIntakeErrorCode.INVALID_MIME_TYPE,
        )
        expectRejected(
            validCandidate(componentClassName = "example.AttackerActivity"),
            ShareIntakeErrorCode.INVALID_COMPONENT,
        )
    }

    private fun rejectsStreamsUrisNestedIntentsAndExecutableSchemes() {
        expectRejected(
            validCandidate(hasStreamExtra = true),
            ShareIntakeErrorCode.UNSUPPORTED_EXTRA,
        )
        expectRejected(
            validCandidate(dataScheme = "content"),
            ShareIntakeErrorCode.UNSUPPORTED_URI,
        )
        expectRejected(
            validCandidate(hasGrantUriPermission = true),
            ShareIntakeErrorCode.UNSUPPORTED_URI,
        )
        expectRejected(
            validCandidate(hasNestedIntent = true),
            ShareIntakeErrorCode.UNSUPPORTED_EXTRA,
        )
        expectRejected(
            validCandidate(text = "javascript:alert(1)"),
            ShareIntakeErrorCode.UNSUPPORTED_EXECUTABLE_CONTENT,
        )
        expectRejected(
            validCandidate(text = "file:///sdcard/private.txt"),
            ShareIntakeErrorCode.UNSUPPORTED_EXECUTABLE_CONTENT,
        )
        expectRejected(
            validCandidate(text = "data:text/html,<script>alert(1)</script>"),
            ShareIntakeErrorCode.UNSUPPORTED_EXECUTABLE_CONTENT,
        )
        check(
            ShareIntentPolicy.validate(validCandidate(text = "data: ordinary label"))
                is ShareIntentValidation.Accepted,
        )
    }

    private fun rejectsUnsafeClipDataControlsAndOversizeText() {
        expectRejected(
            validCandidate(
                clipItems = listOf(ShareClipCandidate(text = null, uriScheme = "content")),
            ),
            ShareIntakeErrorCode.UNSUPPORTED_CLIP_DATA,
        )
        expectRejected(
            validCandidate(
                text = "one",
                clipItems = listOf(ShareClipCandidate(text = "two")),
            ),
            ShareIntakeErrorCode.UNSUPPORTED_CLIP_DATA,
        )
        expectRejected(
            validCandidate(text = "unsafe\u0000text"),
            ShareIntakeErrorCode.INVALID_TEXT,
        )
        expectRejected(
            validCandidate(text = "x".repeat(ShareIntentPolicy.MAX_TEXT_LENGTH + 1)),
            ShareIntakeErrorCode.TEXT_TOO_LONG,
        )
        expectRejected(
            validCandidate(hasUnsupportedExtras = true),
            ShareIntakeErrorCode.UNSUPPORTED_EXTRA,
        )
    }


    private fun enforcesSingleSlotOneShotExpiryAndClear() {
        val first = ShareIntentValidation.Accepted("first", null, null)
        val second = ShareIntentValidation.Accepted("second", null, null)
        ShareIntakeStore.clear()
        ShareIntakeStore.replaceAt(first, now = 1_000L)
        ShareIntakeStore.replaceAt(second, now = 2_000L)
        val consumed = ShareIntakeStore.consumeAt(now = 2_500L)
        check(consumed?.get("status") == "accepted")
        check(consumed["text"] == "second")
        check(ShareIntakeStore.consumeAt(now = 2_501L) == null)

        ShareIntakeStore.replaceAt(first, now = 10_000L)
        val expired = ShareIntakeStore.consumeAt(now = 310_000L)
        check(expired?.get("errorCode") == ShareIntakeErrorCode.EXPIRED.name)
        check(ShareIntakeStore.consumeAt(now = 310_001L) == null)

        ShareIntakeStore.replaceAt(first, now = 400_000L)
        ShareIntakeStore.clear()
        check(ShareIntakeStore.consumeAt(now = 400_001L) == null)
    }
    private fun validCandidate(
        action: String = ShareIntentPolicy.ACTION_SEND,
        mimeType: String = ShareIntentPolicy.MIME_TEXT_PLAIN,
        componentPackage: String = ShareIntentPolicy.PACKAGE_NAME,
        componentClassName: String = ShareIntentPolicy.RECEIVER_CLASS,
        dataScheme: String? = null,
        hasStreamExtra: Boolean = false,
        hasNestedIntent: Boolean = false,
        hasUnsupportedExtras: Boolean = false,
        hasGrantUriPermission: Boolean = false,
        text: String = "Example subscription",
        subject: String? = null,
        title: String? = null,
        clipMimeTypes: List<String> = emptyList(),
        clipItems: List<ShareClipCandidate> = emptyList(),
    ) = ShareIntentCandidate(
        action = action,
        mimeType = mimeType,
        componentPackage = componentPackage,
        componentClassName = componentClassName,
        dataScheme = dataScheme,
        hasStreamExtra = hasStreamExtra,
        hasNestedIntent = hasNestedIntent,
        hasUnsupportedExtras = hasUnsupportedExtras,
        hasGrantUriPermission = hasGrantUriPermission,
        text = text,
        subject = subject,
        title = title,
        clipMimeTypes = clipMimeTypes,
        clipItems = clipItems,
    )

    private fun expectRejected(
        candidate: ShareIntentCandidate,
        expected: ShareIntakeErrorCode,
    ) {
        val result = ShareIntentPolicy.validate(candidate)
        check(result == ShareIntentValidation.Rejected(expected)) {
            "Expected $expected but got $result"
        }
    }
}
