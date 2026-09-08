# language: zh-CN
# mutation-stamp: sha256=81a068fed2810a3403521c7a80d5284db5d2d1af0c53dd5183c65e8084a70cd6
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "dec0798057c6072fd5bc9200831a8be7a95e38764b4ffc6a47a3a2c4b300e951",
#   "feature_name": "部署镜像",
#   "feature_path": "features/engineering/deploy-mirror.feature",
#   "implementation_hash": "sha256:8df78393beb408100614886392b5fd73ad54c1742e1f06627ab69998fae6e74d",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 6,
#       "name": "部署镜像 1: 部署把仓库根各端镜像到工作区根",
#       "result": {
#         "Errors": 0,
#         "Killed": 6,
#         "Survived": 0,
#         "Total": 6
#       },
#       "scenario_hash": "07e6b41139c7eb219c11e2630ef080ee52c36b76bbf6b2872afe3c2d17d5c041",
#       "tested_at": "2026-09-07T11:09:32Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 6,
#       "name": "部署镜像 2: 部署不触碰工作区中不归本仓库的文件",
#       "result": {
#         "Errors": 0,
#         "Killed": 6,
#         "Survived": 0,
#         "Total": 6
#       },
#       "scenario_hash": "eca313dd649f59abec1450f1f162d5d9ab8bb17cecd8ca43cdc6b91ad3c9e511",
#       "tested_at": "2026-09-07T11:09:40Z"
#     }
#   ],
#   "tested_at": "2026-09-07T11:09:40Z",
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
#   - 路径列表为空格分隔；「存在文件」要求列表里每个路径都存在，「预置文件」逐个创建。
# 执行成本：验收运行时对每个例子行都重跑一遍背景与全部步骤，而一次部署是整树镜像
#   （WSL 下经 cmd.exe 走 robocopy 并做 editor-cli 收尾，跨系统调用尤其贵）。所以待验路径
#   走一个空格分隔的列表参数、每个场景只留一行例子：一个场景一次部署，而不是一行一次。
功能: 部署镜像

背景:
  假如 一个空的临时工作区

场景大纲: 部署镜像 1: 部署把仓库根各端镜像到工作区根
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径列表>

例子:
  | 路径列表                                                                                                                  |
  | server/main.lua server/game/core.lua server/adapter/host.lua client/main.lua client/eui_render.lua common/spoke/init.lua |

场景大纲: 部署镜像 2: 部署不触碰工作区中不归本仓库的文件
  假如 临时工作区预置文件<路径列表>
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径列表>

例子:
  | 路径列表                                                                                                     |
  | server/_trigger/GlobalVars.lua data/Prefab.lua eggy.json .gm/probe.lua unit_scripts/x.lua server.TableMgr/a |
