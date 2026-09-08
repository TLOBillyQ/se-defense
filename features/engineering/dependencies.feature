# language: zh-CN
# mutation-stamp: sha256=8654924031afe085d5e7457870f1c58a87b38809c894475867017261507d4086
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "依赖关系约束",
#   "feature_path": "features/engineering/dependencies.feature",
#   "implementation_hash": "sha256:6db135103eee3799d1eab54376b015d0bd122e8803ae4fee7201b9b497c09e8b",
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
#       "mutation_count": 28,
#       "name": "依赖关系约束 2: 系统依赖图的边在模块依赖里成立",
#       "result": {
#         "Errors": 0,
#         "Killed": 28,
#         "Survived": 0,
#         "Total": 28
#       },
#       "scenario_hash": "4ca576d426dda8c20a077ffd751260c7f4021db31cbe0460b89488e1a27f3d87",
#       "tested_at": "2026-09-08T12:37:33Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 68,
#       "name": "依赖关系约束 3: 反向依赖被架构门禁拒绝",
#       "result": {
#         "Errors": 0,
#         "Killed": 68,
#         "Survived": 0,
#         "Total": 68
#       },
#       "scenario_hash": "edbf710c839c6d12b4debeb2c29fa377c55950dc1590d36a1c859b1e3b5db5f2",
#       "tested_at": "2026-09-08T13:26:10Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 24,
#       "name": "依赖关系约束 4: 组件分层固定",
#       "result": {
#         "Errors": 0,
#         "Killed": 24,
#         "Survived": 0,
#         "Total": 24
#       },
#       "scenario_hash": "6cd3e40c395b83bf83532263c2a2cab5363f20b3c922eb638c1f88b4dbc889ec",
#       "tested_at": "2026-09-08T13:26:19Z"
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
#   "tested_at": "2026-09-08T13:26:19Z",
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
#     电网=server.power.power_node，经济=server.economy.resource，侦测=server.defense.radar，
#     火力=server.defense.turret，维修=server.defense.repair，放置=server.board.board_interactions，
#     敌人与波次=server.waves.wave_director，血量=server.units.health，
#     对局流程=server.match.game_state。
#   - 「模块 A 依赖模块 B」指 A 的源码 require B（arch_view 图上存在 A→B 的边）。
#   - 「架构门禁禁止 A 依赖 B」是更强的断言：图上没有 A→B 这条边，且门禁配置会拒绝它——
#     日后有人写出这条 require，`tools/arch check` 必须失败。这就是「固定」：约束落在门禁里，
#     不只落在这张表里。命中方式是禁止依赖规则或分层上行判定之一，本 feature 不区分。
#   - 系统依赖图里有几条影响方向在源码层**没有**直接模块边（对局流程▶全部玩法系统的冻结/解冻、
#     进攻期停采、Radar 揭示▶Turret 开火、资金▶放置、矿点采空▶胜利、电网通电▶放置合法落点）：
#     这些系统互不 require，接线在组合根 server.match.game_root_full（放置的通电信息由
#     game_state.power_zone 注入）。「全部玩法系统」逐个列出：经济、电网、放置、侦测、火力、
#     维修、敌人与波次；血量不在其中——game_state 依赖 health 是「建筑血量▶对局流程」那条边。
#     另有火力▶敌人血量、敌人血量▶波次全灭同样无直接边：turret 与 wave_director 都通过
#     组合根注入的 handle 读 health，不 require 血量模块。
#   - 无直接边的影响方向，场景 3 固定的是「影响者 require 被影响者」这条接反方向；正向若日后
#     真出现直接边，应改为场景 2 的例子行。
#     它们只由场景 3 的反向禁止固定——谁都不许反过来 require 对方，方向不会被悄悄接反。
#   - 组件分层为门禁配置里的既定决策：数字越大越底层，依赖只能从小数字流向大数字；
#     spoke 运行时是基座（substrate），任何层都可以依赖它。
#   - server/ 按玩法系统分包，一包一组件：match 组合根做全部跨系统接线，ui 只读状态出表现，
#     board 收拢棋盘输入与建造规格，systems 是 power/economy/defense/waves 四个玩法包共用的
#     一个组件（同层，互相可依赖），units 是血量/建筑等被系统操作的实体，kernel 是底座
#     （机制与共享事实，不含系统规则），host 是面向宿主的适配层。game/ 这层目录已取消：
#     它原来只用来隔开业务与宿主/入口，该职责由分层承担。
#   - board▶ui 这条边被翻过来：原来 board_interactions 自己 require board_display 并
#     挂载，是全图唯一一条玩法→表现的边，不翻则 board 与 ui 分不了层。现在
#     board_interactions 只暴露信号，组合根拿了信号再挂 BoardDisplay。两半都要钉住：
#     场景 2 的 game_root_full▶board_display 保证挂载没被顺手删掉，场景 3 的
#     board_interactions▶board_display 保证旧方向接不回来。
#   - common/ 下的非 spoke 模块（双端共用的事实：color_norm、unit_name）与 spoke 一样是基座，
#     不排层。理由是层级本身：client 是第 1 层、host 是第 9 层，两端都要够得着同一份实现，
#     给它排任何一个数字都会让另一端变成上行边。基座没有层级，谁都可以依赖它。
#   - 基座的代价是它出不去：common/ 下的模块不得反过来依赖任何 server./client. 模块，
#     否则「双端共用」就名存实亡。分层判定管的是层与层之间，基座的出边未必落在它手里；
#     真禁不住就得在 arch_view.config.json 里补一条禁止依赖规则——场景 3 认的是门禁的结论，
#     不认配置写在哪一栏。
#   - 颜色归一化不许从宿主接缝绕：server.ui.render_util 不得依赖 server.host.convert。
#     这条方向是 ui(4)▶host(9)，顺着层级往下、分层判定不拦，必须由禁止依赖规则拦住。
#     它拦的不是环，是归属：归一化不是宿主关注点，把它挂到 host 表上会污染唯一的接缝。
#     反向 server.host.convert▶server.ui.render_util 是上行边，分层判定自己会拒。
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
  | server.power.core               | server.power.power_node    |
  | server.power.relay              | server.power.power_node    |
  | server.defense.radar            | server.power.power_node    |
  | server.defense.turret           | server.power.power_node    |
  | server.defense.repair           | server.power.power_node    |
  | server.economy.resource         | server.power.power_node    |
  | server.units.building           | server.units.health        |
  | server.waves.enemy              | server.units.health        |
  | server.waves.wave_director      | server.waves.wave_cycle    |
  | server.board.board_interactions | server.board.board_sensors |
  | server.board.building_specs     | server.defense.turret      |
  | server.match.game_state         | server.units.health        |
  | server.match.game_root_full     | server.match.game_state    |
  | server.match.game_root_full     | server.ui.board_display    |

