import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 从 android/key.properties 读取签名信息。
// 文件不存在（例如 CI 没注入 Secrets）时 loaded = false，
// release 构建会直接失败并给出明确原因，绝不静默退回 debug 签名
// ——否则每次 CI 产出的包签名都不同，手机上每次都得卸载重装。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.xinyuj.studytracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications（>=16.x）的 AAR metadata 强制要求开启
        // core library desugaring，否则 :app:checkDebugAarMetadata 直接失败。
        // Kotlin DSL 里属性名必须带 is 前缀，写 Groovy 的 coreLibraryDesugaringEnabled 会编译不过。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.xinyuj.studytracker"
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

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile 在 key.properties 里只写文件名（如 study.jks），
                // 路径基准统一钉在 android/keystore/，避免 file() 默认以 android/app/ 为基准造成错位。
                val ksName = keystoreProperties["storeFile"] as String
                val ksFile = rootProject.file("keystore/$ksName")
                if (!ksFile.exists()) {
                    throw GradleException(
                        "[SIGN] 找不到 keystore：${ksFile.absolutePath}。" +
                            "本地请把 study.jks 放到 android/keystore/ 下；CI 请确认「还原签名材料」步骤已把 keystore 解到 android/keystore/。"
                    )
                }
                storeFile = ksFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 正式签名：CI 上由 workflow 从 GitHub Secrets 还原 keystore 并生成 key.properties。
            // 没有 key.properties 时：CI 环境直接构建失败，本地环境退回 debug 但打醒目警告。
            // CI 里绝不允许静默产出 debug 签名包——那种包覆盖安装会失败，等于白跑一次流水线。
            if (hasKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (System.getenv("CI") != null) {
                throw GradleException(
                    "[SIGN] CI 环境缺少 android/key.properties，拒绝产出 release 包。" +
                        "请检查 GitHub Secrets：KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD 是否齐全，" +
                        "以及 workflow 里的「还原签名材料」步骤是否成功执行。"
                )
            } else {
                logger.warn("======================================================")
                logger.warn("[SIGN] 警告：android/key.properties 不存在，release 退回 debug 签名。")
                logger.warn("[SIGN] 该包无法覆盖安装到正式签名的旧包上，仅限本地临时调试使用。")
                logger.warn("======================================================")
                signingConfig = signingConfigs.getByName("debug")
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

// core library desugaring 所需的脱糖库。版本必须 >= 2.0.4，
// 2.1.4 是当前与 AGP 8.x / compileSdk 35 搭配的稳定版本。
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
