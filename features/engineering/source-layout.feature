# language: zh-CN
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
  | game    | 否   |
  | adapter | 否   |

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
