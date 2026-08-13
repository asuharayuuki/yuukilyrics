plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    ?: "${System.getProperty("user.home")}/.android/debug.keystore"
val releaseKeystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: "android"
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "androiddebugkey"
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: "android"

android {
    namespace = "com.example.yuukilyrics"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.yuukilyrics"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 3
        versionName = "0.1.0"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        create("release") {
            storeFile = file(releaseKeystorePath)
            storePassword = releaseKeystorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts.add("**/libc++_shared.so")
            pickFirsts.add("**/libavcodec.so")
            pickFirsts.add("**/libavformat.so")
            pickFirsts.add("**/libswscale.so")
            pickFirsts.add("**/libavutil.so")
            pickFirsts.add("**/libavfilter.so")
            pickFirsts.add("**/libswresample.so")
        }
    }
}

flutter {
    source = "../.."
}
