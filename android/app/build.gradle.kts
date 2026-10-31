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
    // 不声明 ndkVersion：本项目无任何 C/C++ 原生代码，
    // 声明它会让 Gradle 强制校验/现场下载 NDK，在 CI 上就是几百 MB 的随机失败源。
    // （2026-10-28 run 40700839233 因 NDK 包损坏构建失败）

    compileOptions {
        // flutter_local_notifications（>=16.x）的 AAR metadata 强制要求开启
        // core library desugaring，否则 :app:checkDebugAarMetadata 直接失败。
        // Kotlin DSL 里属性名必须带 is 前缀，写 Groovy 的 coreLibraryDesugaringEnabled 会编译不过。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ===== 引擎 so 处理：交给 AGP 自己 strip（2026-10-29 新增）=====
    // 背景：Flutter SDK 的 libflutter.so 是带符号的 165MB 原件，单架构包也会被撑爆。
    // 之前手工 strip Gradle transform 缓存导致 immutable workspace 校验失败（W14），
    // 正确做法是在这里声明：jniLibs 不需要调试符号，让 AGP 在正常 transform 内 strip。
    packaging {
        jniLibs {
            keepDebugSymbols.clear()
            useLegacyPackaging = false
        }
    }
    defaultConfig {
        applicationId = "com.xinyuj.studytracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // 修复：SDK 默认 36，设备 API 35，降为 35 避免未验证的预发布行为分支
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 2026-10-30 体积收敛：工程无任何原生代码，so 只有 libapp.so + libflutter.so，
        // 三 ABI 全打会产出 525MB 的包。真机是 SM-F926U（arm64-v8a），只打 arm64 即可。
        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a")
        }
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
            // 2026-10-30 补上真正生效的开关：此前只有注释没有实体，
            // AGP 9 仍会执行 minifyReleaseWithR8，在 11GB 机器上被 OOM killer 杀死。
            isMinifyEnabled = false
            isShrinkResources = false
            // 2026-10-29 本机(11GB RAM)构建稳定性：显式关闭 R8/资源压缩。
            // W10/W11b 均在 minifyReleaseWithR8 之后被内核 OOM killer 终结
            // （日志无 BUILD FAILED、进程凭空消失、swap 100%）。
            // 关闭后 release 包体积增大，但功能与签名完全不变，用于真机验收。
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

// [2026-10-30] 本机 aarch64，NDK r28c 只提供 linux-x86_64 prebuilt，
// Flutter Gradle Plugin 会注入 configureCMake*/buildCMake* 任务，
// 其唯一目的是让 AGP 拿 NDK strip so 符号；该 clang 在 aarch64 上
// 一执行即 Illegal instruction，导致构建在此处硬失败。
// 本项目无任何 C/C++ 原生代码，故直接禁用这些任务绕开 NDK 链路。
tasks.matching {
    it.name.startsWith("configureCMake") ||
        it.name.startsWith("buildCMake") ||
        it.name.startsWith("externalNativeBuild")
}.configureEach { enabled = false }
// [FIX-A] 修正 flutterBuildRelease 产出无插件注册器的 app.so
// 根因：Flutter 3.47.8 BaseFlutterTaskHelper 使用 android_aot_bundle_* rule，
// 与 tools 侧 android_aot_* rule 是两条独立缓存链。本机 native 链路被 CMake/NDK
// 禁用块切断后，_bundle 打出的 app.so 不含插件注册器（PathProviderAndroid 等 0 命中）。
// 修复：flutterBuildRelease 结束后，用 .dart_tool/flutter_build/*/arm64-v8a/app.so
// （>10MB 且含注册器）覆盖 intermediates/flutter/release/arm64-v8a/app.so。
afterEvaluate {
    val aotRoot = rootProject.file("../.dart_tool/flutter_build")
    tasks.matching { it.name == "flutterBuildRelease" }.configureEach {
        doLast {
            val outRoot = file("${layout.buildDirectory.get()}/intermediates/flutter/release")
            val src = aotRoot.listFiles()
                ?.map { File(it, "arm64-v8a/app.so") }
                ?.filter { it.isFile && it.length() > 10000000L }
                ?.sortedByDescending { it.lastModified() }
                ?.firstOrNull()
            if (src == null) {
                println("[FIX-A] SKIP: no valid app.so under " + aotRoot)
                return@doLast
            }
            val dstDir = File(outRoot, "arm64-v8a")
            dstDir.mkdirs()
            val dst = File(dstDir, "app.so")
            src.copyTo(dst, overwrite = true)
            println("[FIX-A] replaced app.so " + src.absolutePath + " (" + src.length() + ") -> " + dst.absolutePath + " (" + dst.length() + ")")
        }
    }
}
