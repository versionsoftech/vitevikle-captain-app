import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties from ../key.properties (relative to android/)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fis ->
        keystoreProperties.load(fis)
    }
}
val storeFilePath = keystoreProperties.getProperty("storeFile")
val storePasswordProp = keystoreProperties.getProperty("storePassword")
val keyAliasProp = keystoreProperties.getProperty("keyAlias")
val keyPasswordProp = keystoreProperties.getProperty("keyPassword")
val hasAllSigningProps = !storeFilePath.isNullOrBlank() && !storePasswordProp.isNullOrBlank() && !keyAliasProp.isNullOrBlank() && !keyPasswordProp.isNullOrBlank()

android {
    namespace = "com.vitecaptain.driver"
    // Google Play requires target API 36+ (Android 16) by Aug 31, 2026.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Application ID updated for Google Play publishing
        applicationId = "com.vitecaptain.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasAllSigningProps) {
            create("release") {
                val resolvedStoreFile = rootProject.file(storeFilePath)
                if (!resolvedStoreFile.exists()) {
                    throw GradleException(
                        "Release signing keystore not found at: ${resolvedStoreFile.absolutePath}.\n" +
                        "Check android/key.properties 'storeFile' path."
                    )
                }
                storeFile = resolvedStoreFile
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storePassword = storePasswordProp
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            if (hasAllSigningProps) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.name.contains("Release") }
    if (buildingRelease && !hasAllSigningProps) {
        throw GradleException(
            "Release signing is not configured. Missing properties in android/key.properties.\n" +
            "Expected entries: storeFile, storePassword, keyAlias, keyPassword."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("com.google.android.gms:play-services-maps:18.2.0")
}