场景大纲: 依赖关系约束 3: 反向依赖被架构门禁拒绝
  那么 架构门禁禁止模块<模块>依赖模块<被依赖模块>

例子:
  | 模块                            | 被依赖模块                      |
  | server.power.power_node         | server.power.core               |
  | server.power.power_node         | server.power.relay              |
  | server.power.power_node         | server.defense.turret           |
  | server.power.power_node         | server.economy.resource         |
  | server.units.health             | server.units.building           |
  | server.units.health             | server.waves.enemy              |
  | server.units.building           | server.power.core               |
  | server.units.building           | server.defense.turret           |
  | server.waves.wave_cycle         | server.waves.wave_director      |
  | server.kernel.world_data        | server.waves.wave_director      |
  | server.board.board_sensors      | server.board.board_interactions |
  | server.match.game_state         | server.waves.wave_director      |
  | server.match.game_state         | server.economy.resource         |
  | server.economy.resource_harvest | server.waves.wave_director      |
  | server.economy.resource         | server.match.game_state         |
  | server.economy.resource         | server.board.board_interactions |
  | server.defense.radar            | server.defense.turret           |
  | server.power.power_node         | server.board.board_interactions |
  | server.match.game_state         | server.power.power_node         |
  | server.match.game_state         | server.board.board_interactions |
  | server.match.game_state         | server.defense.radar            |
  | server.match.game_state         | server.defense.turret           |
  | server.match.game_state         | server.defense.repair           |
  | server.defense.turret           | server.units.health             |
  | server.units.health             | server.waves.wave_director      |
  | server.waves.wave_director      | server.economy.resource         |
  | server.board.board_interactions | server.ui.board_display         |
  | server.host                     | server.power.core               |
  | server.power.core               | server.gm                       |
  | server.power.core               | client.eui_render               |
  | server.ui.render_util           | server.host.convert             |
  | server.host.convert             | server.ui.render_util           |
  | common.color_norm               | server.ui.render_util           |
  | common.unit_name                | client.eui_render               |

场景大纲: 依赖关系约束 4: 组件分层固定
  那么 组件<组件>的层级为<层级>

例子:
  | 组件           | 层级 |
  | client         | 1    |
  | server_entry   | 1    |
  | server_support | 2    |
  | match          | 3    |
  | ui             | 4    |
  | board          | 5    |
  | systems        | 6    |
  | units          | 7    |
  | kernel         | 8    |
  | host           | 9    |
  | spoke          | 基座 |
  | common         | 基座 |

场景: 依赖关系约束 5: 依赖环只剩豁免清单里的上游 spoke 内部环
  那么 未豁免的依赖环数量为0
