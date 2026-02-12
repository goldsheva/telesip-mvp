import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val keystoreStorePassword = keystoreProperties["storePassword"] as? String
val keystoreKeyPassword = keystoreProperties["keyPassword"] as? String
val keystoreKeyAlias = keystoreProperties["keyAlias"] as? String ?: "upload"
val keystoreStoreFileOverride = keystoreProperties["storeFile"] as? String

// If storeFile is provided, resolve it from the rootProject; otherwise fallback to upload-keystore.jks at root.
val releaseKeystoreFile = keystoreStoreFileOverride?.let(rootProject::file)
    ?: rootProject.file("upload-keystore.jks")

val hasReleaseKeystore =
    !keystoreStorePassword.isNullOrBlank() && !keystoreKeyPassword.isNullOrBlank()

android {
    namespace = "com.sip_mvp.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.sip_mvp.app"

        // ✅ Support Android 5.0+ (including Android 7.1.1 / API 25)
        minSdk = flutter.minSdkVersion

        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ Often needed with Firebase + WebRTC + other plugins on older Android
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            storeFile = releaseKeystoreFile
            storePassword = keystoreStorePassword
            keyAlias = keystoreKeyAlias
            keyPassword = keystoreKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // ✅ Smaller APK / fewer unused resources
            isMinifyEnabled = true
            isShrinkResources = true

            // Keep default Proguard rules used by Flutter + add your own if needed.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            // (optional) keep default debug behavior
        }
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.2.0"))
    implementation("com.google.firebase:firebase-messaging")
    // ✅ MultiDex runtime support for pre-Lollipop / large method counts
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}

flutter {
    source = "../.."
}
