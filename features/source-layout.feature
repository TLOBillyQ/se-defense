# language: zh-CN
# 场景清单：
#   源码树布局 1: 仓库根直接持有蛋仔工作区根目录
#   源码树布局 2: 部署白名单即官方工作区根
#   源码树布局 3: 模块按所属端落位
#   源码树布局 4: 模块名相对仓库根解析
#   源码树布局 5: 仓库内不再有 src 前缀的模块名
#
# 规则（官方工作区根：client/ common/ data/ server/，本项目跟随）：
#   - 仓库根直接持有 client/ common/ server/ 三个部署目录，没有 src/ 中间层；
#     game/ 与 adapter/ 不是仓库根的一级目录。data/ 是编辑器导出物，只回同步不部署。
#   - 部署（tools/deploy_plan.lua）采用白名单 client common server；仓库根其余内容
#     （docs/ tools/ tests/ features/ data/ 等）不部署。
#   - 只被服务端引用的模块放 server/，只被客户端引用的放 client/，双端共用的才放 common/。
#     业务模块在 server/game/，服务端宿主适配层在 server/adapter/，客户端渲染器直接在 client/。
#   - require 名以仓库根为根（即工作区根），例如 server.game.core、server.adapter.host、
#     client.eui_render；仓库内不再出现 src. 前缀的模块名。spoke 运行时内联在 common/spoke/，
#     require 前缀 common.spoke（SE 文档只认 client/common/data/server 四个根目录，vendor/ 不在其中）。
#   - package.path 只需 ./?.lua 与 ./?/init.lua；无头测试按 server./client./common. 前缀复位模块。
#   - 现有 features/base-defence.feature 与 tools/headless 冒烟在新布局下必须原样通过。
功能: 源码树布局

场景大纲: 源码树布局 1: 仓库根直接持有蛋仔工作区根目录
  那么 仓库根目录<目录>是否存在为<存在>

例子:
  | 目录    | 存在 |
  | client  | 是   |
  | common  | 是   |
  | server  | 是   |
  | src     | 否   |
  | game    | 否   |
  | adapter | 否   |

场景: 源码树布局 2: 部署白名单即官方工作区根
  那么 部署白名单为client common server

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
  | common/spoke/init.lua          |

场景大纲: 源码树布局 4: 模块名相对仓库根解析
  那么 源码文件<文件>引用模块<模块>

例子:
  | 文件                 | 模块                       |
  | server/main.lua      | server.game.game_root_full |
  | server/main.lua      | server.adapter.host        |
  | server/game/core.lua | server.adapter.host        |
  | server/game/core.lua | common.spoke               |
  | client/main.lua      | client.eui_render          |

场景: 源码树布局 5: 仓库内不再有 src 前缀的模块名
  那么 部署树下没有文件引用以src.开头的模块
