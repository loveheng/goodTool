---
status: active
updated: 2026-10-20
---

# goodTools · 日历能力（日历基准 + 重要事件标记 + 时间推演）

## 范围

定位为**日历基准信息、重要事件标记与时间推演引擎**（移动端无头壳，UI 仅做渲染，业务逻辑在纯 Dart 内核）。

- 读取设备系统日历与订阅**通用 / 公共**在线 ICS（节假日、调休、二十四节气、公共赛事、行业展会等**只读事件**），向 MCP 客户端提供日历视图与时间推演能力；
- **不做独立会议 / 日程管理**（参会人、会议链接、会议状态追踪由独立日程 App 承接）——本能力聚焦「看」与「算」，不聚焦「排会」；
- 重要事件标记（生日 / 纪念日 / 里程碑）是本能力的**一等公民**，提供增删查与周年 / 倒计时推演。

## 能力清单

- 日历视图：公历 / 农历 / 节气矩阵，法定节假日与调休补班角标，月网格数据。
- 标记：生日 / 纪念日 / 里程碑的增删查，按年 / 农历自动周年展开与倒计时。
- 订阅：添加 / 列出 / 移除通用在线 ICS 源（URL，可带刷新周期）。
- 时间推演：自然日 / 工作日推算、区间跨度与节假日明细、时区投影、相对日期消歧。

## MCP 工具面（形态）

| 工具 | 档 | 入参 | 出参 | 职责 |
|---|---|---|---|---|
| `calendar_query` | R | `{rangeStart, rangeEnd, timezone?, feedIds?, includeSystem?, limit?}` | `{events:[...], hasMore, timezone}` | 按区间查询事件（展开 RRULE，含脱敏） |
| `calendar_feeds` | R | — | `{feeds:[{id, name, url, refreshMin, lastSyncTime, status}]}` | 列出系统源与订阅源 |
| `calendar_subscribe` | W | `{url, name?, refreshMin?}` | `{success, feedId}` | 添加订阅（写，走 CommandGateway + SSRF 护栏） |
| `calendar_unsubscribe` | W | `{feedId}` | `{success}` | 移除订阅（写，仅作用于已存在 feedId） |
| `calendar_refresh` | W | `{feedId?}` | `{success, updatedCount}` | 强制即时同步（写，网络副作用） |
| `calendar_month_grid` | R | `{year, month, firstDayOfWeek?: int, timezone?}` | `{days:[{date, lunar, isWorkday, badge, markerCount, isCurrentMonth}]}` | 整月网格（恒定 42 格，供 UI 绘制与整月自省） |
| `calendar_resolve_date` | R | `{expression, baseDate?, timezone?}` | `{resolvedDate, weekday, lunar, isWorkday, description?}` | 相对自然语言日期消歧（纯函数） |
| `calendar_marker_list` | R | `{rangeStart, rangeEnd, category?}` | `{markers:[{id, title, date, daysRemaining, isAnnual, anniversaryCount?, ordinalCount?, approximate?}]}` | 查询区间标记与周年展开 |
| `calendar_marker_add` | W | `{originalDate, title, category, baseYear?, isAnnual?, isLunar?, leapPolicy?}` | `{success, markerId}` | 添加标记（写，走 CommandGateway） |
| `calendar_marker_delete` | W | `{markerId}` | `{success}` | 删除标记（写，走 CommandGateway） |

| `calendar_date_calc` | R | `{baseDate, delta:{days?,months?,workdays?,hours?}, timezone?}` | `{targetDate, isWorkday, passedWorkdays?, passedHolidays?[]}` | 自然日 / 工作日推算（纯函数） |
| `calendar_date_diff` | R | `{startDate, endDate, excludeWeekends?, excludeHolidays?}` | `{totalDays, workdays, span:{years,months,days,hours}}` | 精确跨度与工作日统计（纯函数） |
| `calendar_workdays_between` | R | `{startDate, endDate}` | `{totalDays, workdays, holidays:[...], adjustments:[...]}` | 区间节假日 / 调休补班明细透视 |
| `calendar_tz_convert` | R | `{datetime, fromTz, toTz}` | `{target, offset, dstActive}` | 时区投影 / 世界时钟（纯函数） |

> 档位：R = 读（Agent 自由调用）；W = 用户委托写（仅已鉴权 MCP 会话内可用，见「信任与授权」）。

## 实现要点

