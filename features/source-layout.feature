# language: zh-CN
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
#   - 现有 features/base-defence.feature 与 tools/headless 冒烟在新布局下必须原样通过。
功能: 源码树布局

场景大纲: 源码树布局 1: src 一级目录只含蛋仔工作区根目录名
  那么 src的一级目录<目录>是否存在为<存在>

例子:
  | 目录    | 存在 |
  | client  | 是   |
  | server  | 是   |
  | game    | 否   |
  | adapter | 否   |

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
