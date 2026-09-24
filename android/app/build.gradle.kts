import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key, kept outside the project (see
// packaging/create-signing-key.sh). NETWHO_KEY_PROPERTIES can point elsewhere.
val keyPropsFile = file(
    System.getenv("NETWHO_KEY_PROPERTIES")
        ?: "${System.getProperty("user.home")}/.android-keys/netwho-key.properties"
)
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) keyPropsFile.inputStream().use { load(it) }
}
val hasReleaseKey = keyPropsFile.exists()

android {
    namespace = "io.github.biptybop.netwho"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.biptybop.netwho"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without the key, release builds stop (see the check below) unless
            // NETWHO_ALLOW_DEBUG_SIGNING=1, e.g. someone building from source.
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

// A debug-signed release APK must never be published by accident, so fail
// loudly instead of quietly falling back. `flutter run` is unaffected.
gradle.taskGraph.whenReady {
    val releasing = allTasks.any {
        it.project.name == "app" && it.name.endsWith("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    if (releasing && !hasReleaseKey && System.getenv("NETWHO_ALLOW_DEBUG_SIGNING") != "1") {
        throw GradleException(
            "NetWho release key not found at $keyPropsFile.\n" +
                "Create it with packaging/create-signing-key.sh, or set " +
                "NETWHO_ALLOW_DEBUG_SIGNING=1 for a private, debug-signed build."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