- **ICS 解析**：RFC 5545（`VEVENT` / `RRULE` 展开），纯 Dart 实现，内核不沾 `dart:io`。在线 ICS 聚焦**通用 / 公共只读源**（节假日、调休、节气、公共赛事、行业展会），非个人会议日程。
- **网络取数走注入端口**（类比 `WeatherProvider`）：内核定义 `CalendarFeedProvider` 抽象，具体 HTTP 拉取 ICS 由 service 层实现后注入，守住无头约束（arch-guard R4）。`webcal://` 由加载器规整为 `https://` 后强制 HTTPS。
- **缓存与刷新**：本地缓存解析结果，按 `refreshMin` 周期后台刷新；离线返回缓存，出参带 `isCached` 与 `lastSyncTime` 时效标记。
- **全天与浮动时间**：`DTSTART;VALUE=DATE` 视为浮动当地日界；带时区 / `Z` / `TZID` 时间统一经 `package:timezone` 的 `TZDateTime` 归一化（纯 Dart，详见「时区治理」）。
- **农历与节气内核**：集成纯 Dart 农历转换引擎（1900–2100 公农历双向确定性换算、生肖、二十四节气），支撑 `isLunar` 标记周年推演、`month_grid` 农历角标、`resolve_date` 的 `lunar:` 表达式。

## 隐私（脱敏）

- 设置项 `日程敏感字段过滤` 开启时，自动隐藏事件正文中的电话 / 邮箱（正则脱敏）；策略在数据层执行，UI 只 toggle。
- 日历为敏感数据：**Agent 不直连存储，所有写操作经 `CommandGateway`**；订阅 / 退订 / 刷新属「用户委托写」，仅在已鉴权 MCP 会话内可用（见「信任与授权」）。`query` 等读工具对 Agent 自由开放，但脱敏策略默认对 Agent 视角生效。

## 信任与授权

- 需系统日历读取权限；缺权限时 UI 展示黄色警告卡 + 一键跳转授权（不崩溃）。
- 外部 ICS 源由用户主动订阅，属用户自决的数据边界。

### 授权模型（三档，A 拍板）

MCP 会话的 token 鉴权（`McpServer.tokenProvider` 返回非空）= 用户授权边界。订阅 / 退订 / 刷新属「用户委托写」，经 `CommandGateway` 放行，**不再写「Agent 只读」**。

| 档 | 工具 | 放行条件 |
|---|---|---|
| **R 读** | `calendar_query` / `calendar_feeds` / `calendar_month_grid` / `calendar_resolve_date` / `calendar_marker_list` / `calendar_date_calc` / `calendar_date_diff` / `calendar_workdays_between` / `calendar_tz_convert` | Agent 自由调用 |
| **W 委托写** | `calendar_subscribe` / `calendar_unsubscribe` / `calendar_refresh` / `calendar_marker_add` / `calendar_marker_delete` | 仅当 MCP 会话已鉴权（token 非空） |

**两道硬控制（可落地的代码护栏，非弹窗确认）：**

1. **`subscribe` 的 SSRF / 注入护栏**（最关键）：URL 必须是调用方**显式传入参数**，禁止 Agent 自造或「建议」订阅地址；命令执行器内校验——
   - `webcal://` 规整为 `https://` 后**强制 HTTPS**，拒绝 `http` 回退；
   - 拒绝 `localhost` / 回环与私网地址（防 SSRF 拉内网 ICS）：IPv4 回环 `127.0.0.0/8` 与 RFC 1918 私网 `10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`；IPv6 回环 `::1`、链路本地 `fe80::/10`、唯一本地 `fc00::/7`；
   - 域名 / 格式不匹配直接返回结构化错误码，不静默降级。
2. **`unsubscribe` / `refresh` 仅作用于用户 store 中已存在的 `feedId`**：对不存在的 id 返回明确错误（`unsubscribe` 可幂等返回 success），Agent 无权凭空创建 / 越权操作。

> 不引入 per-call 弹窗确认：当前仅有 `McpController.pushSuggestion`（单向建议）无 confirm 回传通道；本地 token 即代表用户已授权，安全重心放在 **URL 护栏 + 作用域受限**。若 v1 需 per-call 确认，须新增 confirm 回传通道（架构改动，后续单列）。

## 时区治理（Timezone Governance，B 拍板）

### B1 基准时区默认链

不传 `timezone` 时逐级回退，且**回写进响应**的 `timezone` 字段（Agent 无需猜）：

```
用户设置 calendar.timezone  →  设备时区（注入端口 DeviceTimezoneProvider）  →  UTC
```

### B2 全天事件归一化与区间匹配（封死 off-by-one）

