---
memo: todos
format: v3
epic: geo
---

# geo · 域内待办
- [x] [2026-10-20] (功能) (层:L1) (重:中) S4 落地 geo 分类 8 个 action（geo_current/geocode/reverse/search_poi/route/static_map/compass/distance），复用 lib/geo 内核与 GeoHttpProvider/LocationSensorProvider (src: 用户)
- [ ] [2026-10-20] (功能) (层:L3) (重:轻) geo_route mode=transit 的 city 自动逆推（geo.md「缺则内核自动逆地理推导」）：当前缺 city 返回 MISSING_ARGUMENT 并给出自愈指引，待补由起点坐标调 geo_reverse 推导城市名 (src: ai)
- [ ] [2026-10-22] (功能) (层:L3) (重:中) 画布夜间模式暗色视觉方案：高德无暗色瓦片（style=7），MapType.night 无等价物；当前深色底过渡，待验证 style=8 叠加或 ColorFiltered 滤镜方案 (src: ai)
- [ ] [2026-10-22] (功能) (层:L3) (重:中) 瓦片源（wprd*.is.autonavi.com/appmaptile，非官方承诺接口）失效降级路径：接回 GeoMapPort 静态图预览（现有 fail-closed 路径），禁加备用瓦片 if-else 分支（decisions 收敛条件①） (src: ai)
- [ ] [2026-10-22] (测试) (层:L3) (重:中) geo_page 全屏布局 + 上滑面板手势的 widget 自动化覆盖：需 HttpOverrides mock 瓦片网络（FlutterMap TileLayer 在 test 环境直连），或用假端口注入后只测面板/搜索框结构；当前靠 analyze + 既有测试 + 真机验收 (src: ai)
- [ ] [2026-10-22] (功能) (层:L3) (重:中) 高德错误（如 ERR_AMAP_KEY_MISSING）的配置引导落地：geo.md 承诺「引导 UI 弹配置卡片」，当前 ErrorLine 只透传机器码，需带「去设置配置 Key」动作入口（跳 HomeShell 设置 Tab） (src: ai)
- [x] [2026-10-20] (集成) (层:L3) (重:中) buildGeoTool 注册进 MCP 线级并注入 Provider（共享 epic S7 已完成）：实际落点是 `lib/tool_face_assembly.dart` **装配件**（非 McpController 内——service 出向不含 tools），HTTP + Binder 双通道共用；注入 `AmapHttpProvider`（真实高德 REST，key 走 KV 懒读 `amap_web_key`/`amap_secret`），定位仍为 `NullLocationSensorProvider`（真实实现待 geolocator，见 domain_gateway 域内待办，此处不双写） (src: ai)
- [x] [2026-10-23] (测试) (层:L3) (重:中) 进场自动定位**真机验收**：本轮已修根因（定位异常冒泡导致卡在硬编码占位起点）并补 13 例假平台单测，但无设备验证——需真机确认「进地图页自动跳到当前位置」「权限拒/定位开关关时胶囊提示可操作且右侧『我的位置』可重试」「GPS 冷启动下低精度回退的实际耗时」 (src: ai)
- [ ] [2026-10-23] (功能) (层:L3) (重:轻) 定位失败提示**分级**：当前统一文案「定位不可用：请检查定位权限与系统定位开关」，未区分「无权限」/「系统定位开关关闭」/「无定位能力」——可经端口扩展诊断字段（端口只返 null 时无法区分），改动面涉及 `LocationSensorProvider` 契约 (src: ai)
