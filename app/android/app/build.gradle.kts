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
    // Jetpack Glance — renders the partner-status home-screen widget
    // (android/app/src/main/kotlin/app/kehai/widget/PartnerWidget.kt).
    // 1.1.1 is the current stable release; 1.2.0 is still rc-only as of
    // writing.
    implementation("androidx.glance:glance-appwidget:1.1.1")
}

flutter {
    source = "../.."
}
