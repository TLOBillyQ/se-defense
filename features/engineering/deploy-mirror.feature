# language: zh-CN
# mutation-stamp: sha256=25be928849c3b04cfdf8a536bd7c06642baf04ae6926d7e57e1ce469b73c7a0a
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "dec0798057c6072fd5bc9200831a8be7a95e38764b4ffc6a47a3a2c4b300e951",
#   "feature_name": "部署镜像",
#   "feature_path": "features/engineering/deploy-mirror.feature",
#   "implementation_hash": "sha256:126dcb7381f182f3e998a71bb987e8faf0f470723228150d10402038767130ff",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 1,
#       "name": "部署镜像 1: 部署把仓库根各端镜像到工作区根",
#       "result": {
#         "Errors": 0,
#         "Killed": 1,
#         "Survived": 0,
#         "Total": 1
#       },
#       "scenario_hash": "69f6bd24b5ebf3d9cb68aeb4bc3e95b2d75c2245affadfe10583124795db2bf8",
#       "tested_at": "2026-09-08T10:18:41Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 2,
#       "name": "部署镜像 2: 部署不触碰工作区中不归本仓库的文件",
#       "result": {
#         "Errors": 0,
#         "Killed": 2,
#         "Survived": 0,
#         "Total": 2
#       },
#       "scenario_hash": "ac0d9e72a9e22ddbb6d052e15eaef760253dd059acd6ed04ba7007baebc42136",
#       "tested_at": "2026-09-08T10:18:42Z"
#     }
#   ],
#   "tested_at": "2026-09-08T10:18:42Z",
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
#   - 场景 2 的预置与保留分成两列（值相同）：同一列既预置又断言的话，改一个路径会把两边
#     一起改掉，断言恒真、变异体必然存活。分列后动任一侧都会让断言落空。
#   - 传输按目的地选：工作区在 Windows 侧（wslpath 给出盘符路径）才走 robocopy 增量并做
#     editor-cli 收尾；本 feature 的临时工作区在 Linux 侧，一律本地 cp、不做收尾。
# 执行成本：验收运行时对每个例子行都重跑一遍背景与全部步骤，而一次部署是整树镜像。
#   所以待验路径走一个空格分隔的列表参数、每个场景只留一行例子：一个场景一次部署，
#   而不是一行一次。
功能: 部署镜像

背景:
  假如 一个空的临时工作区

场景大纲: 部署镜像 1: 部署把仓库根各端镜像到工作区根
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径列表>

例子:
  | 路径列表                                                                                                                  |
  | server/main.lua server/power/core.lua server/host/init.lua client/main.lua client/eui_render.lua common/spoke/init.lua |

场景大纲: 部署镜像 2: 部署不触碰工作区中不归本仓库的文件
  假如 临时工作区预置文件<预置列表>
  当 执行部署到临时工作区
  那么 临时工作区存在文件<保留列表>

例子:
  | 预置列表                                                                                                     | 保留列表                                                                                                     |
  | server/_trigger/GlobalVars.lua data/Prefab.lua eggy.json .gm/probe.lua unit_scripts/x.lua server.TableMgr/a | server/_trigger/GlobalVars.lua data/Prefab.lua eggy.json .gm/probe.lua unit_scripts/x.lua server.TableMgr/a |
