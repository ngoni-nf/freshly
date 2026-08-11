plugins {
    id("com.android.application")
    id("kotlin-android")
    // Must come after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "africa.freshly.client"
    // 35 is the current stable target. compileSdk only decides which APIs are 
    // available at compile time; targetSdk is what changes runtime behaviour.
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required so java.time and other desugared APIs work on the older
        // handsets that still make up a large share of both markets.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        applicationId = "africa.freshly.client"
        // Flutter's floor, currently 24. This was 23 to reach a little further
        // down the installed base in both markets, but the plugin set has moved
        // past it and fighting that costs more than the handful of Android 6
        // devices it would win back.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] =
            System.getenv("MAPS_API_KEY") ?: project.findProperty("MAPS_API_KEY") as String? ?: "YOUR_MAPS_API_KEY_HERE"
    }

    signingConfigs {
        create("release") {
            storeFile = System.getenv("KEYSTORE_PATH")?.let { file(it) }
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // Fall back to debug signing when no keystore is configured, so a
            // release build is testable locally without shipping secrets.
            signingConfig = if (System.getenv("KEYSTORE_PATH") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // App Bundle splits keep the download small — meaningful when a user is
    // paying for the install out of prepaid data.
    bundle {
        language { enableSplit = true }
        density { enableSplit = true }
        abi { enableSplit = true }
    }
}

flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}
