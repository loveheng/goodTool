package com.goodhub.goodtools

import android.annotation.SuppressLint
import android.content.ContentUris
import android.content.Context
import android.provider.CalendarContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 系统日历平台通道（P2-⑦ source: system）。
 *
 * Dart 侧对应 `lib/service/system_calendar_port.dart`（`kSystemCalendarChannel`
 * 同名常量，勿单方改动）。职责边界：
 *  - **只读**：查询区间内 `CalendarContract.Instances`（已展开 RRULE / EXDATE）；
 *  - **权限引导**（U12b）：`requestCalendarPermission` 未授权时跳转应用设置页；
 *  - **fail-closed**：未授权返回 `PERMISSION_DENIED`，绝不返回空列表假装无日程；
 *  - **时区换算住本层**（设备本地时区是唯一事实来源）：全天事件回传
 *    `YYYY-MM-DD`（B2 浮当日界，end 做排他日回退）；定时事件回传带显式
 *    offset 的 ISO 8601（B3），内核不做二次解释。
 */
object SystemCalendarChannel {
    const val NAME = "com.goodhub.goodtools/calendar"
    private const val METHOD_QUERY_EVENTS = "queryEvents"

    /** U12b：运行时权限申请入口（未授权 → 跳转应用详情设置页引导授予）。 */
    private const val METHOD_REQUEST_PERMISSION = "requestCalendarPermission"

