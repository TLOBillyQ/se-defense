# language: zh-CN
# mutation-stamp: sha256=1ad413d4c772af90da1c31f701fe3c4d76ae6aa5c39a5dcca29ff205bd6ed9a2
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "源码树布局",
#   "feature_path": "features/engineering/source-layout.feature",
#   "implementation_hash": "sha256:c145662dff683e714b1821f3532ca777f029203ad082e865f07a4c6239e88c3b",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 4,
#       "name": "源码树布局 1: src 一级目录只含蛋仔工作区根目录名",
#       "result": {
#         "Errors": 0,
#         "Killed": 4,
#         "Survived": 0,
#         "Total": 4
#       },
#       "scenario_hash": "70911301f7269463af9376457cd7bb46dc95706fbdc7e6d3529a9e568b317926",
#       "tested_at": "2026-09-06T13:41:41Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 0,
#       "name": "源码树布局 2: src 一级目录都属于工作区根目录名",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "b995f6a0c8ec4acf4bf2dcd100b1525c4c6d97ad1e81b7415eaeb48e85f23235",
#       "tested_at": "2026-09-06T13:41:41Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 6,
#       "name": "源码树布局 3: 模块按所属端落位",
#       "result": {
#         "Errors": 0,
#         "Killed": 6,
#         "Survived": 0,
#         "Total": 6
#       },
#       "scenario_hash": "66ecb466ad2f712b4a2afc00a57fcd6ee3113f168cb5a2b268a34164b0877d55",
#       "tested_at": "2026-09-06T13:41:42Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 8,
#       "name": "源码树布局 4: 模块名相对 src 根解析",
#       "result": {
#         "Errors": 0,
#         "Killed": 8,
#         "Survived": 0,
#         "Total": 8
#       },
#       "scenario_hash": "d9bfc64e68af7f10f904abbea6ee7c7fa5c3cfcf1849b0c39951fcdf5a4fdae7",
#       "tested_at": "2026-09-06T13:41:42Z"
#     },
#     {
#       "index": 4,
#       "mutation_count": 0,
#       "name": "源码树布局 5: 仓库内不再有 src 前缀的模块名",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "52e89073d55008353a0f1d8b0e2899e374f70c826689b6b2337f17cf955d2921",
#       "tested_at": "2026-09-06T13:41:42Z"
#     }
#   ],
#   "tested_at": "2026-09-06T13:41:42Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   源码树布局 1: src 一级目录只含蛋仔工作区根目录名
#   源码树布局 2: src 一级目录都属于工作区根目录名
#   源码树布局 3: 模块按所属端落位
#   源码树布局 4: 模块名相对 src 根解析
#   源码树布局 5: 仓库内不再有 src 前缀的模块名
#
# 工程 feature：背景直接检查仓库，不启动对局。规则真源 CONTEXT.md「部署树」「宿主接缝」。
# 规则：
#   - src/ 的一级目录与蛋仔 SE 工作区根目录一一对应，只允许 client、common、data、server。
#   - 服务端规则层在 server/game/（世界数据表 world、对局流程 match_flow），宿主适配层在
#     server/adapter/，服务端入口 server/main.lua；客户端入口 client/main.lua 与哑镜像渲染器
#     client/eui_render.lua。
#   - require 名以 src/ 为根（即工作区根），仓库内不再出现 src. 前缀的模块名；vendor.spoke 前缀不变。
#   - 验收管线（run_acceptance.sh / run_mutation.sh）扫描 features/ 下所有子目录的 feature
#     （gameplay、presentation、engineering）。
#   - 不复制 legacy/lua-port 的业务模块。
功能: 源码树布局

场景大纲: 源码树布局 1: src 一级目录只含蛋仔工作区根目录名
  那么 src的一级目录<目录>是否存在为<存在>

例子:
  | 目录    | 存在 |
  | client  | 是   |
  | server  | 是   |

场景: 源码树布局 2: src 一级目录都属于工作区根目录名
  那么 src的一级目录都属于client common data server

场景大纲: 源码树布局 3: 模块按所属端落位
  那么 源码树中存在文件<路径>

例子:
  | 路径                       |
  | server/main.lua            |
  | server/game/world.lua      |
  | server/game/match_flow.lua |
  | server/adapter/host.lua    |
  | client/main.lua            |
  | client/eui_render.lua      |

场景大纲: 源码树布局 4: 模块名相对 src 根解析
  那么 源码文件<文件>引用模块<模块>

例子:
  | 文件                       | 模块                   |
  | server/main.lua            | server.game.match_flow |
  | server/main.lua            | server.adapter.host    |
  | server/game/match_flow.lua | server.game.world      |
  | client/main.lua            | client.eui_render      |

场景: 源码树布局 5: 仓库内不再有 src 前缀的模块名
  那么 src下没有文件引用以src.开头的模块
