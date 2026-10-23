package com.goodhub.good_template

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 凭证安全存储平台通道（ui-console U5 收尾；standards §6.1 凭证零明文）。
 *
 * Dart 侧对应 `lib/service/keystore_secret_store.dart`（`kSecretStoreChannel`
 * 同名常量，勿单方改动）。职责边界：
 *  - **AndroidKeyStore 持密钥**（别名 [KEY_ALIAS]，AES-256-GCM，不可导出；
 *    硬件支持时进 TEE / StrongBox）——明文 Key 只在 `doFinal` 边界内存中出现；
 *  - **密文落专用文件**：Base64(IV‖ciphertext+tag) 存独立 SharedPreferences
 *    文件 [PREFS_NAME]，与普通设置（`FlutterSharedPreferences`）物理隔离；
 *  - **进程级、跨 isolate 可见**：UI 主 isolate（MainActivity 引擎）与 Binder
 *    生产 isolate（McpBinderService 引擎）打开同一份密文，各持 Keystore 句柄
 *    解密同值——修掉内存实现的「重启失位 + 跨 isolate 不可见」两缺陷；
 *  - **不设用户认证**：本壳是常驻基础设施，Agent 经 Binder 随调随起须无解锁
 *    读凭证；威胁模型 = 设备物理沦陷（超出壳边界），Keystore 不可导出仍挡住
 *    提取式攻击。此取舍是产品定位决定，非疏忽；
 *  - **fail-closed**：密钥 / 密文任何异常都转 PlatformException
 *    （`KEYSTORE_ERROR`），**绝不**回 null 假装「未配置」——调用方（高德 /
 *    和风 Provider）据此 fail-closed 返机器码，故障可观测。
 *
 * 线程：Keystore 加解密与 SharedPreferences.commit 磁盘 IO 走后台线程，
 * 不占平台主线程（照 SystemCalendarChannel 同款模式）。
 *
 * **两个引擎都要挂**（与 SystemCalendarChannel 同纪律）：MainActivity 与
 * McpBinderService 各自独立 FlutterEngine，漏挂任一侧该引擎内即
 * MissingPluginException（Dart 侧转 SecretStoreErr.unavailable）。
 */
object SecretStoreChannel {
    const val NAME = "com.goodhub.good_template/secret_store"

    /** Keystore 别名。换别名 = 旧密文全部不可解密，仅重大密钥策略迁移时升版。 */
    private const val KEY_ALIAS = "goodtools_secret_store_v1"

    /** 密文专用 SharedPreferences 文件名（与普通设置隔离）。 */
    private const val PREFS_NAME = "goodtools_secrets"

    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES = 12
    private const val ANDROID_KEY_STORE = "AndroidKeyStore"

    /** 密钥生成幂等锁：双引擎/多线程并发首用，防重复 generateKey 覆盖别名致旧密文失守。 */
    private val keyLock = Any()

    fun register(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> handleRead(context.applicationContext, call, result)
                "write" -> handleWrite(context.applicationContext, call, result)
                "delete" -> handleDelete(context.applicationContext, call, result)
                else -> result.notImplemented()
            }
        }
    }

    /** 读凭证：不存在回 null（端口语义），密文损坏抛 KEYSTORE_ERROR（fail-closed）。 */
    private fun handleRead(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: run {
            result.error("INVALID_ARGUMENT", "read 缺 key 参数", null)
            return
        }
        Thread {
            try {
                val encoded = secretPrefs(ctx).getString(key, null)
                    ?: run {
                        result.success(null)
                        return@Thread
                    }
                result.success(decrypt(encoded))
            } catch (e: Exception) {
                result.error("KEYSTORE_ERROR", "凭证读取失败：${e.message}", null)
            }
        }.start()
    }

    /** 写凭证（覆盖）：同步 commit 确认落盘后才回成功——写后即刻读必见。 */
    private fun handleWrite(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        val value = call.argument<String>("value")
        if (key == null || value == null) {
            result.error("INVALID_ARGUMENT", "write 缺 key/value 参数", null)
            return
        }
        Thread {
            try {
                val encoded = encrypt(value)
                val ok = secretPrefs(ctx).edit().putString(key, encoded).commit()
                if (ok) {
                    result.success(null)
                } else {
                    result.error("KEYSTORE_ERROR", "凭证写入未确认（commit 返回 false）", null)
                }
            } catch (e: Exception) {
                result.error("KEYSTORE_ERROR", "凭证写入失败：${e.message}", null)
            }
        }.start()
    }

    /** 删凭证：幂等（不存在也回成功——端口语义是「确保不存在」）。 */
    private fun handleDelete(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: run {
            result.error("INVALID_ARGUMENT", "delete 缺 key 参数", null)
            return
        }
        Thread {
            try {
                secretPrefs(ctx).edit().remove(key).commit()
                result.success(null)
            } catch (e: Exception) {
                result.error("KEYSTORE_ERROR", "凭证删除失败：${e.message}", null)
            }
        }.start()
    }

    /** 密钥（幂等取或建）。Keystore GCM 强制每次新鲜 IV，无需自管随机数。 */
    private fun getOrCreateKey(): SecretKey = synchronized(keyLock) {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv // Keystore GCM 每次随机，长度 12
        val body = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + body, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val raw = Base64.decode(encoded, Base64.NO_WRAP)
        if (raw.size <= IV_BYTES) throw IllegalArgumentException("密文格式异常（过短）")
        val iv = raw.copyOfRange(0, IV_BYTES)
        val body = raw.copyOfRange(IV_BYTES, raw.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        // GCM tag 校验失败抛 AEADBadTagException——密钥轮换/数据损坏时如实上抛，不兜底。
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }

    private fun secretPrefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
