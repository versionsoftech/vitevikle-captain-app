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
    compileSdk = flutter.compileSdkVersion
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
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!hasAllSigningProps) {
                throw GradleException(
                    "Release signing is not configured. Missing properties in android/key.properties.\n" +
                    "Expected entries: storeFile, storePassword, keyAlias, keyPassword."
                )
            }
            // Resolve storeFile relative to android/ directory (where key.properties is located)
            var resolvedStoreFile = rootProject.file(storeFilePath)
            println("[signingConfigs.release] Resolved keystore path: ${resolvedStoreFile.absolutePath}")
            if (!resolvedStoreFile.exists()) {
                throw GradleException(
                    "Release signing keystore not found at: ${resolvedStoreFile.absolutePath}.\n" +
                    "Check android/key.properties 'storeFile' path."
                )
            }
            // Log non-sensitive signing info to aid debugging
            println("[signingConfigs.release] storeFile=${resolvedStoreFile.absolutePath}, keyAlias=${keyAliasProp}")

            storeFile = resolvedStoreFile
            keyAlias = keyAliasProp
            keyPassword = keyPasswordProp
            storePassword = storePasswordProp
        }
    }

    buildTypes {
        release {
            // Disable shrinking/minification unless R8 rules are configured
            isMinifyEnabled = false
            isShrinkResources = false
            // Use the proper release signing config (from key.properties)
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