- ICS `DTSTART;VALUE=DATE:20261019` 存为**浮动「当地 00:00→次日 00:00」**，无 offset。
- 区间匹配**在生效时区内做，不在 UTC 做**：把 `rangeStart` / `rangeEnd` 转入生效 tz，取其本地日期界 `[d0, d1]`；全天事件日期 `D` 命中当且仅当 `d0 ≤ D ≤ d1`。
- 效果：美东订阅的全天事件在 `timezone=Asia/Shanghai` 查询时按上海日界判断，彻底消除 UTC 上偏一天。
- 出参全天事件：`isAllDay: true` + 日期（或当地日界时间），仍回写 `timezone`（匹配上下文绑定时区）。

### B3 时间表示

出参统一 ISO 8601 带显式 offset（如 `+08:00`），由 `package:timezone` 的 `TZDateTime` 产出（**纯 Dart，满足「内核不沾 `dart:io`」**）。浮动时间（无 Z 无 TZID）按生效时区解释；`TZID` 引用本地时间经内嵌 tz 库解析。

### B4 DST

由 `package:timezone` 处理；跨夏令时切换的会议保持正确墙钟，出参 offset 反映该瞬时的真实偏移。

### B5 tz 数据库注入

默认用 `package:timezone` 内嵌 `latest.tzf`（bundled，纯 Dart 可测）；若宿主需 OTA 更新时区库，再暴露 `TzDataProvider` 注入端口（与 `CalendarFeedProvider` / `WeatherProvider` 同款接缝）。测试可覆写 tz，保证确定性单测。

## RFC 5545 防御约束（C 拍板）

- **C1 无限展开防御**：`calendar_query` 的 `rangeStart` / `rangeEnd` 跨度**硬上限 90 天**；超出直接返回结构化错误码 `ERR_RANGE_TOO_WIDE`（不静默截断，避免 Agent 误以为查到全量）。单事件 RRULE 展开实例上限 **365 次**，独立于区间（防每 15 分钟循环在 90 天内产出 8640 实例）；超限截断并在出参带 `truncated: true` 标记（区间内部分结果仍有价值，故为截断而非错误）。
- **C2 例外与覆盖**：解析器必须处理 `EXDATE`（排除单实例）与独立 `VEVENT` 带 `RECURRENCE-ID`（覆盖单次）——override 是**替换**不是追加；`RECURRENCE-ID` 时区须与主序列同一 tz 的「本地日」比对；`STATUS:CANCELLED` 的 override 视为删除该实例（free/busy 不计入）。无 `COUNT` / `UNTIL` 的无限规则靠区间截断天然安全（区间外本就不返回）。
- **C3 协议规整**（已在实现要点）：`webcal://` → `https://` 强制 HTTPS；重定向跟随设上限（如 3 跳）；拉取超时（默认 10s）回退上次缓存并标 `isCached: true`。

## 结构化出参与确定性契约（D 拍板）

- **D1 分页契约**：统一 `{events:[...], hasMore: bool, nextCursor?: string, timezone}`。固定排序 `startTime asc → uid asc`，保证同输入可重放。零事件显式 `{events:[], hasMore:false, timezone}`。
- **D2 事件对象字段**（轻量视图，剥离会议元数据）：`uid, title, start, end, isAllDay, location, description, source(system|feed), feedId, feedName, timezone, isCached`。`start` / `end` 为带 offset 的 ISO 8601；全天按 B2 规则。解析器内部仍须处理 `EXDATE` / `RECURRENCE-ID` / `STATUS:CANCELLED`（C2）以保证显示正确，但出参**不暴露**参会人 / 组织者 / 会议状态等会议专属字段（由独立日程 App 承接）。
- **D3 结构化错误码**：工具层统一返回 `{ok: bool, code: string, data?/message?}`（或在 MCP `isError` + content 带 `code`），**禁用散文式 `"错误：…"`**（`sample_tool_face` 的散文返回须在日历工具实现时替换）。错误码枚举：`ERR_RANGE_TOO_WIDE`、`ERR_FEED_NOT_FOUND`、`ERR_INVALID_URL`、`ERR_PARSE_FAILED`、`ERR_NETWORK`、`ERR_RATE_LIMITED`。

## 脱敏层级枚举（E 拍板）

设置项 `日程敏感字段过滤` 开启时按等级 mask，数据层执行，UI 只 toggle：

