---
name: goodTools-docs
description: goodTools 文档体系路由与门禁：docs/ 各域职责定位、docs-lint 触发命令与操作纪律、文档评估方法论。新增、修改、移动或废弃文档前必读。规范机制一律指针到全局 docs-spec，严禁复制正文。
---

# goodTools · 文档体系

本 skill 是 `docs/` 的**项目数据**登记处（域路由表 / lint 命令 / 例外），不是规范机制。规范机制（frontmatter、根目录平铺、移动与引用修复、墓碑协议、README 双向覆盖）一律指针到全局 skill **`docs-spec` §1–§7**，本文件不复制其正文（防双源漂移）。

## 1. docs/ 域路由表（以存量结构为准，不臆造新域）

| 域 | 路径 | 内容定位 |
|---|---|---|
| project（项目接入/工程事实） | `docs/project/` | 工程规范 SSOT（`coding-standards.md`）+ UI 设计规范（`ui-design.md`）+ 功能落点索引（`index.md`）+ 设计稿（`domain_gateway.md`） |
| product（产品设计） | `docs/product/` | 四大能力产品文档（overview / calculator / calendar / geo / weather） |

> 各域下**全量文档明细**以 `docs/README.md` 为唯一事实源（防双源，本表不枚举文档、不记文档数）。

## 2. 机械校验与快速自测

修改任何 `docs/` 内容后，提交前单行触发：

```sh
toolbox run docs-lint   # 全局池工具（别名 dl）；pre-commit-gate 亦自动分派；项目池暂无同名脚本，无 toolbox 时按 docs-spec §6 手检
```

- 校验项：frontmatter 两字段（`status`/`updated`）、根目录平铺、README 双向覆盖（链接存在性 + 孤儿检测）。细则 = `docs-spec §6`。

## 3. 操作纪律（正文机制指针 docs-spec，此处只列本项目动作）

- **新建**：frontmatter（`status` + `updated`）+ 同轮在 `docs/README.md` 加条目——**仅此一处**，不动本 skill、不动 `index.md`。
- **移动/重命名**：按 `docs-spec §5` 同步 README 索引并**全仓 grep 精确文件名修引用**（含各 skill 与代码注释）；断链事故教训 → lessons「docs/终态纪律」。
- **废弃**：按 `docs-spec §4` 墓碑协议（翻 `status: deprecated` + 墓碑行），禁静默删除。
- **域级变迁（新增域/拆分/合并/整体迁移）**：按 `docs-spec §2` 三处同步——`docs/README.md` + `docs/project/index.md` 文档落点表 + 本 skill 域路由表。逐篇文档操作**不触发**本条。

**写后自检（AI 落笔三问，任一命中即删/移；判据正文 = `docs-spec §7` 反模式）**：

1. 这句是**现行事实**，还是**关于事实的历史**（何时新增/迁入/谁拍板）？——历史移交 devlog，正文删。
2. 是否写了「原没有 X」「此前缺失」「暂无 + 解释正常流程」类自证句？——删，只留结论。
3. 是否在复述另一事实源（文档数/文件清单/状态列）？——删，留指针指向唯一事实源（README / frontmatter / index）。

## 4. 文档评估方法论（项目实例；通用骨架由 scaffold 预填）

评估目的不是判断文档好坏，而是决定**依赖深度**。六维判据：

| 维度 | 判据 | 本仓实证 |
|---|---|---|
| D1 时效性 | frontmatter `updated` 是否落后于代码实际变更 | `domain_gateway.md` 设计稿未落地 `lib/`，落成后需回填 index.md |
| D2 账实一致性 | 可机械定位断言（类名/路径/行号/阈值）对代码实证，三态 ✅/❌/❓ | `geo_provider.dart` 行号引用须实测 |
| D3 单源状态 | 同主题有无矛盾表述；指针能否 grep 定位 | 工具面形态描述以 index.md 为唯一事实源 |
| D4 决策状态 | 结论「已拍板/待裁决/已废弃」是否显式 | `domain_gateway.md` 为 draft 评估稿，落地即转正 |
| D5 验证账本 | 变更是否有成对 `[验证]` | 设计稿落地验证 checklist |
| D6 信息密度 | 每条陈述是否携带可行动信息 | 能力矩阵映射表 |

依赖分级（评估输出）：**L3 可直接依赖**（六维全过，作设计前提）｜**L2 抽查依赖**（关键断言动手前实证——读码纪律第③步）｜**L1 仅线索**（过期/缺验证/状态不明任一命中，一切以代码为准）。

使用时机：① 依赖前——文档建图时顺带分级；② 变更后——触及断言同轮 SSOT 回填；③ 收尾时——`::audit` 机械项覆盖 D2/D3（::verify 三态、指针抽查）。

## 5. 本仓例外（存量与 docs-spec 的冲突；不静默改写存量）

- 文档域仅 `project/`/`product/` 两域；frontmatter 严格两字段 `status`/`updated`，与 docs-spec 一致。
- UI 设计规范 SSOT = `docs/project/ui-design.md`，与 `docs/project/coding-standards.md` §1 架构红线一致；UI 代码落点纪律见 goodTools-ui skill。

## 维护协议

- 域路由表只随**域级变迁**更新（`docs-spec §2`），逐篇文档增删不回改本 skill；表内禁记文档数、文件清单等易腐数据，禁写过程叙事（何时新增/迁入/「原没有 X」）——见 `docs-spec §7` 反模式。
- 规范机制变更不回改本 skill；全局 docs-spec 升级时本文件无需改（指针即同步）。
