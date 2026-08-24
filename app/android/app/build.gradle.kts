plugins {
    id("com.android.application")
    // Kotlin 2.x split the Compose compiler out of kotlin-android into its
    // own plugin; the Glance home-screen widget (PartnerWidgetAppWidget)
    // is @Composable, so this is required even though the app has no
    // other Jetpack Compose UI. Version pinned to match the
    // org.jetbrains.kotlin.android version declared in settings.gradle.kts
    // — the two must always match.
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.kehai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on its scheduling path,
        // which doesn't exist below API 26 — so the plugin requires core
        // library desugaring (its README makes this a hard requirement, and
        // the APK build fails outright without it). Kehai never schedules a
        // notification, but desugaring is an all-or-nothing build flag.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.kehai"
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Backports java.time (and friends) to older API levels — paired with
    // `isCoreLibraryDesugaringEnabled` above, required by
    // flutter_local_notifications. 2.1.5 is the version its own README and
    // example app pin; anything 2.1.4+ satisfies the plugin.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Jetpack Glance — renders the partner-status home-screen widget
    // (android/app/src/main/kotlin/app/kehai/widget/PartnerWidget.kt).
    // 1.1.1 is the current stable release; 1.2.0 is still rc-only as of
    // writing.
    implementation("androidx.glance:glance-appwidget:1.1.1")

    // Health Connect — the smartwatch-vitals source (steps + heart rate,
    // kb/platform-android.md "Smartwatches (2026)"), read by
    // KehaiVitalsPlugin. 1.1.0 is the current stable release; the 1.2.0
    // line is alpha-only. It declares minSdk 26 against our 24 — see the
    // `tools:overrideLibrary` note in AndroidManifest.xml for why that's
    // safe here.
    implementation("androidx.health.connect:connect-client:1.1.0")
    // connect-client only depends on coroutines at *runtime* scope, so
    // without this the Kotlin compiler can't see CoroutineScope/launch —
    // and its suspend API is unusable from our plugin.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

flutter {
    source = "../.."
}
