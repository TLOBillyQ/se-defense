# language: zh-CN
# mutation-stamp: sha256=d7f5467bc66273f19246af996012a775a0ef6f8cc9a91ba1026e7be622803020
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "依赖关系约束",
#   "feature_path": "features/engineering/dependencies.feature",
#   "implementation_hash": "sha256:20b2e0055dc52065a71ca0d284277e763554e5ec31383cf96baf42566bca66c6",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 0,
#       "name": "依赖关系约束 1: 架构门禁在当前源码树上通过",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "96abdb87673581f28d38f18cb55f0f13ca236cb20feb535afa63293c9683ae1b",
#       "tested_at": "2026-09-07T14:53:45Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 24,
#       "name": "依赖关系约束 2: 系统依赖图的边在模块依赖里成立",
#       "result": {
#         "Errors": 0,
#         "Killed": 24,
#         "Survived": 0,
#         "Total": 24
#       },
#       "scenario_hash": "a3a0f24d135074632e9b1c6c04982d27f973b8ad4304e0e7201f57a21300b2a6",
#       "tested_at": "2026-09-07T14:54:06Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 40,
#       "name": "依赖关系约束 3: 反向依赖被架构门禁拒绝",
#       "result": {
#         "Errors": 0,
#         "Killed": 40,
#         "Survived": 0,
#         "Total": 40
#       },
#       "scenario_hash": "a31f6095c283d6b2ce0bea19d4d5bbeca07c5f27fc2d7d5dac868fd362c68bd5",
#       "tested_at": "2026-09-07T14:54:39Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 12,
#       "name": "依赖关系约束 4: 组件分层固定",
#       "result": {
#         "Errors": 0,
#         "Killed": 12,
#         "Survived": 0,
#         "Total": 12
#       },
#       "scenario_hash": "8cbade16ac9369508a4ea6e0e5c6bcc618081dd5df8606e84ce36d64bec7d8b5",
#       "tested_at": "2026-09-07T14:54:50Z"
#     },
#     {
#       "index": 4,
#       "mutation_count": 0,
#       "name": "依赖关系约束 5: 依赖环只剩豁免清单里的上游 spoke 内部环",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "b30059e02e03267d435243ed798f735fba75980946932ac2df2e7aa839170e3e",
#       "tested_at": "2026-09-07T14:54:50Z"
#     }
#   ],
#   "tested_at": "2026-09-07T14:54:50Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   依赖关系约束 1: 架构门禁在当前源码树上通过
#   依赖关系约束 2: 系统依赖图的边在模块依赖里成立
#   依赖关系约束 3: 反向依赖被架构门禁拒绝
#   依赖关系约束 4: 组件分层固定
#   依赖关系约束 5: 依赖环只剩豁免清单里的上游 spoke 内部环
#
# 工程 feature：背景直接检查仓库源码，不启动对局。
# 规则真源：docs/gdd/README.md「系统依赖图」+ arch_view.config.json（门禁配置）。
#
# 规则：
#   - 「架构门禁」指 arch_view（`tools/arch check`）：它扫描 arch_view.config.json 的
#     source_roots，把每个模块归到一个组件与层级，然后拒绝三类事实——禁止依赖规则命中的边、
#     由低层级组件指向高层级组件的上行边、以及未豁免的投影依赖环。门禁不通过即非零退出。
#   - GDD 的系统依赖图是规则层的影响方向（谁被谁影响），本 feature 把它固定成源码层的
#     模块依赖方向：被影响的一方 require 影响它的一方，反向不成立。系统与模块的对应：
#     电网=server.game.power_node，经济=server.game.resource，侦测=server.game.radar，
#     火力=server.game.turret，维修=server.game.repair，放置=server.game.board_interactions，
#     敌人与波次=server.game.wave_director，血量=server.game.health，
#     对局流程=server.game.game_state。
#   - 「模块 A 依赖模块 B」指 A 的源码 require B（arch_view 图上存在 A→B 的边）。
#   - 「架构门禁禁止 A 依赖 B」是更强的断言：图上没有 A→B 这条边，且门禁配置会拒绝它——
#     日后有人写出这条 require，`tools/arch check` 必须失败。这就是「固定」：约束落在门禁里，
#     不只落在这张表里。命中方式是禁止依赖规则或分层上行判定之一，本 feature 不区分。
#   - 系统依赖图里有几条影响方向在源码层**没有**直接模块边（进攻期停采、Radar 揭示▶Turret 开火、
#     资金▶放置、矿点采空▶胜利）：这些系统互不 require，接线在组合根 server.game.game_root_full。
#     它们只由场景 3 的反向禁止固定——谁都不许反过来 require 对方，方向不会被悄悄接反。
#   - 组件分层为门禁配置里的既定决策：数字越大越底层，依赖只能从小数字流向大数字；
#     spoke 运行时是基座（substrate），任何层都可以依赖它。
#   - 上游 spoke 运行时内联进本仓（docs/spoke-upstream.md），其内部环不重写，走豁免清单；
#     本仓自己的代码不得引入新环。
#   - 本 feature 由 run_acceptance.sh 扫描 features/engineering/ 自动执行。
功能: 依赖关系约束

