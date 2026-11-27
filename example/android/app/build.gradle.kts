plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ch.rosenweg4303.rosenweg_basis_beispiel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // rosenweg_basis ab 0.8: flutter_local_notifications (Benachrichtigung) braucht es
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ch.rosenweg4303.rosenweg_basis_beispiel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // rosenweg_basis (commons-rosenweg) verlangt 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Rosenweg-Signierschluessel nur ueber Umgebungsvariablen (Job release in
    // .github/workflows/beispiel.yml, Tag beispiel-v*). Ohne sie: Debug-Signatur,
    // damit `flutter run --release` und die CI-Bauten ohne Schluessel gehen.
    val signierDatei = providers.environmentVariable("SIGNING_STORE_FILE").orNull
    signingConfigs {
        if (signierDatei != null) {
            create("rosenweg") {
                storeFile = file(signierDatei)
                storePassword = providers.environmentVariable("SIGNING_STORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("SIGNING_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("SIGNING_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (signierDatei != null) "rosenweg" else "debug")
        }
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

dependencies {
    // Benachrichtigung (flutter_local_notifications) ueber rosenweg_basis
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
