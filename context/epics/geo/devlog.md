---
dev-loop: devlog
format: v1
epic: geo
total-merged: 1
last-merge: 2026-10-24
---

# geo · 变更日志
- [2026-10-24] [验证]: 真机侧载验收通过（用户确认 2026-10-24）：17 项体验修复 + 进场自动定位（含 GPS 冷启动/权限拒/开关关胶囊提示）——域内待办两项真机验收项闭环
- [2026-10-24] [变更]: geo 域深化两洞（geo 8→9 action）：① geo_ip_locate——高德 /v3/ip IP 定位兜底原语（rectangle 取中心点 GCJ-02，省/市/adcode；高德 city 空数组怪癖归一为不出键；解析失败 fail-closed AMAP_PARSE_ERROR）；② geo_current 定位链升级——GPS 优先（source=gps）→ 无权限/硬件失败回退 IP 定位（source=ip，缺省 GCJ02 不绕换算，无 accuracy），两级皆败 PERMISSION_DENIED；复用 GeoHttpProvider 零新端口；③ geo_search_poi 传 near 切 /v3/place/around（radius 生效），否则 /v3/place/text——text 端点不吃 location/radius，旧实现错端点等于静默失效；docs/product/geo.md 表更新（G1 先行）
- [2026-10-24] [验证]: flutter analyze → 0 issue；flutter test → 607 全绿（geo 9 action 对账 + IP 兜底/around 端点 6 例）；arch-guard 全过