场景: 依赖关系约束 1: 架构门禁在当前源码树上通过
  那么 架构门禁检查通过

场景大纲: 依赖关系约束 2: 系统依赖图的边在模块依赖里成立
  那么 模块<模块>依赖模块<被依赖模块>

例子:
  | 模块                            | 被依赖模块                 |
  | server.game.core                | server.game.power_node     |
  | server.game.relay               | server.game.power_node     |
  | server.game.radar               | server.game.power_node     |
  | server.game.turret              | server.game.power_node     |
  | server.game.repair              | server.game.power_node     |
  | server.game.resource            | server.game.power_node     |
  | server.game.building            | server.game.health         |
  | server.game.enemy               | server.game.health         |
  | server.game.wave_director       | server.game.wave_cycle     |
  | server.game.board_interactions  | server.game.board_sensors  |
  | server.game.building_specs      | server.game.turret         |
  | server.game.game_root_full      | server.game.game_state     |

场景大纲: 依赖关系约束 3: 反向依赖被架构门禁拒绝
  那么 架构门禁禁止模块<模块>依赖模块<被依赖模块>

例子:
  | 模块                       | 被依赖模块                     |
  | server.game.power_node     | server.game.core               |
  | server.game.power_node     | server.game.relay              |
  | server.game.power_node     | server.game.turret             |
  | server.game.power_node     | server.game.resource           |
  | server.game.health         | server.game.building           |
  | server.game.health         | server.game.enemy              |
  | server.game.building       | server.game.core               |
  | server.game.building       | server.game.turret             |
  | server.game.wave_cycle     | server.game.wave_director      |
  | server.game.world          | server.game.wave_director      |
  | server.game.board_sensors  | server.game.board_interactions |
  | server.game.game_state     | server.game.wave_director      |
  | server.game.game_state     | server.game.resource           |
  | server.game.resource_harvest | server.game.wave_director    |
  | server.game.resource       | server.game.game_state         |
  | server.game.resource       | server.game.board_interactions |
  | server.game.radar          | server.game.turret             |
  | server.adapter.host        | server.game.core               |
  | server.game.core           | server.gm                      |
  | server.game.core           | client.eui_render              |

场景大纲: 依赖关系约束 4: 组件分层固定
  那么 组件<组件>的层级为<层级>

例子:
  | 组件           | 层级 |
  | client         | 1    |
  | server_entry   | 1    |
  | server_support | 2    |
  | game           | 3    |
  | adapter        | 4    |
  | spoke          | 基座 |

场景: 依赖关系约束 5: 依赖环只剩豁免清单里的上游 spoke 内部环
  那么 未豁免的依赖环数量为0