- `PII_MASK_PHONE_EMAIL`：电话、邮箱（事件 `description` / `location` 中出现的联系方式）；
- `PII_MASK_LOCATION`：物理住址类 `location`（家庭住址等敏感地点）。

规则：不可逆 mask（非 tokenize，防重标识）；对**同一原文稳定**（同串同掩码，保确定性）；默认对 Agent 视角 mask。脱敏在 `calendar_query` 出参前统一执行（Markers 为用户私有数据，不涉外部 PII，不在此列）。

## 时间计算与推演工具（F 拍板）

新增 R 档工具（见主表），语义约束：

- **F1 纯函数纪律**：`date_calc` / `date_diff` / `tz_convert` / `resolve_date` 的 `baseDate` / `datetime` / `expression` **显式注入，禁止 `DateTime.now()`**（确定性单测纪律）。`workdays_between` / `month_grid` 非纯函数（读缓存 / 节假日视图），须明确数据来源与 `timezone?` 过滤，tz 按 B 归一。
- **F2 组合顺序**：`date_calc` 的 `delta` **禁止 `months` 与 `workdays` / `hours` 混合**；若同传，按 `days → months → workdays → hours` 顺序应用；工作日跳跃跳过周六日 + 内置中国法定节假日表（含调休补班）。
- **F3 节假日表与 OTA**：纯 Dart 实现须 bundle 一份**版本化中国法定节假日表**（含节假日与调休补班 `adjustments`），经 `HolidayProvider` 注入，并支持**本地 bundle + 静态 JSON OTA 热更**，避免跨年（如 2027 国务院新安排）发版不及时导致判断失真；表带版本号，测试可覆写。
- **F4 date_diff**：`excludeHolidays` 与 `excludeWeekends` 独立；`workdays` 跳过周末 + 法定假；`span` 严格处理大小月 / 闰年（用日期成分差而非毫秒相除）。
- **F5 tz_convert**：时区投影 / 世界时钟，返回目标时区时间戳 + offset + DST 状态，避免 Agent 自算 DST。
- **F6 resolve_date / month_grid / workdays_between**：见「日期消歧与月网格」「区间工作日明细透视」各节。

## 生产级契约：幂等 / 频控 / 唯一性 / Schema（G 拍板）

- **G1 幂等**：`subscribe` 同 url 幂等（返回已有 `feedId` 或报错，不建重复源）；`refresh` / `unsubscribe` 对不存在 `feedId` 明确错误（`unsubscribe` 可幂等 success）。
- **G2 频控**：`refresh` 最小刷新间隔（如 30s）+ 单 feed 并发锁，防 Agent 循环调用打爆网络。
- **G3 缓存生命周期**：`unsubscribe` 必须清该 `feedId` 缓存与 `lastSyncTime`；离线回退带 `isCached` + `lastSyncTime` 时效；超时（10s）回退标 `isCached: true`。
- **G4 事件唯一性**：跨源合并（system + feed）UID 可能碰撞，事件主键用 `feedId:uid` 复合键，否则合并展示错乱。
- **G5 Schema 契约**：每个工具经 `McpToolFace.schemas()` 登记**严格 JSON Schema**（`required`、枚举 `source` / `category`、date ISO 8601 格式约束）。当前 doc 为散文表，实现时必须 pin schema——这是「确定性调用」的物理落点。

## 重要事件标记（Markers，定位修正核心）

一等公民数据模型（不依赖系统日历 / ICS，存于用户私有 store）：

```
Marker {
  id: string
  title: string
  originalDate: string   // 真实起始完整日期，如 "2018-10-19"（公历）或 "2018-08-15"（农历，isLunar=true）
  baseYear: int          // 起始年，用于计算 anniversaryCount = targetYear - baseYear（标准满周年；平年 2-29 按 02-28，isLunar 闰月按 leapPolicy）
  category: "birthday"|"anniversary"|"milestone"
  isAnnual: bool         // 按年循环（生日 / 纪念日）
  isLunar: bool          // 按农历对齐（如"农历八月十五"）
  leapPolicy: "ignoreLeap"|"strictLeap"|"followRegular"  // 闰月策略，默认 "ignoreLeap"
}
```

