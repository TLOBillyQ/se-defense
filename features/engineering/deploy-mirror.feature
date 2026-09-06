# language: zh-CN
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
