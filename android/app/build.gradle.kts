import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(propertyName: String, envName: String): String? {
    val propertyValue = keystoreProperties[propertyName]?.toString()?.trim()
    if (!propertyValue.isNullOrEmpty()) {
        return propertyValue
    }
    return System.getenv(envName)?.trim()?.takeIf { it.isNotEmpty() }
}

fun androidSdkValue(propertyName: String, envName: String, fallback: Int): Int {
    val propertyValue = project.findProperty(propertyName)?.toString()?.trim()
    if (!propertyValue.isNullOrEmpty()) {
        return propertyValue.toInt()
    }
    val envValue = System.getenv(envName)?.trim()
    if (!envValue.isNullOrEmpty()) {
        return envValue.toInt()
    }
    return fallback
}

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val releaseStoreFileOnDisk = releaseStoreFile?.let(rootProject::file)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrEmpty() } &&
    releaseStoreFileOnDisk?.isFile == true
val allowUnsignedRelease = providers.gradleProperty("WEBTUI_ALLOW_UNSIGNED_RELEASE")
    .orNull
    ?.toBooleanStrictOrNull() == true
val requestedReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (requestedReleaseTask && !hasReleaseSigning && !allowUnsignedRelease) {
    throw GradleException(
        "Release signing is incomplete or the configured keystore does not exist. " +
            "Provide the protected signing values. For compile-only local validation, " +
            "explicitly set WEBTUI_ALLOW_UNSIGNED_RELEASE=true; never upload that artifact.",
    )
}

android {
    namespace = "com.vpsttt.webtui_chat"
    compileSdk = androidSdkValue(
        "WEBTUI_ANDROID_COMPILE_SDK",
        "WEBTUI_ANDROID_COMPILE_SDK",
        flutter.compileSdkVersion,
    )
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vpsttt.webtui_chat"
        minSdk = flutter.minSdkVersion
        targetSdk = androidSdkValue(
            "WEBTUI_ANDROID_TARGET_SDK",
            "WEBTUI_ANDROID_TARGET_SDK",
            flutter.targetSdkVersion,
        )
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["webtuiAppLinkHost"] =
            project.findProperty("WEBTUI_APP_LINK_HOST")?.toString()
                ?: System.getenv("WEBTUI_APP_LINK_HOST")?.trim()?.takeIf { it.isNotEmpty() }
                ?: "chat.vpsttt.com"
    }

    flavorDimensions += "environment"

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = releaseStoreFileOnDisk!!
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "WebTui Chat Dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "WebTui Chat Staging")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "WebTui Chat")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            ndk.debugSymbolLevel = "SYMBOL_TABLE"
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
