# language: zh-CN
# mutation-stamp: sha256=6ab94943e7365ed2578af8dbe55ce8cd671dc20655673d42c18d148b4f817907
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "dec0798057c6072fd5bc9200831a8be7a95e38764b4ffc6a47a3a2c4b300e951",
#   "feature_name": "部署镜像",
#   "feature_path": "features/engineering/deploy-mirror.feature",
#   "implementation_hash": "sha256:3ae7009950ff4596685d956c6ea747bb1a55254168101ace4c6441d6ce2fd2e9",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 7,
#       "name": "部署镜像 1: 部署把 src 各端镜像到工作区根",
#       "result": {
#         "Errors": 0,
#         "Killed": 7,
#         "Survived": 0,
#         "Total": 7
#       },
#       "scenario_hash": "77f64659dd143ec539ee9ce7705652b0a7ba04457efdc64012595a871421a8c7",
#       "tested_at": "2026-09-06T13:39:55Z"
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
#       "tested_at": "2026-09-06T13:39:55Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 3,
#       "name": "部署镜像 3: 部署不触碰工作区中不归本仓库的文件",
#       "result": {
#         "Errors": 0,
#         "Killed": 3,
#         "Survived": 0,
#         "Total": 3
#       },
#       "scenario_hash": "f870fd96c7984e05155e34e610b2e6d59c660c4e4ac79d20f72d546ebb6004f9",
#       "tested_at": "2026-09-06T13:39:58Z"
#     }
#   ],
#   "tested_at": "2026-09-06T13:39:58Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
# 场景清单：
#   部署镜像 1: 部署把 src 各端镜像到工作区根
#   部署镜像 2: 部署后工作区根不再有 src 目录
#   部署镜像 3: 部署不触碰工作区中不归本仓库的文件
#
# 工程 feature：背景创建临时工作区（./tmp 下），不启动对局。规则真源 CONTEXT.md「部署树」。
# 规则：
#   - 部署（tools/deploy.lua，工作区由 EGGY_WORKSPACE 指定）把 src/<端>/ 下每个文件落到
#     工作区 /<端>/ 同相对路径，vendor/spoke 仍落到工作区 vendor/spoke。
#   - 部署只重置本仓库拥有的子树；工作区里 server/_trigger、data、eggy.json 等不归本仓库的
#     内容原样保留。
#   - 旧部署树在工作区根留下的 src/ 目录随部署清除。
功能: 部署镜像

背景:
  假如 一个空的临时工作区

场景大纲: 部署镜像 1: 部署把 src 各端镜像到工作区根
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径>

例子:
  | 路径                       |
  | server/main.lua            |
  | server/game/world.lua      |
  | server/game/match_flow.lua |
  | server/adapter/host.lua    |
  | client/main.lua            |
  | client/eui_render.lua      |
  | vendor/spoke/init.lua      |

场景: 部署镜像 2: 部署后工作区根不再有 src 目录
  假如 临时工作区预置文件src/game/core.lua
  当 执行部署到临时工作区
  那么 临时工作区不存在目录src

场景大纲: 部署镜像 3: 部署不触碰工作区中不归本仓库的文件
  假如 临时工作区预置文件<路径>
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径>

例子:
  | 路径                           |
  | server/_trigger/GlobalVars.lua |
  | data/Prefab.lua                |
  | eggy.json                      |
