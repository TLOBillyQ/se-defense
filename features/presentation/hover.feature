# language: zh-CN
# 场景清单：
#   悬停 1: 悬停建筑显示该建筑的英文描述
#   悬停 2: 悬停 Core 显示 CORE 描述
#   悬停 3: 悬停矿点显示剩余量并随采集变化，采空后悬停消失
#   悬停 4: 清除悬停后无悬停
#   悬停 5: 放置态中不产生悬停
#
# 规则真源：docs/gdd/14-hover.md（V1–V4）。
# 约定：
#   - 「悬停位于 (x,z) 的 X」「清除悬停」是编排动作；命中判定归棋盘输入。
#   - 悬停描述三行：首行为建筑名大写，第二、三行为英文原文。
#   - 矿点剩余量为 0 即离场，因此采空后悬停随之消失。
功能: 悬停信息

背景:
  假如 一局新对局
  并且 玩家开始对局

场景大纲: 悬停 1: 悬停建筑显示该建筑的英文描述
  假如 一座已建好的<建筑>位于(0,3)
  当 悬停位于(0,3)的<建筑>
  并且 推进0.1秒
  那么 悬停是否存在为是
  并且 悬停描述首行的文本为<首行>
  并且 悬停描述第二行的文本为<第二行>
  并且 悬停描述第三行的文本为<第三行>

例子:
  | 建筑   | 首行   | 第二行                                                                   | 第三行                                                          |
  | Relay  | RELAY  | Extends the power grid, relaying power to any building inside its coverage. | Buildings lose power when their path to the Core is broken.     |
  | Radar  | RADAR  | Reveals enemies inside its coverage to turrets.                          | Turrets cannot fire at enemies that no radar has revealed.      |
  | Turret | TURRET | Fires at enemies inside its coverage that radar has revealed.            | Pair with radar coverage — a turret alone sees nothing.         |
  | Repair | REPAIR | Repairs the most damaged building inside its coverage, one at a time.    | Repair buildings can mend each other, but never themselves.     |

场景大纲: 悬停 2: 悬停 Core 显示 CORE 描述
  当 悬停位于(0,0)的Core
  并且 推进0.1秒
  那么 悬停描述首行的文本为<首行>
  并且 悬停描述第二行的文本为<第二行>
  并且 悬停描述第三行的文本为<第三行>

例子:
  | 首行 | 第二行                                                                          | 第三行                                    |
  | CORE | Seeds the power grid, all buildings must trace a path to it for receiving power. | Game is over if this building is destroyed. |

场景大纲: 悬停 3: 悬停矿点显示剩余量并随采集变化，采空后悬停消失
  当 悬停位于(1.71,0.06)的矿点
  并且 推进0.1秒
  那么 悬停描述首行的文本为RESOURCE
  并且 悬停描述第二行的文本为Generates $1.25/s while powered. Harvesting pauses during an attack.
  并且 悬停描述第三行的文本为300 remaining.
  当 推进<秒数>秒
  那么 悬停描述第三行的文本为<第三行>
  当 位于(1.71,0.06)的矿点剩余量设为0
  并且 推进0.1秒
  那么 悬停是否存在为否

例子:
  | 秒数 | 第三行         |
  | 0.8  | 299 remaining. |

场景: 悬停 4: 清除悬停后无悬停
  假如 一座已建好的Relay位于(0,3)
  并且 悬停位于(0,3)的Relay
  并且 推进0.1秒
  当 清除悬停
  并且 推进0.1秒
  那么 悬停是否存在为否

场景: 悬停 5: 放置态中不产生悬停
  假如 一座已建好的Relay位于(0,3)
  并且 玩家选择待建Radar
  当 悬停位于(0,3)的Relay
  并且 推进0.1秒
  那么 悬停是否存在为否
