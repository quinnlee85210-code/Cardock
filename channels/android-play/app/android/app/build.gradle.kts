import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val cardockDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(',').filter { it.isNotBlank() }.mapNotNull {
    runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8).split('=', limit = 2) }.getOrNull()
}.filter { it.size == 2 }.associate { it[0] to it[1] }
fun cardockString(name: String, fallback: String = "") = groovy.json.JsonOutput.toJson(cardockDefines[name] ?: fallback)

android {
    buildFeatures { buildConfig = true }
    sourceSets.getByName("main").java.srcDir(if (cardockDefines["CARDOCK_DISTRIBUTION"] == "google_play") "src/googleBilling/kotlin" else "src/noBilling/kotlin")
    namespace = "com.localaccount.account_subscription_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        buildConfigField("String", "CARDOCK_CHANNEL", cardockString("CARDOCK_DISTRIBUTION", "development"))
        buildConfigField("String", "CARDOCK_SIGNING_SHA256", cardockString("CARDOCK_ANDROID_SIGNING_SHA256"))
        buildConfigField("String", "CARDOCK_PLAY_PUBLIC_KEY", cardockString("CARDOCK_PLAY_LICENSE_PUBLIC_KEY")
        )
        buildConfigField("String", "CARDOCK_STORE_PRODUCT_ID", cardockString("CARDOCK_STORE_PRODUCT_ID"))
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.localaccount.account_subscription_manager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val signingMode = System.getenv("CARDOCK_SIGNING_MODE") ?: if (cardockDefines["CARDOCK_DISTRIBUTION"] == "google_play") "unsigned" else "continuity"
    require(signingMode in setOf("continuity", "unsigned", "formal")) { "Invalid signing mode" }
    if (signingMode == "formal") {
        signingConfigs.create("cardockFormal") {
            storeFile = file(requireNotNull(System.getenv("CARDOCK_KEYSTORE_PATH")))
            storePassword = requireNotNull(System.getenv("CARDOCK_KEYSTORE_PASSWORD"))
            keyAlias = requireNotNull(System.getenv("CARDOCK_KEY_ALIAS"))
            keyPassword = requireNotNull(System.getenv("CARDOCK_KEYSTORE_PASSWORD"))
            storeType = "PKCS12"
        }
    }
    buildTypes {
        release {
            signingConfig = when (signingMode) {
                "formal" -> signingConfigs.getByName("cardockFormal")
                "continuity" -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }

    bundle {
        language {
            enableSplit = false
        }
    }
}

dependencies {
    if (cardockDefines["CARDOCK_DISTRIBUTION"] == "google_play") {
        implementation("com.android.billingclient:billing:9.1.0")
    }
    implementation("androidx.biometric:biometric:1.1.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
tasks.register<JavaExec>("nativeReminderRecoveryTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(files(
        layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"),
        layout.buildDirectory.dir("tmp/kotlin-classes/debug"),
    ))
    classpath(fileTree(java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib")) {
        include("**/kotlin-stdlib-*.jar")
    })
    mainClass.set("com.localaccount.account_subscription_manager.ReminderRecoveryPolicyNativeTest")
}
tasks.register<JavaExec>("nativeSharePolicyTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(
        files(
            layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"),
            layout.buildDirectory.dir("tmp/kotlin-classes/debug"),
        ),
    )
    classpath(
        fileTree(
            java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib"),
        ) {
            include("**/kotlin-stdlib-*.jar")
        },
    )
    mainClass.set(
        "com.localaccount.account_subscription_manager.ShareIntentPolicyNativeTest",
    )
}

tasks.register<JavaExec>("nativeAndroidStoreReadinessPolicyTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(
        files(
            layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"),
            layout.buildDirectory.dir("tmp/kotlin-classes/debug"),
        ),
    )
    classpath(
        fileTree(
            java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib"),
        ) {
            include("**/kotlin-stdlib-*.jar")
        },
    )
    mainClass.set(
        "com.localaccount.account_subscription_manager.AndroidStoreReadinessPolicyNativeTest",
    )
}

// Same offline native runner used by reminder/share policy tests.
tasks.register<JavaExec>("nativeCalendarInsertTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(files(layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"), layout.buildDirectory.dir("tmp/kotlin-classes/debug")))
    classpath(fileTree(java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib")) { include("**/kotlin-stdlib-*.jar") })
    mainClass.set("com.localaccount.account_subscription_manager.CalendarInsertPolicyNativeTest")
}

tasks.register<JavaExec>("nativePlayBillingReceiptTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(files(layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"), layout.buildDirectory.dir("tmp/kotlin-classes/debug")))
    classpath(fileTree(java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib")) { include("**/kotlin-stdlib-*.jar") })
    mainClass.set("com.localaccount.account_subscription_manager.PlayBillingReceiptNativeTest")
}

tasks.register<JavaExec>("nativeGooglePlayReadinessTest") {
    dependsOn("compileDebugUnitTestKotlin")
    classpath(files(layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"), layout.buildDirectory.dir("tmp/kotlin-classes/debug")))
    classpath(fileTree(java.io.File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib")) { include("**/kotlin-stdlib-*.jar") })
    mainClass.set("com.localaccount.account_subscription_manager.GooglePlayReadinessNativeTest")
}
