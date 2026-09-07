# language: zh-CN
# mutation-stamp: sha256=e570016e3391bcf03fd957cd5c322a95ffc47be0f04cae65d975ef09a7d6006a
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "dec0798057c6072fd5bc9200831a8be7a95e38764b4ffc6a47a3a2c4b300e951",
#   "feature_name": "部署镜像",
#   "feature_path": "features/deploy-mirror.feature",
#   "implementation_hash": "sha256:9487480e8ec263ad18097b43813c8244979683200e416f664eb90fc8e4d49214",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 6,
#       "name": "部署镜像 1: 部署把 src 各端镜像到工作区根",
#       "result": {
#         "Errors": 0,
#         "Killed": 6,
#         "Survived": 0,
#         "Total": 6
#       },
#       "scenario_hash": "7200c11169938668e779f4de02d687f9ad576c365e6a56d2370afe3c894affca",
#       "tested_at": "2026-09-05T14:19:32Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 0,
#       "name": "部署镜像 2: 部署后工作区根不再有 src 目录",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "24b6b5c362fc846d460f3bceaa745fa91fe5600ad7cd1eab217546bdefd0dd8c",
#       "tested_at": "2026-09-05T14:19:32Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 3,
#       "name": "部署镜像 2: 部署不触碰工作区中不归本仓库的文件",
#       "result": {
#         "Errors": 0,
#         "Killed": 3,
#         "Survived": 0,
#         "Total": 3
#       },
#       "scenario_hash": "f870fd96c7984e05155e34e610b2e6d59c660c4e4ac79d20f72d546ebb6004f9",
#       "tested_at": "2026-09-05T14:19:35Z"
#     }
#   ],
#   "tested_at": "2026-09-05T14:19:35Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   部署镜像 1: 部署把仓库根各端镜像到工作区根
#   部署镜像 2: 部署不触碰工作区中不归本仓库的文件
#
# 工程 feature：背景在 ./tmp 下创建临时工作区，不启动对局。规则真源 CONTEXT.md「部署树」。
# 规则：
#   - 部署（tools/deploy.lua，工作区由 EGGY_WORKSPACE 指定）把仓库根白名单 <端>/（client/
#     common/ server/）下每个文件落到工作区 /<端>/ 同相对路径；spoke 运行时就是 common/spoke/，
#     落到 common/spoke，无特例。仓库根其余内容不部署。
#   - 部署只重置本仓库拥有的白名单子树；工作区里 server/_trigger、data、eggy.json 等不归本仓库的
#     内容，以及编辑器自己生成的 .gm/ server.TableMgr unit_scripts/，一律原样保留。
功能: 部署镜像

背景:
  假如 一个空的临时工作区

场景大纲: 部署镜像 1: 部署把仓库根各端镜像到工作区根
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径>

例子:
  | 路径                    |
  | server/main.lua         |
  | server/game/core.lua    |
  | server/adapter/host.lua |
  | client/main.lua         |
  | client/eui_render.lua   |
  | common/spoke/init.lua   |

场景大纲: 部署镜像 2: 部署不触碰工作区中不归本仓库的文件
  假如 临时工作区预置文件<路径>
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径>

例子:
  | 路径                           |
  | server/_trigger/GlobalVars.lua |
  | data/Prefab.lua                |
  | eggy.json                      |
  | .gm/probe.lua                  |
  | unit_scripts/x.lua             |
  | server.TableMgr/a              |
