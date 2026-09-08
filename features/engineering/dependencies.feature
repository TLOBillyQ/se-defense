# language: zh-CN
# mutation-stamp: sha256=1abd573a953825a3af9e680235897da24eda5e00ad97e699b0e84b6e15b61523
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "依赖关系约束",
#   "feature_path": "features/engineering/dependencies.feature",
#   "implementation_hash": "sha256:2bd4c04034d0469c2b03a80dc6b139f2cb5575dd42e6547509236cbf29d29384",
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
#       "tested_at": "2026-09-08T03:21:38Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 26,
#       "name": "依赖关系约束 2: 系统依赖图的边在模块依赖里成立",
#       "result": {
#         "Errors": 0,
#         "Killed": 26,
#         "Survived": 0,
#         "Total": 26
#       },
#       "scenario_hash": "a6aae4a1ce88fd239aef70f015f9e7b083a4f796dfd3765aaf26fc2fabc90443",
#       "tested_at": "2026-09-08T03:21:47Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 58,
#       "name": "依赖关系约束 3: 反向依赖被架构门禁拒绝",
#       "result": {
#         "Errors": 0,
#         "Killed": 58,
#         "Survived": 0,
#         "Total": 58
#       },
#       "scenario_hash": "d1292eb190f399c2899a5a342c8afe3a6c63c1ef30c75d3ed8dcb8f2f78708ea",
#       "tested_at": "2026-09-08T03:22:05Z"
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
#       "tested_at": "2026-09-08T03:22:09Z"
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
#       "tested_at": "2026-09-08T03:22:09Z"
#     }
#   ],
#   "tested_at": "2026-09-08T03:22:09Z",
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
#   - 系统依赖图里有几条影响方向在源码层**没有**直接模块边（对局流程▶全部玩法系统的冻结/解冻、
#     进攻期停采、Radar 揭示▶Turret 开火、资金▶放置、矿点采空▶胜利、电网通电▶放置合法落点）：
#     这些系统互不 require，接线在组合根 server.game.game_root_full（放置的通电信息由
#     game_state.power_zone 注入）。「全部玩法系统」逐个列出：经济、电网、放置、侦测、火力、
#     维修、敌人与波次；血量不在其中——game_state 依赖 health 是「建筑血量▶对局流程」那条边。
#     另有火力▶敌人血量、敌人血量▶波次全灭同样无直接边：turret 与 wave_director 都通过
#     组合根注入的 handle 读 health，不 require 血量模块。
#   - 无直接边的影响方向，场景 3 固定的是「影响者 require 被影响者」这条接反方向；正向若日后
#     真出现直接边，应改为场景 2 的例子行。
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
  | server.game.game_state          | server.game.health         |
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
  | server.game.power_node     | server.game.board_interactions |
  | server.game.game_state     | server.game.power_node         |
  | server.game.game_state     | server.game.board_interactions |
  | server.game.game_state     | server.game.radar              |
  | server.game.game_state     | server.game.turret             |
  | server.game.game_state     | server.game.repair             |
  | server.game.turret        | server.game.health             |
  | server.game.health        | server.game.wave_director      |
  | server.game.wave_director | server.game.resource           |
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
