# Base Defence GDD（游戏设计文档）

本目录是 Base Defence 绿地重写的**规则真源**。specifier 按系统各领一张 ticket，只读本目录与 `CONTEXT.md` 就能写出该系统的 feature；不需要、也不应该读 `legacy/lua-port` 分支的旧代码。

## 真源与约定

- **规则与数值照上游 Unity 源码**（`Spoke/Examples/05_BaseDefence`），已逐条抄录到各系统文档；数值冲突以本 GDD 为准，改数值须开 ADR。
- **例外：棋盘输入照目的地**（固定上帝视角 + 点击/触摸），不照 Unity 的 WASD 平移相机。
- **术语用 `CONTEXT.md`「玩法」一节**的词，feature 里不得另造同义词。
- **feature 是纯规则层**：不出现 tick、客户端、GM、快照、EUI、节点路径。时间用"秒"，动作用"玩家开始对局 / 放置 / 敌人投弹"这类领域动词。
- **每个 feature 自包含**：背景直接给定前置状态（"一座已通电的 Turret 位于 (3, 0)"），不引用别的 feature。跨系统交互写在**受影响方**的 feature。
- **随机只断言约束**，不断言具体随机结果（方向属于四边之一、层级不超过解锁上限、预算耗尽即停）。
- **表现层 feature 只断言"状态 X 时显示 Y"**，不断言像素、材质、动画细节。
- 文件名英文、内容中文 Gherkin、首行 `# language: zh-CN`。

## 系统清单与 feature 落点

| # | 系统 | GDD | feature |
|---|---|---|---|
| 0 | 世界与初始布局（共享事实，无 feature） | `00-world.md` | — |
| 1 | 对局流程 | `01-match-flow.md` | `features/gameplay/match-flow.feature` |
| 2 | 经济与矿点 | `02-economy.md` | `features/gameplay/economy.feature` |
| 3 | 电网 | `03-power-grid.md` | `features/gameplay/power-grid.feature` |
| 4 | 放置 | `04-placement.md` | `features/gameplay/placement.feature` |
| 5 | 侦测与火力 | `05-detection-fire.md` | `features/gameplay/detection-fire.feature` |
| 6 | 维修 | `06-repair.md` | `features/gameplay/repair.feature` |
| 7 | 敌人与波次 | `07-enemies-waves.md` | `features/gameplay/enemies-waves.feature` |
| 11 | HUD 侧栏 | `11-hud.md` | `features/presentation/hud.feature` |
| 12 | 播报与边缘警示 | `12-announcer.md` | `features/presentation/announcer.feature` |
| 13 | 覆盖圈与链路 | `13-overlays.md` | `features/presentation/overlays.feature` |
| 14 | 悬停信息 | `14-hover.md` | `features/presentation/hover.feature` |
| 15 | 血条与单位特效 | `15-health-fx.md` | `features/presentation/health-fx.feature` |
| 16 | 棋盘输入 | `16-board-input.md` | `features/presentation/board-input.feature` |

## 系统依赖图

```
对局流程 ──冻结/解冻──▶ 全部系统
电网 ──通电状态──▶ 经济(矿点) / 侦测与火力 / 维修 / 放置(合法落点)
敌人与波次 ──进攻期──▶ 经济(停采)
敌人与波次 ──炸弹伤害──▶ 建筑血量 ──▶ 电网(Relay 离场断电) / 对局流程(Core 离场失败)
侦测(Radar 揭示) ──▶ 火力(Turret 开火) ──▶ 敌人血量 ──▶ 波次(全灭进入下一波)
经济(资金) ──▶ 放置(可负担/扣费)
经济(矿点采空) ──▶ 对局流程(胜利)
```

规则归属原则：**谁被影响，规则写在谁那里**。"Relay 被毁导致分支断电"在电网；"未通电 Turret 不开火"在侦测与火力；"进攻期停采"在经济。

## 验收接缝（供 to-spec 引用）

只用一个接缝：现有无头 harness（SE 桩 + 真适配层 + 真服务端入口）。steps 层把规则词汇翻译成编排动作（直接造好建筑、指定位置与航线生成敌人、设定波次、推进秒数）与读取（模式、资金、实体、通电、快照节点 text/color/visible、ring/line 形状）。不为单个系统另开模块级测试接缝。

## 迁移说明

- 旧 Lua 移植保留在分支 `legacy/lua-port`，仅作参考。
- 旧 `features/base-defence.feature` 与 `acceptance/generated/base-defence/` 在新 feature 集落地时删除（与新集在价格、开局方式上矛盾）。
- `features/source-layout.feature`、`features/deploy-mirror.feature` 是工程 feature，保留不动。

## 已知的移植差异（照 Unity 写，实现时由适配层吸收）

- Unity 的"建筑离场"发生在 2 秒碎裂动画结束后；胜负判定依赖离场而非死亡。规则层保留"离场"概念，表现层决定碎裂时长。
- 通电/断电有 0.15 秒去抖；规则层以"持续 0.15 秒后生效"描述。
- Unity 热键 E/R/T/Y 与 Escape 在目的地没有键盘，`16-board-input.md` 定义触摸等价物。
