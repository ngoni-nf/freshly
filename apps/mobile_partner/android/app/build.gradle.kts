plugins {
    id("com.android.application")
    id("kotlin-android")
    // Must come after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "africa.freshly.partner"
    // 36 because flutter_plugin_android_lifecycle, geolocator_android,
    // google_maps_flutter_android and sqflite_android all compile against it.
    // compileSdk only decides which APIs are available at compile time and is
    // backward compatible; targetSdk below is what changes runtime behaviour.
    compileSdk = 36
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
        applicationId = "africa.freshly.partner"
        // API 23 covers roughly the entire installed base in South Africa and
        // Zimbabwe while still giving us runtime permissions.
        minSdk = flutter.minSdkVersion
        // Held at 35 deliberately. Moving to 36 opts into Android 16's
        // edge-to-edge and other behaviour changes, which deserve their own
        // pass rather than arriving as a side effect of a plugin bump.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] =
            System.getenv("MAPS_API_KEY") ?: project.findProperty("MAPS_API_KEY") as String? ?: ""
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
