plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.goodhub.goodtools"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.goodhub.goodtools"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 基线 34（Android 14），与同生态其余三家（goodshare / shiguang / goodhub）对齐。
        // 原为 flutter.minSdkVersion（Flutter 3.47.5 默认 24），改此值的原因有二：
        //  ① 引入插件接入 SDK（goodhub-mcp-plugin-core / goodhub-mcp-contract）后，
        //     两个模块的 minSdk 均为 34，app 低于 34 会 manifest merger 直接失败
        //     （uses-sdk:minSdkVersion 24 cannot be smaller than version 34）；
        //  ② goodhub 本地插件链路（Binder 发现 / 随调随起 / 签名权限闸门）本身即 Android 14+ 基线。
        minSdk = 34
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // AIDL 契约（IMcpChannel / IMcpCallback）已随 SDK 拆仓而移除自拷贝：
    // 契约唯一物理副本在独立仓 goodhub-mcp-sdk 的 `:contract` 模块，本仓经 Maven 坐标消费
    // （`com.zzh.goodhub.mcp:goodhub-mcp-contract`），故不再需要开启本模块的 AIDL 编译器
    // （AGP 8+ 默认关闭 → 曾导致 McpBinderService 的 import 全部 Unresolved，见 context/lessons.md）。
    // 2026-10-20 改造：删除 android/app/src/main/aidl/ 后，`buildFeatures { aidl = true }` 一并移除。

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // 插件接入 SDK（goodhub-mcp-plugin-core）：提供 GoodHubPluginService 基类 + @McpTool 注解
    // + 反射派发器。零手写 AIDL——契约（:contract 模块）经 api 依赖传递引入。
    // 本仓业务逻辑在 Dart，故 McpBinderService 重写 handleJsonRpc 接管路由（见该文件头注释）。
    // 版本与 contract_version 绑定，见 SDK 仓 VERSION 文件。
    implementation("com.zzh.goodhub.mcp:goodhub-mcp-plugin-core:0.2.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
