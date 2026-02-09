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
val releaseKeystoreFile = keystoreStoreFileOverride?.let(rootProject::file)
    ?: rootProject.file("upload-keystore.jks")
val hasReleaseKeystore = !keystoreStorePassword.isNullOrBlank() && !keystoreKeyPassword.isNullOrBlank()

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            // TODO: Add your own signing config for the release build.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
