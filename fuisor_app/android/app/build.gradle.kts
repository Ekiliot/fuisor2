plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fuisor.app.fuisor_app"
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.fuisor.app.fuisor_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // --- [ВАЖНО] ДОБАВЛЕНЫ ЭТИ ДВЕ СТРОКИ ---
            // Это запрещает удалять код плагинов (Hive, PathProvider) при сборке
            isMinifyEnabled = false
            isShrinkResources = false
            // ----------------------------------------

            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Решаем конфликт дублирующихся нативных библиотек (libc++_shared.so)
            // Используем первый найденный файл из конфликтующих библиотек
            // Это решает конфликт между Mapbox (common-ndk27) и ffmpeg-kit-full-gpl
            pickFirsts += listOf(
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/arm64-v8a/libc++_shared.so"
            )
        }
    }
}

flutter {
    source = "../.."
}