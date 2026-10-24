---
dev-loop: devlog
format: v1
epic: weather
total-merged: 2
last-merge: 2026-10-24
---
- [2026-10-24] [变更]: 真机反馈两项落地：① 详情并入城市卡——手风琴卡片（_selected→_expandedId 单开；点摘要行就地展开 now+逐日+预警+更新时间，详情不再另起独立区块；展开态箭头翻转被动指示；缓存回放标记并入更新时间行）；② 手势代替按钮——列表行删除 IconButton 全部退役，改 Dismissible 左滑删除（乐观移除满足离场契约，命令派发失败经 store 重读回滚；成功 SnackBar 撤销=同名重添加走 Actor 配额校验）；搜索条箭头钮退役，提交走键盘搜索键（suffix 仅被动进度指示）；页面新增唯一手势说明行「左滑删除 · 点卡片展开/收起详情」
- [2026-10-24] [验证]: flutter analyze → 0 issue；flutter test → 611 全绿（新增 weather_page widget 冒烟 4 例：首帧无按钮/手风琴就地展开收起/左滑删+撤销恢复/多城聚合）；arch-guard 7 条全过
