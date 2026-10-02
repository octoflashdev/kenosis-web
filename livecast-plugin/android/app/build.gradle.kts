import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: load android/key.properties (gitignored) if present — same
// loader pattern as the host app. When absent (CI / fresh clones), release
// falls back to the debug signing config so non-release builds still pass.
// NOTE: the plugin app is a SEPARATE Play Console app; when it ships publicly
// it should get its OWN upload keystore (a separate key.properties), not the
// host's. Until then (debug-only feature surface) the debug fallback covers
// local builds, and release AAB builds reuse whatever key.properties is placed
// in this directory by the release tooling.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "hr.exel.kenosis_plugin_livecast"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // AGP 9 disables the AIDL build feature by default — the plugin contract
    // (android/app/src/main/aidl/hr/exel/kenosis/plugin/IKenosisPlugin.aidl)
    // is binder IPC, so opt in or the Stub/Proxy classes are never generated
    // and Kotlin compilation of LivecastPluginService fails with
    // "Unresolved reference 'kenosis'".
    buildFeatures {
        aidl = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // "Kenosis AI - LiveCast plugin" — a separate Play Store app.
        // The host (hr.exel.kenosis_ai) discovers this app's service by the
        // hr.exel.kenosis_ai.PLUGIN_SERVICE intent action (manifest <queries>).
        applicationId = "hr.exel.kenosis.plugin_livecast"
        minSdk = maxOf(flutter.minSdkVersion, 29)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        // Debug builds get a ".debug" applicationId suffix, mirroring the host
        // app: hr.exel.kenosis.plugin_livecast.debug installs alongside a
        // future Play-installed release. The host's discovery binds whatever
        // plugin package is installed — the manifest <queries> filters on the
        // PLUGIN_SERVICE action, not the package name.
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            // Signed with the upload keystore (android/key.properties,
            // gitignored) when present; otherwise the debug config so
            // `flutter run --release` / CI builds without the key still work.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // The LAN web server serving the live transcript page (BSD-2, MavenCentral,
    // license-clean for the APK). Port ladder 8090..8099 — see LivecastServer.
    implementation("org.nanohttpd:nanohttpd:2.3.1")

    // Local unit tests (LivecastStateTest — the pure session state machine).
    // Run on the dev machine: cd plugins/livecast/android && ./gradlew :app:testDebugUnitTest
    // (NOT on the build server — too slow; same policy as the host app's tests).
    testImplementation("junit:junit:4.13.2")
    // The real org.json (android.jar's copy is a "not mocked" stub in local
    // unit tests). Test-only: the APK keeps the platform's android-runtime
    // org.json.
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}