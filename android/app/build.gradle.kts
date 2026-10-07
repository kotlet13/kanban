import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("jivie-key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val jivieApplicationId = "si.triparna.jivie"
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = releaseSigningKeys.all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
}
val releaseKeystoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { path ->
        val moduleRelativeFile = file(path)
        if (moduleRelativeFile.exists()) moduleRelativeFile else rootProject.file(path)
    }

// Missing private signing settings must not prevent development builds. The
// release variant always checks them before building and never uses debug keys.
val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing requires android/jivie-key.properties with non-empty " +
                    releaseSigningKeys.joinToString(", ") + "."
            )
        }
        if (keystoreProperties.getProperty("applicationId") != jivieApplicationId) {
            throw GradleException(
                "Jivie release signing must explicitly declare applicationId=$jivieApplicationId " +
                    "in android/jivie-key.properties."
            )
        }
        if (releaseKeystoreFile?.isFile != true) {
            throw GradleException("Release signing requires an existing keystore file.")
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(validateReleaseSigning)
}

android {
    namespace = "si.triparna.jivie"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // A separate install and store identity from legacy Kanban Connect.
        applicationId = "si.triparna.jivie"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Current Google Play target for a new phone app; keep explicit for release review.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