- `isAnnual: true` 在 `marker_list` 查询区间内**自动展开**为各周年实例，并算力字段：
  - `anniversaryCount`：标准满周年（targetYear − baseYear，如 2018→2026 为第 8 周年）；生日场景可选附带 `ordinalCount`（第 N 个生日 = targetYear − baseYear + 1）。
  - `daysRemaining`：距下一次纪念日的倒计时天数（可为负表示已过去）；
  - `isLunar: true` 时先按农历引擎对齐到对应公历日再算（见下）。
  - **浮动日界（跨时区）**：所有 `Marker` 恒定视为**浮动当地时间（Floating Local Date）**，在任意生效时区下均严格按该时区当地公历 `YYYY-MM-DD` 匹配，不受 UTC Offset 影响而跨日抖动（用户在东八区标「10-19 朋友生日」，到西五区仍显示当地 10-19）。
  - **公历 2/29 平年对齐**：若 `isLunar: false` 且 `originalDate` 为 02-29，平年统一对齐至 `02-28` 并打 `approximate: true`。
  - **`originalDate` 为年份单一真相源**：`marker_add` 入参 `baseYear` 可选；若 `originalDate` 为完整 `YYYY-MM-DD`，内核自动派生 `baseYear`，仅当传入无年份格式（如 `"10-19"`）时才必须显式补 `baseYear`，避免双参冲突。
- 写操作（`marker_add` / `marker_delete`）走 `CommandGateway`（W 档，受 A 授权模型约束）；`markerId` 为内部主键，删除仅作用于用户自有标记，Agent 无权越权删他人数据。

## 农历与纪念日引擎（Lunar Engine）

- 集成**纯 Dart 农历转换库**（1900–2100 公农历双向确定性换算、生肖、二十四节气），满足「内核不沾 `dart:io`」与确定性单测。
- `isLunar: true` 的标记周年推演：以农历月日（如八月十五）对齐到目标公历年的农历同日；遇闰月按 `leapPolicy` 处理：
  - `ignoreLeap`（默认）：仅对齐正规月份（无论当年有无闰四月，均过正常四月）；
  - `strictLeap`：若标记创建于闰月（如闰四月初五），仅在有该闰月的年份触发，平年不触发；
  - `followRegular`：平年自动对齐对应平月，并打 `approximate: true` 标记，避免静默错算。
- `month_grid` 每格输出 `lunar`（农历月日 / 节气名），供 UI 角标与 Agent 整月分析。
- `resolve_date` 支持 `lunar:2026-08-15` 表达式，返回对应公历 `resolvedDate` + `lunar` 回显。

## 区间工作日明细透视（calendar_workdays_between）

- 入参 `{startDate, endDate}`，出参在 `date_diff` 基础上**展开明细**：

```json
{
  "totalDays": 10,
  "workdays": 6,
  "holidays": [{"date": "2026-10-01", "name": "国庆节"}],
  "adjustments": [{"date": "2026-10-10", "name": "补班", "type": "workday"}]
}
```

- `holidays` 来自 `HolidayProvider`（含国务院公布的法定节假日）；`adjustments` 为调休补班日（法定假挪用的周末上班），二者共同决定 `workdays` 统计，供 Agent 拼假策略 / 工期推演，避免逐日往返查询的 Token 损耗。
- 确定性：`startDate` / `endDate` 显式注入，节假日表经 `HolidayProvider` 可覆写。

## 日期消歧与月网格（calendar_resolve_date / calendar_month_grid）

- **`calendar_resolve_date`**（R，纯函数）：`{expression, baseDate?, timezone?}` → `{resolvedDate, weekday, lunar, isWorkday, description?}`。
  - `expression` 支持：`"next_friday"`、`"today+3"`、`"q4_start"`、`"lunar:2026-08-15"`、`"mid_autumn"`（内置节日别名表）等；`baseDate` 缺省按 B1 默认链，但**实现内不得调用 `DateTime.now()`**，由调用方或默认链注入。
  - 农历 / 跨月跨年 / 节日别名由农历引擎 + 别名表解析，杜绝 LLM 自算幻觉。
- **`calendar_month_grid`**（R）：`{year, month, firstDayOfWeek?: int, timezone?}` → `{days:[{date, lunar, isWorkday, badge, markerCount, isCurrentMonth}]}`（恒定 42 个元素）。
  - `firstDayOfWeek`（默认 1=周一，7=周日）决定 42 格矩阵的列起始，避免中 / 欧首日习惯差异导致的整体列错位；
  - `badge` 枚举：`holiday` / `adjusted_workday` / `solar_term`（节气）/ `none`；
  - `markerCount`：当日重要标记数量（含周年展开实例），供 UI 圆点；
  - 出参**恒定 42 个元素（6 行 × 7 列）**，当月前后非当月日期同样填充并标 `isCurrentMonth: false`（置灰），确保移动端切月视图高度物理恒定、无 Layout Shift；农历 / 节气 / 休班算法在**纯 Dart 核心层计算**（arch-guard R4，不落在 UI），既供渲染也供 Agent 整月自省。

