import java.util.Properties

// Release signing credentials live in android/key.properties, which is
// gitignored and never published. See ANDROID_RELEASE.md for why the
// keystore must be backed up: every published APK is signed with it, and
// Android refuses to install an update signed by a different key, so
// losing it forces users to uninstall (destroying their local
// growmont.db) before they can move to a replacement key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.growmont.growmont_crm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.growmont.growmont_crm"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Both derive from pubspec.yaml's `version: <name>+<code>` — the
        // single source of truth (see RELEASE.md). versionCode is what
        // Android uses to decide whether an APK is an upgrade; it must
        // strictly increase on every published build, even when
        // versionName is unchanged. installer/build_android_release.ps1
        // enforces that.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Absent key.properties (a fresh clone, or CI without the
            // secret) leaves this config empty rather than failing at
            // configuration time, so debug builds and `flutter test` still
            // work. The release buildType below is what refuses to produce
            // an unsigned/debug-signed release artifact.
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falling back to the debug key here would be worse than
            // failing: the debug keystore is machine-local and publicly
            // known, so an APK signed with it cannot be updated from any
            // other machine and can be forged by anyone. Fail loudly
            // instead — a debug-signed release must never reach a user.
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "android/key.properties not found — cannot build a release APK.\n" +
                    "This file holds the release signing credentials and is gitignored " +
                    "by design, so it does not arrive with a clone.\n" +
                    "Restore it and growmont-release.jks from your backup. " +
                    "See flutterapp/ANDROID_RELEASE.md."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            // Minify/shrinkResources deliberately left off (the Flutter
            // default). A Flutter APK's size is dominated by the AOT-
            // compiled Dart snapshot and native engine libs, which R8
            // cannot touch, so shrinking the Java/Kotlin side buys little
            // here — while adding a class of bug that only appears in
            // release builds, via reflection-based Firebase/plugin code.
            // Not worth the risk on a sideloaded build with no staged
            // rollout to catch it.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // MainActivity uses androidx.core's FileProvider to hand the downloaded
    // APK to the package installer. It already arrives transitively via the
    // Flutter embedding, but that is an implementation detail of whichever
    // Flutter version is in use — declared explicitly so a future engine
    // change cannot break the updater's compile in a non-obvious way.
    implementation("androidx.core:core-ktx:1.13.1")
}
