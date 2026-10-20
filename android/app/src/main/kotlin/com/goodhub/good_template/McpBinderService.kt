package com.goodhub.good_template

import android.os.Handler
import android.os.Looper
import com.zzh.goodhub.mcp.IMcpCallback
import com.zzh.goodhub.mcp.plugin.GoodHubPluginService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** 端点标识：与 AndroidManifest 的 meta-data 保持一致（值唯一出处，两处共用这组常量）。 */
private const val SERVER_ID = "good_template"
private const val SERVER_TITLE = "GoodTemplate"

/**
 * 模板本地 Binder 插件服务（server 端，goodhub 契约 thirdconnect.md §1.2.2）。
 *
 * **2026-10-20 改用官方 SDK（goodhub-mcp-plugin-core）**：
 * 自拷 AIDL（`android/app/src/main/aidl/`）已删除，契约由 SDK 的 `:contract` 模块提供
 * （契约物理单副本，宿主 goodhub 侧同批删除）。本类不再自写 `IMcpChannel.Stub`，
 * 改为继承 [GoodHubPluginService] 并重写 [handleJsonRpc] 接管路由——
 * 本仓业务逻辑在 Dart（`McpServer.handleJsonRpc`），SDK 的运行时反射派发器扫不到任何
 * `@McpTool` 方法，不接管路由会导致 `tools/list` 返回空、工具全量丢失。
 *
 * 角色边界（§11.3·1）：仅 server 端；不 bindService、不持 DeathRecipient
 * （连接生命周期 / 挂起队列状态机归 GoodHub 宿主 BinderTransport）。
 *
 * 触达 Dart：持有独立 headless [FlutterEngine]（BIND_AUTO_CREATE 随调随起，满足
 * §1.2.5 随调随起——app 被杀也能被拉起跑 MCP），经 MethodChannel `good_template/mcp_binder`
 * 调 Dart 后台 entrypoint（[mcpBinderMain]）→ McpServer.handleJsonRpc。
 *
 * **F1（务必保留）**：对**所有 tools/call**（宿主回调已注册时）走 `_async` + onEvent 终帧切片
 * （修并行调用排队撞 B1 超时）；answerReverse 通道保留契约位（本仓当前不发反向请求）。
 *
 * 线程：AIDL `call` 由 goodhub 在 Binder 线程触发（非主线程），直接阻塞等待 Dart 回传
 * 不触发 ANR（§1.2.3）；首调前经 [ready] 信号解除引擎未就绪竞态。
 */
class McpBinderService : GoodHubPluginService(SERVER_ID, SERVER_TITLE) {

    private var flutterEngine: FlutterEngine? = null
    @Volatile
    private var channel: MethodChannel? = null

    /**
     * 宿主回注的回调副本（F1 分流判定 + 终帧可观测性；volatile 防跨线程可见性）。
     * SDK 基类内部另持有一份（private），本仓这份用于「回调是否在线」判定与 [DEGRADE] 日志。
     */
    @Volatile
    private var hostCallback: IMcpCallback? = null

    /** 引擎主线程 Handler：MethodChannel.invokeMethod 必须在其上执行（@UiThread），
     *  call()/registerCallback() 均在 Binder 线程触发，须 post 过来。 */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Dart 后台 entrypoint 就绪信号：注册完 MethodChannel 处理器后放行 call。 */
    private val ready = CompletableFuture<Boolean>()

