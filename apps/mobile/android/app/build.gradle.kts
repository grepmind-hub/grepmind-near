plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A production Firebase project has not yet been supplied. Do not let the
// development JSON be used by production, but keep unconfigured builds usable.
tasks.configureEach {
    if (name.startsWith("processProduction") && name.endsWith("GoogleServices") &&
        !file("src/production/google-services.json").isFile) {
        enabled = false
    }
    if (name.startsWith("preProduction") && name.endsWith("Build") &&
        !file("src/production/google-services.json").isFile) {
        doFirst {
            val generated = layout.buildDirectory.dir("generated/res").get().asFile
            val stale = generated.listFiles()?.any {
                it.name.startsWith("processProduction") &&
                    it.name.endsWith("GoogleServices") &&
                    it.walkTopDown().any { entry -> entry.isFile }
            } == true
            check(!stale) {
                "Stale production Firebase resources exist without a production configuration; clean the generated build before continuing."
            }
        }
    }
}

android {
    namespace = "com.abashyaka.app"
    // sms_autofill 2.6.1 compiles against API 37. This changes the compile
    // API only; targetSdk, signing, and the Flutter/Android SDK paths stay intact.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.abashyaka.app"
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

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
        }
        create("production") {
            dimension = "environment"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
