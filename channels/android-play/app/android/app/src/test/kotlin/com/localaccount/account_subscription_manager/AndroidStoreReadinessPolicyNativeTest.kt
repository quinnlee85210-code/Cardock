package com.localaccount.account_subscription_manager

internal object AndroidStoreReadinessPolicyNativeTest {
    @JvmStatic
    fun main(arguments: Array<String>) {
        classifiesPersistablePermissionModes()
        releasesBothRuntimeResources()
        preservesReleaseFailuresWithoutSkippingCleanup()
        preservesAcquireFailureWhenCleanupAlsoFails()
        completesShutdownWhenReleaseFails()
        println("AndroidStoreReadinessPolicyNativeTest: all checks passed")
    }

    private fun classifiesPersistablePermissionModes() {
        check(
            persistablePermissionMode(readGranted = false, writeGranted = false) ==
                PersistablePermissionMode.NONE,
        )
        check(
            persistablePermissionMode(readGranted = true, writeGranted = false) ==
                PersistablePermissionMode.READ,
        )
        check(
            persistablePermissionMode(readGranted = false, writeGranted = true) ==
                PersistablePermissionMode.WRITE,
        )
        check(
            persistablePermissionMode(readGranted = true, writeGranted = true) ==
                PersistablePermissionMode.READ_WRITE,
        )
    }

    private fun releasesBothRuntimeResources() {
        val releases = mutableListOf<String>()
        releaseRuntimeResources(
            releaseWifi = { releases += "wifi" },
            releaseWake = { releases += "wake" },
        )
        check(releases == listOf("wifi", "wake"))
    }

    private fun preservesReleaseFailuresWithoutSkippingCleanup() {
        val wifiFailure = RuntimeException("TEST-ONLY-WIFI-RELEASE")
        var wakeReleased = false
        val wifiThrown = captureRuntimeFailure {
            releaseRuntimeResources(
                releaseWifi = { throw wifiFailure },
                releaseWake = { wakeReleased = true },
            )
        }
        check(wifiThrown === wifiFailure)
        check(wakeReleased)

        val wakeFailure = RuntimeException("TEST-ONLY-WAKE-RELEASE")
        var wifiReleased = false
        val wakeThrown = captureRuntimeFailure {
            releaseRuntimeResources(
                releaseWifi = { wifiReleased = true },
                releaseWake = { throw wakeFailure },
            )
        }
        check(wakeThrown === wakeFailure)
        check(wifiReleased)

        val firstFailure = RuntimeException("TEST-ONLY-FIRST-RELEASE")
        val secondFailure = RuntimeException("TEST-ONLY-SECOND-RELEASE")
        val bothThrown = captureRuntimeFailure {
            releaseRuntimeResources(
                releaseWifi = { throw firstFailure },
                releaseWake = { throw secondFailure },
            )
        }
        check(bothThrown === firstFailure)
        check(bothThrown.suppressed.contentEquals(arrayOf(secondFailure)))
    }

    private fun preservesAcquireFailureWhenCleanupAlsoFails() {
        val acquireFailure = RuntimeException("TEST-ONLY-ACQUIRE")
        val releaseFailure = RuntimeException("TEST-ONLY-RELEASE-AFTER-ACQUIRE")
        val thrown = captureRuntimeFailure {
            acquireRuntimeResources(
                acquire = { throw acquireFailure },
                releaseAfterFailure = { throw releaseFailure },
            )
        }
        check(thrown === acquireFailure)
        check(thrown.suppressed.contentEquals(arrayOf(releaseFailure)))
    }

    private fun completesShutdownWhenReleaseFails() {
        val releaseFailure = RuntimeException("TEST-ONLY-SHUTDOWN-RELEASE")
        val foregroundFailure = RuntimeException("TEST-ONLY-SHUTDOWN-FOREGROUND")
        val completedSteps = mutableListOf<String>()
        val thrown = captureRuntimeFailure {
            completeRuntimeShutdown(
                {
                    completedSteps += "release"
                    throw releaseFailure
                },
                {
                    completedSteps += "stopForeground"
                    throw foregroundFailure
                },
                { completedSteps += "stopSelf" },
                { completedSteps += "super" },
            )
        }
        check(
            completedSteps ==
                listOf("release", "stopForeground", "stopSelf", "super"),
        )
        check(thrown === releaseFailure)
        check(thrown.suppressed.contentEquals(arrayOf(foregroundFailure)))
    }

    private fun captureRuntimeFailure(action: () -> Unit): RuntimeException = try {
        action()
        error("Expected RuntimeException")
    } catch (error: RuntimeException) {
        error
    }
}
