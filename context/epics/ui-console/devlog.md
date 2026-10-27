---
dev-loop: devlog
format: v1
epic: ui-console
total-merged: 2
last-merge: 2026-10-27
---
- [2026-10-27] [变更]: 年视图恢复（用户拍板，撤销同日「年视图撤除」口径）：① 年条带与月条带同构（ListView+_GlidePhysics+±2 预挂载，纵滑跨年惯性）；② 入口双通道（§6）：双指捏合收缩月→年/张开年→月（Listener 原始指针检测，不进手势竞技场——单指滚动零干扰）+ 点标题切换（_RangeNav 增 onTap）；③ 点迷你月落月（滑行到目标月）；④ 键盘 ↑↓ 按模式分派；⑤ 模式切换用 Stack+Offstage 双条带常驻——AnimatedSwitcher 会 unmount/重挂载子树致条带 offset 丢失 + glide 撞未挂载 controller 被丢弃，弃用；⑥ 年条带独立 _yearPageHeight——年/月视口高不同（月模式上方固定表头占位），共用页高致 itemExtent 失配两页同屏
- [2026-10-27] [验证]: arch-guard 7/7；analyze 0 issue；flutter test 632 全过（新增年视图回归 3 例）；build-apk --install 成功
- [2026-10-27] [SSOT 修正]: 旧 2026-10-27 [日历外壳·年视图撤除] 年视图冗余撤除 ➔ 新 真机手感过关后用户拍板恢复年视图——年条带以月条带同构无限滚动条回归（纵滑跨年惯性 + ±2 预挂载），入口双通道 = 双指捏合（月→年收缩/年→月张开，Listener 原始指针）+ 点标题；点迷你月落月；「[日历外壳] 2026-10-23 条目中双指捏合收缩→年视图」口径随之复活，快甩进年视图入口不恢复（捏合/标题双通道已覆盖）
- [2026-10-27] [变更]: 真机联调修复：AppBar 标题槽 InkWell 真机 tap 不响应（同 AppBar TextButton 正常、宿主机/单测均无法复现）→ _RangeNav 改 GestureDetector(behavior: opaque)，标题切换稳定；lessons §ui 登记
- [2026-10-27] [验证]: arch-guard 7/7；analyze 0 issue；flutter test 632 全过；build-apk --install 成功；真机点标题进年视图锚定 2026 整页（10月高亮）截图取证
- [2026-10-27] [变更]: 事件面板全屏盖住日历条带时，向上滑翻月被面板抢手势——补悬浮按钮（Scaffold.floatingActionButton，仅 `_showEvents` 时出现）按当前模式向上滚一屏（月→上一月 / 年→上一年 / 年份块→上一块），`Icons.keyboard_arrow_up`；既解可达性冲突又是 §6 双通道可见控件（日历「上一月」原只有滑动 + 键盘 ↑，无等价可见控件）。FAB 为独立点击热区，不与面板上滑冲突
- [2026-10-27] [变更]: 年视图回归补 2 例（纵滑跨年 + 纵滑后点迷你月落月对位），判据用「页面中心在屏内」的 `_visibleYearGrid`/`_countVisibleYearGrid`（预挂载 ±2 会建相邻年页，旧「findsOneWidget」误判；真正判据是「仅一页中心在屏」防 itemExtent 失配两页同屏）。analyze 0 issue；flutter test 634 全过
- [2026-10-27] [变更]: 日历页两处体验修复——①事件快照读取失败时清空 _events 旧日期残留（原会以旧日事件冒充新日期）；②「今天」归位不再强制展开事件面板，面板已开才刷新为今天的事件
- [2026-10-27] [验证]: flutter analyze → 零 issue（4.6s）；未跑全量测试：纯 UI 局部小修，非数据层/协议/跨文件重构
- [2026-10-27] [变更]: 日历体验补全三项——①月格密度点 1~3 枚分级（日程+标记总数 clamp，修文档与实现不符）；②事件面板条目点按展开完整描述（didUpdateWidget 换日期重置展开态，无描述不可点，仍不含地点敏感字段）；③AppBar 新增「跳转到指定日期」（Icons.event + showDatePicker，选后走 _onDaySelected 选中+展开面板，月条带滑行落月）
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（4.6s）；flutter test 634 全过
- [2026-10-27] [变更]: 日历体验第二轮五项——①事件面板空态加「重新读取」重试按钮（onRetry 回调）；②面板把手关闭热区加高（上下留白 4→8px）；③移除键盘 ↑/PageUp 反直觉「下一月」绑定（保留 ↓/PageDown = 上一月）；④年视图迷你月补读屏 Semantics（年月 + 当前月态，_miniMonthSemanticsLabel）；⑤三级缩放切换补入场 scale/fade 过渡（Offstage 常驻结构不动，_kickZoom 六个切模式点接入，reduced motion 直落）
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（4.5s）；flutter test 634 全过
- [2026-10-27] [变更]: 日历体验收尾两项低频项——①权限提示残留：WidgetsBindingObserver 生命周期 resumed 且有提示时自动 force 重读月总览并清年密度缓存，读取成功即清提示（从系统设置授权回来不再挂着旧提示）；②月/年/年份块页缓存整表清空改窗口外定向摘除（月 ±4 月 / 年 ±2 年 / 块 ±1 块，锚标题落定位），快甩远途回跳不再全量重建可见页
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（4.3s）；flutter test 634 全过
- [2026-10-27] [变更]: 面板全屏切换按钮从把手行右上角移至 Scaffold FAB 位（原「向上滚动一屏」FAB 撤除，_glideCurrentUp 删除）——GlobalKey 挂 _EventPanel key 由父级触发 _toggleFullscreen，onFullscreenChanged 回报全屏态驱动 FAB 图标/tooltip；把手行仅剩抓手+日期（Row 层简化）；代价：面板全屏态下「上一月」无可见控件（§6 双通道缺口，靠关面板后滑动/今天/跳转日期补偿，评估经用户拍板）
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（5.4s）；flutter test 634 全过
- [2026-10-27] [变更]: 修日历进页空白屏——上轮缩放过渡引入的两个坑：①_zoomAnim 初始 value=0 且 _zoomFade 起点全透明，首帧日历 Stack 以透明度 0 渲染；修复 initState 置 value=1.0，_kickZoom 仅模式切换时从 0 重播；②控制器 late final 初始化器读 MediaQuery.disableAnimationsOf(context)，initState 首触即在 initState 期间 dependOnInheritedWidget 断言崩溃（14 例测试挂）；修复时长固定 200ms，reduced-motion 判断收敛到 _kickZoom（build 期）
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（5.2s）；flutter test 634 全过
- [2026-10-27] [变更]: 面板把手 fat-finger 修正（真机反馈热区太小手指太粗、触摸串到日历格操作混乱）——①把手热区大幅加高（上下留白 8→16px + 日期行下 16px，可点/可拖区约 100px 高）；②点把手语义分级：非 peek 态点按降档回 peek（误触不丢面板，原「点按=直接关闭」致想拖没拖动时面板消失、手指继续滑落到日历格），peek 态点按才关闭；拖拽行为不变
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（5.3s）；flutter test 634 全过
- [2026-10-27] [变更]: 面板滚动接力链（内容优先、面板兜底，Google Maps 式 bottom-sheet 手势）——①事件列表包 NotificationListener 链式手势：列表能滚→上滑滚内容不拦截；列表在顶继续下拉（overscroll<0）→面板跟手降档、松手过阈值关闭否则吸附最近档；内容滚不动（maxScrollExtent==0）上推→面板跟手升档至全屏；把手拖拽进行中不接力、仅吃 depth 0；②把手日期行加方向 chevron（未全屏朝上=可上推展开、全屏旋转 180° 朝下=下拉收回，AnimatedRotation 200ms）；直接「面板内上滑=全屏」否决：长列表将永远滚不到底，内容滚动优先是 HCI 正解
- [2026-10-27] [验证]: arch-guard 7/7；flutter analyze 零 issue（4.6s）；flutter test 634 全过
- [2026-10-27] [变更]: 面板默认档位 peek→半屏——事件列表默认首屏可读（peek 200px 看不全，下意识上推的起点就该给足内容）；_panelH 延迟初始化（_halfH 依赖 MediaQuery，禁在 initState 读，didChangeDependencies/didUpdateWidget 经 _initPanelHOnce 一次性置位防重复覆盖拖拽结果）；peek 保留为下拖降档/快速瞄一眼档，点把手降档链（half→peek→关）语义不变
- [2026-10-27] [验证]: 默认半屏档位验证：arch-guard 7/7 + analyze 零 issue + test 634 全过（2026-10-27 第二次跑批）
- [2026-10-27] [变更]: 点把手改回一次直接关闭（用户拍板）——默认半屏后原降档中转（half→peek→关）要点两次才消失，太啰嗦；热区已加大 + 下拉/滚动接力链都在，误触代价可控；降档语义保留在拖拽/列表顶部下拉链路，点按不中转
- [2026-10-27] [验证]: arch-guard 7/7；analyze 零 issue（4.1s）；test 634 全过
- [2026-10-27] [变更]: 滚动动画优雅度统一——①病灶：程序化滑行（键盘/归位/点选落位）走 easeOutCubic 定时缓动（起步即峰值速度、猛冲急停），与手势惯性的临界阻尼弹簧两副面孔；②程序化滑行统一改 _GlidePhysics 同款弹簧（kSpring/kTolerance 公开），经公开的 BallisticScrollActivity+beginActivity 驱动（SDK 无 ScrollPosition.animateWith，DrivenScrollActivity 只收 duration+curve，查证后选 Ballistic 路径：收敛后 goBallistic(≈0) 经 physics 判 idle 终止干净）；③面板 snap/关闭改速度连续弹簧——把手拖拽松手末速（primaryVelocity）直接喂入 SpringSimulation，修「松手顿挫」（原 Tween 零速起步速度不连续，最刺眼病灶）
- [2026-10-27] [验证]: arch-guard 7/7；analyze 零 issue（4.2s）；test 634 全过
- [2026-10-27] [变更]: 修 FAB 泄露——显示条件 _showEvents 未限定视图模式，切年/年份块视图后全屏按钮跟着浮现，点击操作的是 Offstage 里看不见的月视图面板（零反馈），观感即「到年视图回不去月视图」；修复：FAB 仅 _showEvents && 月视图显示，回月通道 = 捏合张开 / 点标题循环
- [2026-10-27] [验证]: arch-guard 7/7；analyze 零 issue（4.4s）；test 634 全过
- [2026-10-27] [变更]: 修 FAB 全屏点击复现 bug（复现测试 test/calendar_fab_fullscreen_test.dart 取证）——三层根因：①AnimationController 默认值域 0.0–1.0 把面板高度弹簧钳到 1px（点全屏后面板塌没），改 AnimationController.unbounded；②面板全屏挤压条带到 0 高，月模式固定件（告警行/星期表头/间隙 ~9.4px）装不下 RenderFlex overflow×272 满屏黄黑条纹——LayoutBuilder tight<120 时固定件让位消失 + _DayCell 包 FittedBox(scaleDown) 兜底；③0 高退化布局下小数尾差互打（0.358px 溢出）——_fullH 顶部留 48px 呼吸条，条带恒非退化
- [2026-10-27] [验证]: arch-guard 7/7；analyze 零 issue（4.2s）；test 635 全过（含新增 FAB 全屏链路回归钉）
- [2026-10-28] [变更]: FAB 全屏链路回归钉定位判据修正——今日格候选筛选由「中心点落在页矩形内」收紧为「整格完整落在页矩形内」（相邻缓存月页只露几像素在条带视口顶部，中心点在页内但被视口裁剪+固定 WeekdayHeader 覆盖，tap 必脱靶 → 面板未展开误报）；lessons §ui 登记
- [2026-10-28] [验证]: 发版前质检——arch-guard 7/7；analyze 零 issue（4.6s）；flutter test 635 全过
