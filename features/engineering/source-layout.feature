# language: zh-CN
# 场景清单：
#   源码树布局 1: 仓库根直接持有蛋仔工作区根目录
#   源码树布局 2: 部署白名单即官方工作区根
#   源码树布局 3: 模块按所属端落位
#   源码树布局 4: 模块名相对仓库根解析
#   源码树布局 5: 仓库内不再有 src 前缀的模块名
#   源码树布局 6: 双端共用的事实只有一份实现
#
# 规则（官方工作区根：client/ common/ data/ server/，本项目跟随）：
#   - 仓库根直接持有 client/ common/ server/ 三个部署目录，没有 src/ 中间层；
#     game/ 与 adapter/ 不是仓库根的一级目录。data/ 是编辑器导出物，只回同步不部署。
#   - 部署（tools/deploy.lua）采用白名单 client common server；仓库根其余内容
#     （docs/ tools/ tests/ features/ data/ 等）不部署。
#   - 只被服务端引用的模块放 server/，只被客户端引用的放 client/，双端共用的才放 common/。
#     common/ 下不止 spoke 运行时：双端共用的事实（颜色归一化 common/color_norm、单位名约定
#     common/unit_name）也住这里。它们的判据是「两端都要」，不是「像工具函数」——
#     只有一端用的辅助模块仍留在该端的包里。
#   - 一份共用事实只允许有一处实现。曾经的两份重复（server/host/convert.lua 的 copy_color
#     与 server/ui/render_util.lua 的 copy_colour；server/host/entity.lua 的 unit_name 与
#     client/eui_render.lua 的 _unit_name）由测试与注释兜着不漂移，现在改由结构保证：
#     旧位置不再定义那些函数，双端各自 require common/ 下的唯一一份。
#     场景 6 钉「旧的没了」，场景 4 钉「新的接上了」——只钉一半的话，把函数体原地换个名字，
#     或加一条谁也不调用的 require，都能蒙混过关。
#   - 「源码文件 F 不定义函数 N」看的是定义处，不是出现次数：源码里没有 `function ...N(`
#     形式的定义（含 `t.N(`、`t:N(`、`local function N(`）。注释里提到 N、或调用别处的 N，
#     都不算定义——收敛之后调用点还在，只是指向 common/ 的那一份。
#   - 文件名避开保留服务名（CONTEXT.md「保留服务名」）：撞名的 Lua 文件会被编辑器静默跳过、
#     不进地图包，且目录层级不隔离。color_norm / unit_name 都是双词名，不与已知服务名相撞。
#   - 出口选 common/ 而不是 server/kernel/：host/ 是最底层（第 9 层），依赖 kernel/（第 8 层）
#     是上行边，门禁会拒；而从宿主接缝绕会把一个非宿主关注点塞进 host 表。
#     业务模块按玩法系统分包落在 server/ 下（match/ ui/ board/ power/ economy/ defense/
#     waves/ units/ kernel/），服务端宿主适配层在 server/host/，客户端渲染器直接在 client/。
#     GM 面 server/gm.lua 与网络层 server/net.lua 与 main.lua 同级：它们编排业务与适配层，适配层自身不得 require 任何业务包。
#   - require 名以仓库根为根（即工作区根），例如 server.power.core、server.host、
#     client.eui_render；仓库内不再出现 src. 前缀的模块名。spoke 运行时内联在 common/spoke/，
#     require 前缀 common.spoke（SE 文档只认 client/common/data/server 四个根目录，vendor/ 不在其中）。
#   - package.path 只需 ./?.lua 与 ./?/init.lua；无头测试按 server./client./common. 前缀复位模块。
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
  | 路径                            |
  | server/main.lua                 |
  | server/match/game_root_full.lua |
  | server/power/core.lua           |
  | server/host/init.lua            |
  | server/ui/build_panel.lua       |
  | server/gm.lua                   |
  | server/net.lua                  |
  | client/main.lua                 |
  | client/eui_render.lua           |
  | client/channel.lua              |
  | client/camera.lua               |
  | client/board_input.lua          |
  | client/gm.lua                   |
  | common/spoke/init.lua           |
  | common/color_norm.lua           |
  | common/unit_name.lua            |

场景大纲: 源码树布局 4: 模块名相对仓库根解析
  那么 源码文件<文件>引用模块<模块>

例子:
  | 文件                      | 模块                        |
  | server/main.lua           | server.match.game_root_full |
  | server/main.lua           | server.host                 |
  | server/main.lua           | server.net                  |
  | server/power/core.lua     | server.host                 |
  | server/power/core.lua     | common.spoke                |
  | client/main.lua           | client.eui_render           |
  | client/main.lua           | client.channel              |
  | client/main.lua           | client.camera               |
  | client/main.lua           | client.board_input          |
  | server/ui/render_util.lua | common.color_norm           |
  | server/host/entity.lua    | common.unit_name            |
  | client/eui_render.lua     | common.unit_name            |

场景: 源码树布局 5: 仓库内不再有 src 前缀的模块名
  那么 部署树下没有文件引用以src.开头的模块

场景大纲: 源码树布局 6: 双端共用的事实只有一份实现
  那么 源码文件<文件>不定义函数<函数>

例子:
  | 文件                      | 函数        |
  | server/host/convert.lua   | copy_color  |
  | server/ui/render_util.lua | copy_colour |
  | server/host/entity.lua    | unit_name   |
  | client/eui_render.lua     | _unit_name  |
