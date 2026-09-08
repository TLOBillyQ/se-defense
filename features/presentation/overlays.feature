# language: zh-CN
# mutation-stamp: sha256=8c4d335278dadbbedb71af3e43b8695dd1eaab6371c15657e483205fa9edf4bc
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "59935a2447a84086d15a8473e4a78f481fadc4e76f8b445bee2bd4c4bc669565",
#   "feature_name": "覆盖圈与链路",
#   "feature_path": "features/presentation/overlays.feature",
#   "implementation_hash": "sha256:8bcff87e0f422d09969aacbb515dd52ffbfb117663327c836cea3c54bb6cf507",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 0,
#       "name": "覆盖圈 1: 一个 Relay 接入 Core 时默认显示一条链路线",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "101640a42a41ae4e4dac68c316bb8abc711cbf7f5b03225f08c3ba64cd0de18a",
#       "tested_at": "2026-09-08T10:19:18Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 0,
#       "name": "覆盖圈 2: 悬停 Turret 显示全图 Turret 射程圈、到 Core 的供电链与高亮环，不显示整棵树",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "1f0e0fc295dbb143b07c767e9c9826c1f2fbdbbd898f943de3a1ba70f72e3f3f",
#       "tested_at": "2026-09-08T10:19:18Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 4,
#       "name": "覆盖圈 3: 放置态显示通电供电圈与待建类型的全图覆盖圈，未通电者不显示",
#       "result": {
#         "Errors": 0,
#         "Killed": 4,
#         "Survived": 0,
#         "Total": 4
#       },
#       "scenario_hash": "c16b9ecd8262edba36b97b514ca303a5151ce4a779fd0655de3de346965d11a8",
#       "tested_at": "2026-09-08T10:19:19Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 12,
#       "name": "覆盖圈 4: 预览圆随落点移动，圆心与半径跟随足迹",
#       "result": {
#         "Errors": 0,
#         "Killed": 12,
#         "Survived": 0,
#         "Total": 12
#       },
#       "scenario_hash": "fd3bf4c34e688c304e63b1f0f14fcf1febfa7a697c9a4d0a511753dd3614c58d",
#       "tested_at": "2026-09-08T10:19:20Z"
#     },
#     {
#       "index": 4,
#       "mutation_count": 0,
#       "name": "覆盖圈 5: 对局结束后不再显示链路线",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "c176a88b05eb5e32353be2207057c5ff7799e8248229b58808e1bc274c99a59a",
#       "tested_at": "2026-09-08T10:19:20Z"
#     }
#   ],
#   "tested_at": "2026-09-08T10:19:20Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   覆盖圈 1: 一个 Relay 接入 Core 时默认显示一条链路线
#   覆盖圈 2: 悬停 Turret 显示全图 Turret 射程圈、到 Core 的供电链与高亮环，不显示整棵树
#   覆盖圈 3: 放置态显示通电供电圈与待建类型的全图覆盖圈，未通电者不显示
#   覆盖圈 4: 预览圆随落点移动，圆心与半径跟随足迹
#   覆盖圈 5: 对局结束后不再显示链路线
#
# 规则真源：docs/gdd/13-overlays.md（O1–O6）、docs/gdd/00-world.md 实体总表（半径）。
# 约定：
#   - 链路线：一段连接建筑与其供电者的线段，以两端坐标断言。
#   - 供电圈：Core / 通电 Relay 的供电范围圆（4 / 3）；覆盖圈：Radar 8、Turret 5、Repair 5 的功能范围圆。
#   - 高亮环半径为足迹半径的 1.5 倍；预览圆圆心为当前落点。
#   - 「位于 (x,z) 的覆盖圈」以圆心定位。覆盖圈为单色（白模不吃颜色，#42），落点合法性
#     改由消息行承载，见 hud.feature「HUD 10」。
#   - 「悬停位于 (x,z) 的 X」「玩家拖动到棋盘 (x,z)」是编排动作；显示状态在推进时间后读取。
功能: 覆盖圈与链路

背景:
  假如 一局新对局
  并且 玩家开始对局

场景: 覆盖圈 1: 一个 Relay 接入 Core 时默认显示一条链路线
  假如 一座已建好的Relay位于(0,3)
  当 推进1秒
  那么 链路线数量为1
  并且 存在一条连接(0,3)与(0,0)的链路线
  并且 覆盖圈数量为0

场景: 覆盖圈 2: 悬停 Turret 显示全图 Turret 射程圈、到 Core 的供电链与高亮环，不显示整棵树
  假如 一座已建好的Relay位于(0,3)
  并且 一座已建好的Turret位于(0,5.5)
  并且 一座已建好的Turret位于(2,0)
  并且 一座已建好的Relay位于(-3,0)
  并且 推进1秒
  并且 链路线数量为4
  当 悬停位于(0,5.5)的Turret
  并且 推进0.1秒
  那么 覆盖圈数量为2
  并且 位于(0,5.5)的覆盖圈半径为5
  并且 位于(2,0)的覆盖圈半径为5
  并且 链路线数量为2
  并且 存在一条连接(0,5.5)与(0,3)的链路线
  并且 存在一条连接(0,3)与(0,0)的链路线
  并且 高亮环圆心为(0,5.5)
  并且 高亮环半径为0.6
  当 清除悬停
  并且 推进0.1秒
  那么 覆盖圈数量为0
  并且 链路线数量为4
  并且 高亮环是否显示为否

场景大纲: 覆盖圈 3: 放置态显示通电供电圈与待建类型的全图覆盖圈，未通电者不显示
  假如 一座已建好的Relay位于(0,3)
  并且 一座已建好的Turret位于(2,0)
  并且 一座已建好的Turret位于(0,10)
  并且 一座已建好的Relay位于(0,13)
  并且 推进1秒
  并且 供电圈数量为0
  当 玩家选择待建<待建类型>
  并且 推进0.1秒
  那么 供电圈数量为2
  并且 位于(0,0)的供电圈半径为4
  并且 位于(0,3)的供电圈半径为3
  并且 位于(0,13)的供电圈是否显示为否
  并且 覆盖圈数量为<覆盖圈数量>
  并且 位于(0,10)的覆盖圈是否显示为否
  并且 预览圆是否显示为是
  并且 链路线数量为0

例子:
  | 待建类型 | 覆盖圈数量 |
  | Turret   | 1          |
  | Relay    | 0          |

场景大纲: 覆盖圈 4: 预览圆随落点移动，圆心与半径跟随足迹
  假如 玩家选择待建Turret
  当 玩家拖动到棋盘(<拖动x>,<拖动z>)
  并且 推进0.1秒
  那么 预览圆圆心为(<圆心x>,<圆心z>)
  并且 预览圆半径为0.4

例子:
  | 拖动x | 拖动z | 圆心x | 圆心z |
  | 0     | 2     | 0     | 2     |
  | 0.9   | 0     | 0.9   | 0     |
  | 0     | 4.01  | 0     | 4.01  |

场景: 覆盖圈 5: 对局结束后不再显示链路线
  假如 一座已建好的Relay位于(0,3)
  并且 推进1秒
  并且 链路线数量为1
  当 Core死亡
  并且 推进3秒
  那么 链路线数量为0
