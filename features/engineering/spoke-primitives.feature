# language: zh-CN
# 场景清单：
#   spoke 原语约束 1: 业务模块引用 common.spoke 下的模块
#   spoke 原语约束 2: 业务模块实际调用 spoke 原语
#   spoke 原语约束 3: 不引用 common.spoke 的业务模块只允许豁免清单内的纯辅助模块
#   spoke 原语约束 4: 豁免模块只组合 server. 前缀的模块
#
# 工程 feature：背景直接检查仓库源码，不启动对局。规则真源 CONTEXT.md「spoke 原语约束」。
# 规则：
#   - server/game 下的业务模块必须建立在 common/spoke 的响应式原语之上：以 require("common.spoke")
#     取门面表，或 require("common.spoke.reactive.<原语>") / require("common.spoke.runtime.<原语>") 直取模块，
#     两种形式都算「引用 common.spoke 下的模块」。
#   - 「使用 spoke 原语 X」指源码里出现门面访问 spoke.X（如 spoke.State）、门面子表访问
#     spoke.reactive.x / spoke.runtime.x，或直取 require common.spoke.reactive.x / common.spoke.runtime.x
#     （x 为 X 的小写蛇形名）三者之一；Dock 亦计作 EffectBuilder 作用域的组合调用
#     :dock(...)（如 ss:dock("enemies")）。
#   - 不引用 common.spoke 的模块视为不合规，除非它是纯函数/纯数据的辅助模块：自身不 require 模块，
#     或只 require server. 前缀的模块（仍间接建立在 spoke 之上），且被点名在豁免清单里；
#     新增豁免必须改这里的例子表，作为显式决策。豁免模块不得引入任何非 server. 前缀的模块。
#   - 本 feature 由 run_acceptance.sh 扫描 features/engineering/ 自动执行。
功能: spoke 原语约束

场景大纲: spoke 原语约束 1: 业务模块引用 common.spoke 下的模块
  那么 源码文件<文件>引用common.spoke下的模块

例子:
  | 文件                            |
  | server/main.lua                 |
  | server/game/game_root_full.lua  |
  | server/game/core.lua            |
  | server/game/game_state.lua      |
  | server/game/session.lua         |
  | server/game/building.lua        |
  | server/game/power_node.lua      |
  | server/game/relay.lua           |
  | server/game/radar.lua           |
  | server/game/turret.lua          |
  | server/game/repair.lua          |
  | server/game/resource.lua        |
  | server/game/resource_harvest.lua|
  | server/game/enemy.lua           |
  | server/game/health.lua          |
  | server/game/wave_director.lua   |
  | server/game/announcer.lua       |
  | server/game/input_signals.lua   |
  | server/game/board_interactions.lua |

场景大纲: spoke 原语约束 2: 业务模块实际调用 spoke 原语
  那么 源码文件<文件>使用spoke原语<原语>

例子:
  | 文件                           | 原语    |
  | server/game/core.lua           | State   |
  | server/game/core.lua           | Effect  |
  | server/game/game_state.lua     | Memo    |
  | server/game/game_state.lua     | Phase   |
  | server/game/power_node.lua     | Epoch   |
  | server/game/game_root_full.lua | Dock    |
  | server/game/enemy.lua          | State   |
  | server/game/health.lua         | Trigger |
  | server/game/wave_director.lua  | Effect  |

场景: spoke 原语约束 3: 不引用 common.spoke 的业务模块只允许豁免清单内的纯辅助模块
  那么 server/game下不引用common.spoke的模块都属于board_display board_sensors building_specs coverage_display game_tick link_display render_util sidebar_gameplay turret_behaviour wave_cycle world

场景大纲: spoke 原语约束 4: 豁免模块只组合 server. 前缀的模块
  那么 源码文件<文件>只引用前缀为server.的模块

例子:
  | 文件                             |
  | server/game/board_display.lua    |
  | server/game/board_sensors.lua    |
  | server/game/building_specs.lua   |
  | server/game/coverage_display.lua |
  | server/game/game_tick.lua        |
  | server/game/link_display.lua     |
  | server/game/render_util.lua      |
  | server/game/sidebar_gameplay.lua |
  | server/game/turret_behaviour.lua |
