# language: zh-CN
# mutation-stamp: sha256=a06c09c1b6b004274d88d91ebdef5ba7eaab0a608a5810d0d79edc2e4ea26443
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "spoke 原语约束",
#   "feature_path": "features/engineering/spoke-primitives.feature",
#   "implementation_hash": "sha256:da7313c808f88a13d98c97ea48247899ce6bf42acbac206e75809adca8f79ba6",
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
#       "scenario_hash": "e8a013ccde9bef494c902ca54b684e6023994773c92c18b998a7adadb87ece49",
#       "tested_at": "2026-09-07T11:26:02Z"
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
#       "scenario_hash": "687b53aff010b656637c25f16a488b5afc94e83b57415b4906bf7cc8496596ed",
#       "tested_at": "2026-09-07T11:26:02Z"
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
#       "scenario_hash": "4736e99dcd0f703b33b4f2e6daa81566d589ea3b569dc38c6cfa0bd12def51a6",
#       "tested_at": "2026-09-08T10:14:52Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 12,
#       "name": "spoke 原语约束 4: 豁免模块只组合 server. 前缀的模块",
#       "result": {
#         "Errors": 0,
#         "Killed": 12,
#         "Survived": 0,
#         "Total": 12
#       },
#       "scenario_hash": "5cbc56a28517e6c9c7933f5fc1f74fcead7ebc8c0f1b1172541f0fd5e109b912",
#       "tested_at": "2026-09-08T10:14:53Z"
#     }
#   ],
#   "tested_at": "2026-09-08T10:14:53Z",
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
