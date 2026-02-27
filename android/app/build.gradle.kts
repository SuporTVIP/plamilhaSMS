plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Adicione o plugin do Google Services para Firebase
}

android {
    namespace = "com.suportvips.milhasalert.milhas_alert"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 🚀 1. DESUGARING ATIVADO AQUI
        isCoreLibraryDesugaringEnabled = true
        
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.suportvips.milhasalert.milhas_alert"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 🚀 2. MULTIDEX ATIVADO AQUI
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// 🚀 3. PACOTE DE TRADUÇÃO DO JAVA ADICIONADO AQUI NO FINAL
dependencies {
    // 🚀 Sintaxe correta para Kotlin DSL (.kts)
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")
    
    // O desugaring também precisa de parênteses e aspas duplas
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}