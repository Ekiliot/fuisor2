plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.fuisor.app.fuisor_app"
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
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
        debug {
            // Отключаем оптимизацию для debug сборки
            // Это гарантирует, что все platform channels и плагины работают корректно
            isMinifyEnabled = false
            isShrinkResources = false
            isDebuggable = true
        }
        
        release {
            // --- [КРИТИЧНО] ОТКЛЮЧЕНА ОПТИМИЗАЦИЯ КОДА ---
            // Это ОБЯЗАТЕЛЬНО для работы platform channels и плагинов
            // Без этого Flutter плагины могут не найти методы через reflection
            // и platform channels могут перестать работать
            isMinifyEnabled = false
            isShrinkResources = false
            // -----------------------------------------------

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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}