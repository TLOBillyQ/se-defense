# language: zh-CN
# mutation-stamp: sha256=541524633c21c8b2c80335de411b59244f8334be08386bf7cc5b39edacfa289e
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
#   "feature_name": "源码树布局",
#   "feature_path": "features/source-layout.feature",
#   "implementation_hash": "sha256:194ee37a4733b6deac278c2933712d2841b455d69f216460c4d31f7edaebffaa",
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
#       "tested_at": "2026-09-05T14:23:56Z"
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
#       "tested_at": "2026-09-05T14:23:56Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 7,
#       "name": "源码树布局 3: 模块按所属端落位",
#       "result": {
#         "Errors": 0,
#         "Killed": 7,
#         "Survived": 0,
#         "Total": 7
#       },
#       "scenario_hash": "8645f0ec0e5c09a75fb101fcd373f0bc877e9662e165e83669121322fa44c385",
#       "tested_at": "2026-09-05T14:23:57Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 10,
#       "name": "源码树布局 4: 模块名相对 src 根解析",
#       "result": {
#         "Errors": 0,
#         "Killed": 10,
#         "Survived": 0,
#         "Total": 10
#       },
#       "scenario_hash": "8e35f6cf1a7a188a31605a865807ddf7416ae0c39afaa81fca769cc9662ff2ed",
#       "tested_at": "2026-09-05T14:23:57Z"
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
#       "tested_at": "2026-09-05T14:23:57Z"
#     }
#   ],
#   "tested_at": "2026-09-05T14:23:57Z",
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
# 规则（参考 LuaSource_战机斗蛐蛐 工作区根：client/ common/ data/ server/）：
#   - src/ 的一级目录与蛋仔 SE 工作区根目录一一对应，只允许 client、common、data、server；
#     game/ 与 adapter/ 不再是 src 的一级目录。
#   - 只被服务端引用的模块放 server/，只被客户端引用的放 client/，双端共用的才放 common/。
#     业务模块在 server/game/，服务端宿主适配层在 server/adapter/，客户端渲染器直接在 client/。
#   - require 名以 src/ 为根（即工作区根），例如 server.game.core、server.adapter.host、
#     client.eui_render；仓库内不再出现 src. 前缀的模块名。vendor.spoke 前缀不变。
#   - 仓库内引用旧路径的地方随之跟进：tools/headless/run_server.lua、tools/acceptance/headless.lua
#     （package.path 需含 ./src/?.lua；按 ^src%. 复位模块的逻辑改为复位 server./client./common. 前缀，
#     否则每个场景不再是全新对局）、tools/deploy.lua、CONTEXT.md「宿主接缝」「部署树」词条、
#     src/game/README.md（随目录迁移）、vendor/UPSTREAM.md。
#   - 现有 features/base-defence.feature 与 tools/headless 冒烟在新布局下必须原样通过。
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
  | 路径                           |
  | server/main.lua                |
  | server/game/game_root_full.lua |
  | server/game/core.lua           |
  | server/adapter/host.lua        |
  | server/adapter/build_panel.lua |
  | client/main.lua                |
  | client/eui_render.lua          |

场景大纲: 源码树布局 4: 模块名相对 src 根解析
  那么 源码文件<文件>引用模块<模块>

例子:
  | 文件                 | 模块                       |
  | server/main.lua      | server.game.game_root_full |
  | server/main.lua      | server.adapter.host        |
  | server/game/core.lua | server.adapter.host        |
  | server/game/core.lua | vendor.spoke               |
  | client/main.lua      | client.eui_render          |

场景: 源码树布局 5: 仓库内不再有 src 前缀的模块名
  那么 src下没有文件引用以src.开头的模块
