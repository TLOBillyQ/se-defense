# language: zh-CN
# mutation-stamp: sha256=c504acdecd6af2d8fdc479b74c3df90797ae5440edf7ac9d5d547c6228b6c86a
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "spoke 原语约束",
#   "feature_path": "features/engineering/spoke-primitives.feature",
#   "implementation_hash": "sha256:2d009cd1808fcfdfa7a640622fecb1a1eb1c16448a2606d2a3bda0f91f813f95",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 19,
#       "name": "spoke 原语约束 1: 业务模块引用 common.spoke 下的模块",
#       "result": {
#         "Errors": 0,
#         "Killed": 19,
#         "Survived": 0,
#         "Total": 19
#       },
#       "scenario_hash": "e6de683ff35a656c07335173fbe9fe3d6a80e1eda65704f30bfe592b012a5929",
#       "tested_at": "2026-09-08T12:38:10Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 18,
#       "name": "spoke 原语约束 2: 业务模块实际调用 spoke 原语",
#       "result": {
#         "Errors": 0,
#         "Killed": 18,
#         "Survived": 0,
#         "Total": 18
#       },
#       "scenario_hash": "18fdf4b48d0ba6bc91399611f03ac80769b304b48eec9f0d0ae813b6fbb18f81",
#       "tested_at": "2026-09-08T12:38:11Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 0,
#       "name": "spoke 原语约束 3: 不引用 common.spoke 的业务模块只允许豁免清单内的纯辅助模块",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "eb334f9727251d5fcc9b90359db130165a920504384d6f5b6da780056d4626ae",
#       "tested_at": "2026-09-08T12:38:11Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 14,
#       "name": "spoke 原语约束 4: 豁免模块只组合 server. 与 common. 前缀的模块",
#       "result": {
#         "Errors": 0,
#         "Killed": 14,
#         "Survived": 0,
#         "Total": 14
#       },
#       "scenario_hash": "3b9c9392dc85f8444a3d05bbad20630b9073288265df0aca52a5ce3475ff36f6",
#       "tested_at": "2026-09-08T13:26:22Z"
#     }
#   ],
#   "tested_at": "2026-09-08T13:26:22Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   spoke 原语约束 1: 业务模块引用 common.spoke 下的模块
#   spoke 原语约束 2: 业务模块实际调用 spoke 原语
#   spoke 原语约束 3: 不引用 common.spoke 的业务模块只允许豁免清单内的纯辅助模块
#   spoke 原语约束 4: 豁免模块只组合 server. 与 common. 前缀的模块
#
# 工程 feature：背景直接检查仓库源码，不启动对局。规则真源 CONTEXT.md「spoke 原语约束」。
# 规则：
#   - 业务包（server/ 下除 host/ 外的包目录：match ui board power economy defense waves units
#     kernel）里的模块必须建立在 common/spoke 的响应式原语之上：以 require("common.spoke")
#     取门面表，或 require("common.spoke.reactive.<原语>") / require("common.spoke.runtime.<原语>") 直取模块，
#     两种形式都算「引用 common.spoke 下的模块」。
#   - 「使用 spoke 原语 X」指源码里出现门面访问 spoke.X（如 spoke.State）、门面子表访问
#     spoke.reactive.x / spoke.runtime.x，或直取 require common.spoke.reactive.x / common.spoke.runtime.x
#     （x 为 X 的小写蛇形名）三者之一；Dock 亦计作 EffectBuilder 作用域的组合调用
#     :dock(...)（如 ss:dock("enemies")）。
#   - 不引用 common.spoke 的模块视为不合规，除非它是纯函数/纯数据的辅助模块：自身不 require 模块，
#     或只 require server. / common. 前缀的模块（仍间接建立在 spoke 之上），且被点名在豁免
#     清单里；新增豁免必须改这里的例子表，作为显式决策。豁免模块不得引入任何别的前缀（如 client.）。
#   - common. 前缀是后开的口子：双端共用的事实住 common/（如 common.color_norm），
#     render_util 这类豁免模块要用它。口子不算放水——豁免模块一旦 require 了 common.spoke，
#     它就不再是「不引用 common.spoke 的模块」，场景 3 的清单当场对不上而失败。
#   - 作用域按包目录取，不按仓库根下的单个文件：server/ 根下的入口模块（main net gm）与宿主
#     适配层 host/ 都不在本约束内。豁免清单写成「包.模块」而不是裸模块名——这次重构的赌注就是
#     模块落在哪个包里，写全名才能让「搬错包」的变异体死掉。
#   - 本 feature 由 run_acceptance.sh 扫描 features/engineering/ 自动执行。
功能: spoke 原语约束

场景大纲: spoke 原语约束 1: 业务模块引用 common.spoke 下的模块
  那么 源码文件<文件>引用common.spoke下的模块

例子:
  | 文件                                |
  | server/main.lua                     |
  | server/match/game_root_full.lua     |
  | server/power/core.lua               |
  | server/match/game_state.lua         |
  | server/match/session.lua            |
  | server/units/building.lua           |
  | server/power/power_node.lua         |
  | server/power/relay.lua              |
  | server/defense/radar.lua            |
  | server/defense/turret.lua           |
  | server/defense/repair.lua           |
  | server/economy/resource.lua         |
  | server/economy/resource_harvest.lua |
  | server/waves/enemy.lua              |
  | server/units/health.lua             |
  | server/waves/wave_director.lua      |
  | server/ui/announcer.lua             |
  | server/board/input_signals.lua      |
  | server/board/board_interactions.lua |

场景大纲: spoke 原语约束 2: 业务模块实际调用 spoke 原语
  那么 源码文件<文件>使用spoke原语<原语>

例子:
  | 文件                            | 原语    |
  | server/power/core.lua           | State   |
  | server/power/core.lua           | Effect  |
  | server/match/game_state.lua     | Memo    |
  | server/match/game_state.lua     | Phase   |
  | server/power/power_node.lua     | Epoch   |
  | server/match/game_root_full.lua | Dock    |
  | server/waves/enemy.lua          | State   |
  | server/units/health.lua         | Trigger |
  | server/waves/wave_director.lua  | Effect  |

场景: spoke 原语约束 3: 不引用 common.spoke 的业务模块只允许豁免清单内的纯辅助模块
  那么 server下业务包中不引用common.spoke的模块都属于board.board_sensors board.building_specs defense.turret_behaviour kernel.game_tick kernel.world_data match.roster ui.board_display ui.build_panel ui.coverage_display ui.link_display ui.operation_log ui.render_util ui.sidebar_gameplay waves.wave_cycle

场景大纲: spoke 原语约束 4: 豁免模块只组合 server. 与 common. 前缀的模块
  那么 源码文件<文件>只引用前缀为server.或common.的模块

例子:
  | 文件                                |
  | server/ui/board_display.lua         |
  | server/board/board_sensors.lua      |
  | server/board/building_specs.lua     |
  | server/ui/coverage_display.lua      |
  | server/kernel/game_tick.lua         |
  | server/ui/link_display.lua          |
  | server/ui/render_util.lua           |
  | server/match/roster.lua             |
  | server/ui/sidebar_gameplay.lua      |
  | server/defense/turret_behaviour.lua |
  | server/waves/wave_cycle.lua         |
  | server/kernel/world_data.lua        |
  | server/ui/build_panel.lua           |
  | server/ui/operation_log.lua         |