    /**
     * 在 FlutterEngine 上注册 handler。**两个引擎都要挂**：
     * MainActivity（UI/HTTP 调试通道）与 McpBinderService（生产 Binder 通道）各自
     * 独立引擎，漏挂任一侧该通道引擎内即 MissingPluginException（Dart 侧转
     * ERR_CALENDAR_SOURCE_UNAVAILABLE）。
     */
    fun register(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_QUERY_EVENTS -> handleQuery(context.applicationContext, call, result)
                METHOD_REQUEST_PERMISSION -> handleRequestPermission(context.applicationContext, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * U12b 权限申请（fail-closed 引导，不弹假授权）：
     *  - 已授权 → `granted`；
     *  - 未授权 → 打开本应用详情设置页（ACTION_APPLICATION_DETAILS_SETTINGS），
     *    回 `settings_opened`——UI 据此提示「去系统设置授予日历权限，返回后重试」。
     *
     * 为什么不走 Activity.requestPermissions 对话框：MethodChannel 双程回调配
     * onRequestPermissionsResult 需要 Activity 生命周期管道，而壳的后台引擎
     * （McpBinderService）无 Activity 可挂；设置页跳转对两个引擎同构，且授权后
     * 下次查询即生效（权限在查询时判定，非缓存判定）。
     */
    private fun handleRequestPermission(ctx: Context, result: MethodChannel.Result) {
        if (ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR)
            == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }
        try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.fromParts("package", ctx.packageName, null)
            ).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            result.success("settings_opened")
        } catch (e: Exception) {
            result.error(
                "SETTINGS_LAUNCH_FAILED",
                "无法打开系统设置页：${e.message}",
                null
            )
        }
    }

    @SuppressLint("SimpleDateFormat")
    private fun handleQuery(
        ctx: Context,
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        if (ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR)
            != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            result.error("PERMISSION_DENIED", "READ_CALENDAR 未授权：请到系统设置授予日历权限", null)
            return
        }
        val rangeStart = call.argument<String>("rangeStart")
        val rangeEnd = call.argument<String>("rangeEnd")
        val startMillis = parseLocalDayMillis(rangeStart) ?: run {
            result.error("INVALID_ARGUMENT", "rangeStart 须为 YYYY-MM-DD：$rangeStart", null)
            return
        }
        // 区间含末日：Instances 上界取 end 次日 00:00（排他）。
        val endMillisExclusive = (parseLocalDayMillis(rangeEnd) ?: run {
            result.error("INVALID_ARGUMENT", "rangeEnd 须为 YYYY-MM-DD：$rangeEnd", null)
            return
        }) + DAY_MS

        // ContentProvider 查询必须在主线程之外（MethodChannel handler 默认主线程）。
        Thread {
            try {
                val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
                ContentUris.appendId(uri, startMillis)
                ContentUris.appendId(uri, endMillisExclusive)
                val projection = arrayOf(
                    CalendarContract.Instances.EVENT_ID,
                    CalendarContract.Instances.TITLE,
                    CalendarContract.Instances.BEGIN,
                    CalendarContract.Instances.END,
                    CalendarContract.Instances.ALL_DAY,
                    CalendarContract.Instances.EVENT_LOCATION,
                    CalendarContract.Instances.DESCRIPTION,
                    CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
                )
                val out = mutableListOf<Map<String, Any?>>()
                ctx.contentResolver.query(
                    uri.build(), projection, null, null,
                    CalendarContract.Instances.BEGIN + " ASC"
                )?.use { c ->
                    val iId = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
                    val iTitle = c.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
                    val iBegin = c.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
                    val iEnd = c.getColumnIndexOrThrow(CalendarContract.Instances.END)
                    val iAllDay = c.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
                    val iLoc = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)
                    val iDesc = c.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION)
                    val iCalName = c.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
                    while (c.moveToNext()) {
                        val allDay = c.getInt(iAllDay) != 0
                        val begin = c.getLong(iBegin)
                        val end = c.getLong(iEnd)
                        out.add(
                            mapOf(
                                "uid" to c.getLong(iId).toString(),
                                "calendarName" to (c.getString(iCalName) ?: ""),
                                // 同一事件跨天 RRULE 会出现多实例，uid 唯一性由 Dart 合并层加 start 后缀保证。
                                "title" to (c.getString(iTitle) ?: ""),
                                "start" to (if (allDay) localDate(begin) else isoWithOffset(begin)),
                                // Instances.END 对全天事件是排他次日：回退 1s 再取日期，避免末日跨到次日。
                                "end" to (if (allDay) localDate(end - 1) else isoWithOffset(end)),
                                "isAllDay" to allDay,
                                "location" to c.getString(iLoc),
                                "description" to c.getString(iDesc),
                            )
                        )
                    }
                }
                result.success(out)
            } catch (e: SecurityException) {
                result.error("PERMISSION_DENIED", "READ_CALENDAR 被拒：${e.message}", null)
            } catch (e: Exception) {
                result.error("SOURCE_ERROR", "系统日历查询失败：${e.message}", null)
            }
        }.start()
    }

    /** `YYYY-MM-DD` → 本地时区当日 00:00 毫秒；非法返回 null（fail-closed，不兜底）。 */
    private fun parseLocalDayMillis(raw: String?): Long? {
        if (raw == null || !Regex("""^\d{4}-\d{2}-\d{2}$""").matches(raw)) return null
        return try {
            val cal = Calendar.getInstance(TimeZone.getDefault())
            cal.clear()
            cal.set(
                raw.substring(0, 4).toInt(),
                raw.substring(5, 7).toInt() - 1,
                raw.substring(8, 10).toInt(),
                0, 0, 0
            )
            cal.timeInMillis
        } catch (e: NumberFormatException) {
            null
        }
    }

    /** 毫秒 → 本地时区 `YYYY-MM-DD`（全天事件用，B2 浮当日界）。 */
    private fun localDate(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }.format(Date(ms))

    /** 毫秒 → 带显式 offset 的 ISO 8601（B3，如 `2026-10-20T08:00:00+08:00`）。 */
    private fun isoWithOffset(ms: Long): String {
        val base = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }.format(Date(ms))
        val offsetMs = TimeZone.getDefault().getOffset(ms)
        if (offsetMs == 0) return "${base}Z"
        val sign = if (offsetMs >= 0) "+" else "-"
        val abs = kotlin.math.abs(offsetMs)
        val hh = (abs / 3_600_000).toString().padStart(2, '0')
        val mm = (abs % 3_600_000 / 60_000).toString().padStart(2, '0')
        return "$base$sign$hh:$mm"
    }

    private const val DAY_MS = 86_400_000L
}
