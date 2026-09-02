import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Play提出用のアップロード鍵。key.properties/*.jksはandroid/直下に置き、gitignore対象
// （絶対にコミットしない）。ファイルが無い環境（CI等）でもデバッグビルドは通るよう、無ければnullのまま扱う。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.goen.goen_app"
    compileSdk = flutter.compileSdkVersion
    // ネイティブ(C++/JNI)コードを使用するプラグインがないため、NDKは不要（自動インストール時の
    // FileAlreadyExistsException等の不安定要因を避けるため明示的に指定しない）。

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.goen.goen_app"
        // 要件定義書 6章「対応端末」: Android 13以上（API 33）を対象とする。
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.propertiesがある（=本番/署名済みビルドをしようとしている）場合のみ正式な鍵を使う。
            // 無い環境（ローカルの`flutter run --release`等）ではdebug鍵にフォールバックする。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