    /**
     * 接管全部 JSON-RPC 路由（= 原自写 binder.call 的全部逻辑，行为逐字保持）：
     *  1. 等 Dart entrypoint 就绪（上限 5s，不就绪回 -32000）；
     *  2. F1 分流：宿主回调已注册且 method=="tools/call" → 立即回 `_async` 占位帧
     *     （不占 5s Binder 预算），真实终帧由 dispatch 的 Result 回调经 onEvent 推同 id 终帧；
     *  3. 非 tools/call（initialize/tools/list，均 <1s）与回调缺失时维持同步路径（兼容旧宿主）。
     */
    override fun handleJsonRpc(jsonRpcRequest: String): String {
        val reqId = extractId(jsonRpcRequest) // B3：先取 id，供错误帧回显
        // 等 Dart entrypoint 注册完处理器（上限 5s，对齐 goodhub 冷启 5s，R2）。
        if (!ready.completeFutureOrDefault(false, 5, TimeUnit.SECONDS)) {
            return errorJson(reqId, -32000, "MCP Binder 引擎未就绪（Dart entrypoint 超时）")
        }
        val ch = channel
        if (ch == null) return errorJson(reqId, -32603, "MCP Binder 通道未建立")
        // F1（_async+onEvent 终帧切片，契约 §1.2.2）：回调已注册且为 tools/call 时，
        // call 立即回 _async 占位帧（不占 5s Binder 预算），真实结果由 dispatch 的
        // Result 回调经 onEvent 推同 id 终帧——并行调用不再排队撞 B1 超时。
        // 非 tools/call（initialize/tools/list，均 <1s）与回调缺失时维持同步路径（兼容旧宿主）。
        if (hostCallback != null && extractMethod(jsonRpcRequest) == "tools/call") {
            android.util.Log.i(TAG, "[F1] async dispatch posted: id=$reqId")
            mainHandler.post {
                try {
                    ch.invokeMethod(
                        "dispatch",
                        jsonRpcRequest,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                val frame = result as? String
                                android.util.Log.i(
                                    TAG,
                                    "[F1] dispatch done: id=$reqId emit=${frame != null}",
                                )
                                if (frame == null) {
                                    emitTerminalFrame(errorJson(reqId, -32603, "Dart 返回空响应"))
                                } else {
                                    emitTerminalFrame(frame)
                                }
                            }

                            override fun error(code: String, msg: String?, details: Any?) {
                                emitTerminalFrame(
                                    errorJson(reqId, -32603, "MCP Binder 调用失败: ${msg ?: code}"),
                                )
                            }

                            override fun notImplemented() {
                                emitTerminalFrame(
                                    errorJson(reqId, -32603, "Dart 未实现 dispatch"),
                                )
                            }
                        },
                    )
                } catch (e: Exception) {
                    emitTerminalFrame(
                        errorJson(reqId, -32603, "MCP Binder 调用失败: ${e.message}"),
                    )
                }
            }
            return asyncResultJson(reqId)
        }
        val resultFuture = CompletableFuture<String?>()
        mainHandler.post {
            try {
                ch.invokeMethod(
                    "dispatch",
                    jsonRpcRequest,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            resultFuture.complete(result as? String)
                        }

                        override fun error(code: String, msg: String?, details: Any?) {
                            resultFuture.completeExceptionally(Exception(msg ?: code))
                        }

                        override fun notImplemented() {
                            resultFuture.completeExceptionally(Exception("Dart 未实现 dispatch"))
                        }
                    },
                )
            } catch (e: Exception) {
                resultFuture.completeExceptionally(e)
            }
        }
        // B1：加 per-call ≤5s 超时，避免 Dart 不回（工具死锁/引擎异常）时 Binder 线程永久阻塞（致命）。
        return try {
            val result = resultFuture.get(5, TimeUnit.SECONDS)
            result ?: errorJson(reqId, -32603, "Dart 返回空响应")
        } catch (e: TimeoutException) {
            errorJson(reqId, -32000, "MCP Binder call timeout")
        } catch (e: Exception) {
            errorJson(reqId, -32603, "MCP Binder 调用失败: ${e.message}")
        }
    }

    /**
     * 宿主注册 / 注销回调（= 原自写 binder.registerCallback 的逻辑）：
     * 存下回调副本供 F1 分流判定与可观测性用，并通知 Dart 侧回调通道已建立。
     */
    override fun onHostCallback(cb: IMcpCallback?) {
        hostCallback = cb
        // 通知 Dart 侧回调通道已建立（注册后 tools/call 即走 _async 切片）。
        // invokeMethod 须引擎主线程执行。
        mainHandler.post { runCatching { channel?.invokeMethod("hostCallbackReady", cb != null) } }
    }

    /**
     * 终帧经 SDK 通道推给宿主（F1 义务②：推失败打 [DEGRADE] 日志，防悬挂可观测——
     * goodhub 侧 _pendingTerminal 无终帧即悬挂，靠其 idle 超时兜底）。
     *
     * 用 SDK 的 `tryEmitEvent`（回报成败）而非 `emitEvent`（静默吞掉投递异常）：
     * 后者会吞掉「推帧失败」这个必须可观测的降级信号。
     */
    private fun emitTerminalFrame(frame: String) {
        if (hostCallback == null) {
            android.util.Log.w(TAG, "[DEGRADE] 终帧无处可推（回调已注销）: ${frame.take(200)}")
            return
        }
        if (!tryEmitEvent(frame)) {
            android.util.Log.w(TAG, "[DEGRADE] onEvent 推帧失败（宿主回调断连？）")
            return
        }
        android.util.Log.i(TAG, "[F1] terminal emitted: ${frame.take(80)}")
    }

    override fun onCreate() {
        super.onCreate()
        initEngine()
    }

    private fun initEngine() {
        if (flutterEngine != null) return
        // 独立 headless 引擎（不挂 UI renderer）；与主 isolate 共用 App 进程，随 Binder 拉起。
        // FlutterEngine 构造器内部已通过 FlutterInjector 初始化 FlutterLoader（含资源抽取），
        // 故路径须取「引擎所用的同一个 loader」，绝不可 new FlutterLoader()——新实例未 init →
        // findAppBundlePath 读 flutterApplicationInfo=null → NPE（随调随起全新进程必现）。
        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine) // sqflite/path_provider 等插件注入
        flutterEngine = engine
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            // 兜底：若引擎构造未触发初始化（跨 Flutter 版本差异），显式与 FlutterActivity 同款配对。
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
        }
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        // 系统日历平台通道（P2-⑦）：生产 Binder 引擎与 MainActivity 引擎共用同一实现。
        SystemCalendarChannel.register(engine, applicationContext)
        // 凭证安全存储平台通道（ui-console U5）：生产 Binder 引擎与 MainActivity 引擎共用同一实现，
        // 漏挂则本 isolate 内 SecretStore 不可用（UI 写的 Key 对 Agent 不可见即此病根）。
        SecretStoreChannel.register(engine, applicationContext)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready.complete(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:good_template/mcp_binder_entrypoint.dart",
                ENTRYPOINT,
            ),
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            flutterEngine?.destroy()
        } catch (_: Exception) {
            // 引擎销毁异常忽略。
        }
        flutterEngine = null
        channel = null
        hostCallback = null
    }

    companion object {
        const val CHANNEL = "good_template/mcp_binder"
        const val ENTRYPOINT = "mcpBinderMain"

        /** JSON-RPC error 帧（Binder call 需返回字符串；回显请求 id，见 B3）。 */
        private fun errorJson(id: Any?, code: Int, message: String): String =
            JSONObject().apply {
                put("jsonrpc", "2.0")
                // id 为 null / JSONObject.NULL → 写 JSON null；number/string 原样（自动加引号）
                put("id", if (id == null) JSONObject.NULL else id)
                put(
                    "error",
                    JSONObject().apply {
                        put("code", code)
                        put("message", message)
                    },
                )
            }.toString()

        /** 从请求 JSON 解析 id（number/string/null），供错误帧回显（B3）。 */
        private fun extractId(request: String): Any? = try {
            JSONObject(request).opt("id")
        } catch (_: Exception) {
            null
        }

        private const val TAG = "GoodTemplateBinder"

        /** _async 占位帧（§1.2.2）：call 立即返回，真实终帧经 onEvent 推送。 */
        private fun asyncResultJson(id: Any?): String = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("id", if (id == null) JSONObject.NULL else id)
            put("result", JSONObject().apply { put("_async", true) })
        }.toString()

        /** 从请求 JSON 解析 method（缺失/解析失败返回 null），供 _async 分流判定。 */
        private fun extractMethod(request: String): String? = try {
            JSONObject(request).optString("method", null)
        } catch (_: Exception) {
            null
        }

        /**
         * [CompletableFuture.get] 超时兜底（Kotlin 1.8 无 `completeOnTimeout`，1.9+ 才有）：
         * 等 [ready] 至多 [timeout]；到点未就绪返回 [default]（永不抛，避免 call 挂死）。
         */
        private fun CompletableFuture<Boolean>.completeFutureOrDefault(
            default: Boolean,
            timeout: Long,
            unit: TimeUnit,
        ): Boolean = try {
            get(timeout, unit)
        } catch (_: Exception) {
            default
        }
    }
}