## 相关文档

- 产品概述：[overview.md](overview.md)
- UI 开发规范：[../project/ui-design.md](../project/ui-design.md)

## 决策日志
- [2026-10-20] [决策]: **节假日表绝不编造**——国务院年度安排凭记忆填充会造成错误的「今天放假/补班」判断（比不判断更糟），故默认 `EmptyHolidayProvider`（version `empty-0`）且出参回写 `holidayTableVersion` 让 Agent 可知判断依据；真实表待官方数据导入（P2-①）。
- [2026-10-20] [决策]: **跨度算法用逐月推进而非月份相减借位**——借位法在 `1/31 → 3/1` 上会算出负数天内差（借的是 end 所在上月的天数）。改为从 start 逐整月推进（先年后月）直至再进一月即超过 end，残余即天数。
- [2026-10-20] [决策]: **校验职责下沉 Actor**——必填与 SSRF 校验在命令执行器（service 层）内做：`buildCommand` 无法返回 `SubActionResult`，在工具层抛异常会被内核兜成散文错误，破坏结构化错误口径。
- [2026-10-20] [决策]: **本轮不装配进 `tool_face_assembly`**——6 个 R 档的 ICS/农历/时区源与 5 个 W 档的 Actor 均未落地，接线等于线级摆 14 个恒失败工具（与 S5「能力不假上线」同一纪律）。待 P2 源就绪后一并装配，届时线级 = 4 域 26 action，与 `domain_gateway.md` 矩阵闭环。
- [2026-10-20] [决策]: **SubAction 增 `validate` 前置校验钩子（G6）**——`buildCommand` 只能返回 `Command`、无法表达失败，必填/护栏/幂等这类可预期失败此前只能抛异常，被内核兜成散文错误、破坏 D3 结构化错误口径。拦截顺序固定 `admits → validate → dispatch`（未授权会话不触达入参校验，不泄露可枚举信息）。已同步 coding-standards §3.3 G6。
- [2026-10-20] [决策]: **SSRF 护栏从 `lib/tools/calendar/url_guard.dart` 上移到 `lib/mcp/calendar_provider.dart`**——Actor（service 层）也要复检，而 standards §1 里 `service` 出向只含 `mcp`/`action`，不得 import `tools`；放内核两侧复用。
- [2026-10-20] [决策]: **Actor 输出统一为 `{'success':…}` 信封，isError 由信封派生**（`SubActionResult.fromActor`）。没有这一步，业务失败（URL 被护栏拒绝等）在 MCP 顶层仍是 `isError:false`，客户端误判成功、Agent 基于失败结果继续推理。
- [2026-10-20] [决策]: **ICS 解析器与 PII 脱敏住内核（lib/mcp）而非 tools**——service 层 Actor/Provider 也要复用，而 standards §1 里 `service` 出向只含 `mcp`/`action`，不得 import `tools`（与 SSRF 护栏上移同一理由）。
- [2026-10-20] [决策]: 装配默认用内存标记 store 而非 SharedPrefs——装配函数是**同步**的（`SharedPreferences.getInstance()` 是异步），持久化 store 需调用方异步打开后注入（参数已留）。语义可接受：Binder isolate 本就每次拉起重建、HTTP 侧随 app 生命周期；真实持久化替换时注入即可，无装配面改动。
- [2026-10-20] [决策]: **strictLeap / followRegular 的闰月语义在内核 expand 层完整实现，但 marker_add 入参面暂不放行「闰」格式**——calendar.md 只定义了 `YYYY-MM-DD` 农历格式（无闰月位），扩 W 档 validate 正则会连带改 Actor 与 P2-⑤ 测试面；当前经工具面创建的闰月标记不存在，三策略语义以直接构造 `CalendarMarker` 的单测钉死（`2025-闰6-05` 源）。入参面扩展列为断点候选，不静默假装支持。
- [2026-10-20] [决策]: **resolve_date 的相对表达式与不带年份的别名必须显式传 baseDate**——F1 禁 `DateTime.now()`，B1 链只提供时区回退不提供「今天」，显式报 MISSING_ARGUMENT + suggestion（可改用 `mid_autumn:2027` 带年份格式）是唯一确定解释。已知别名先认名再问基准：未知别名直接 INVALID_ARGUMENT，不落「缺 baseDate」误报（单测抓到的首版顺序 bug）。
