# 01 对局流程

## 职责

对局阶段状态机、时间冻结、胜负判定、重开。

## 依赖

- 经济：剩余矿点数（胜利）。
- 建筑血量/离场：Core 离场（失败）。

## 规则

- R1 阶段：Pregame → Playing → Victory | GameOver → (重开) Pregame。没有别的转移。
- R2 开始对局：只有玩家主动"开始对局"才从 Pregame 进 Playing。进入 Playing 的瞬间资金置为 100。
- R3 时间冻结：阶段不是 Playing 时，波次倒计时、采集、敌人移动/攻击、Turret/Repair 行为全部不推进。
- R4 胜利：Playing 中，剩余矿点数为 0（全部采空且离场）→ Victory。
- R5 失败：Playing 中，Core 离场（死亡且碎裂完成）→ GameOver。
- R6 胜负只在 Playing 判定：Pregame 里 Core 被毁或矿点为 0 不改变阶段。
- R7 重开：Victory/GameOver 中玩家"重开" → 回到 Pregame，全图重建为初始布局（Core + 27 矿点，没有其他建筑、没有敌人、波次回到第 1 波 30 秒）。
- R8 Pregame 不接受放置：放置意图被忽略。

## 数值

| 项 | 值 |
|---|---|
| 起始资金 | 100 |
| 初始矿点数 | 27 |

## 必须覆盖的场景

1. 新对局处于 Pregame，玩家开始对局后处于 Playing 且资金为 100。
2. Pregame 中推进 60 秒，波次倒计时不变、资金不变。
3. Playing 中所有矿点采空并离场 → Victory。
4. Playing 中 Core 离场 → GameOver。
5. Victory/GameOver 中推进时间，敌人不移动、采集不进行。
6. 重开后回到 Pregame，棋盘只有 Core 与 27 个矿点，资金按 R2 在下次开始时重置。
7. Pregame 中放置意图无效。

## 不做

- 暂停、存档、难度选择。
