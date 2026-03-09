import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Adicione o plugin do Google Services para Firebase
}

// 🚀 LENDO O COFRE DE SENHAS (SINTAXE KOTLIN)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.suportvips.milhasalert.milhas_alert"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 🚀 CONFIGURANDO A ASSINATURA DINÂMICA
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.suportvips.milhasalert.milhas_alert"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 🚀 MULTIDEX ATIVADO AQUI
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            // 🚀 AVISANDO PARA USAR A ASSINATURA NO MODO RELEASE
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        // 🚀 DESUGARING ATIVADO AQUI
        isCoreLibraryDesugaringEnabled = true
        
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

flutter {
    source = "../.."
}

// 🚀 PACOTE DE TRADUÇÃO DO JAVA ADICIONADO AQUI NO FINAL
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")
    
    // O desugaring também precisa de parênteses e aspas duplas
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}