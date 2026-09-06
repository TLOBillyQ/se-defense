-- src/server/present/board_input.lua — 棋盘输入语义（规则真源
-- docs/gdd/16-board-input.md I1–I8）。目的地的触摸/点击已在上游换算为棋盘
-- 坐标（EUI 捕获层 + 射线求交，客户端侧），本模块决定这些落点与按钮点击
-- 的含义：按钮按阶段路由（开始/重开/选择待建/取消），棋盘点击仅 Playing
-- 有效（I8）、棋盘外无效（I2）、放置态在合法落点确认（I4）、非放置态驱动
-- 悬停（I3）。纯 Lua、无宿主依赖；玩家意图经适配层 RemoteEvent 上行至此。
local world = require("server.game.world")

local M = {}

local function on_board(x, z)
  return x >= world.board.min and x <= world.board.max
    and z >= world.board.min and z <= world.board.max
end

-- I5/I7：按钮点击。开始/重开按阶段生效（规则层各自把关）；
-- 建筑按钮：放置态中点当前类型 = 取消（I4），否则进入放置态（资金不足或
-- 非 Playing 由 placement.select 把关）。
function M.click_button(match, pres, name)
  if name == "开始" then
    match:start()
  elseif name == "重开" then
    match:restart()
  elseif match.placing_kind == name then
    match:cancel()
  else
    match:select(name)
  end
end

-- I2/I3/I4/I8：棋盘点击。
function M.click_board(match, pres, x, z)
  if match.mode ~= "Playing" then return end
  if not on_board(x, z) then return end
  if match.placing_kind then
    match:confirm(x, z) -- 非法落点不确认、保持放置态（04 R6）
  else
    pres:hover_at(x, z) -- 命中即悬停，空地即清除（V1/I3）
  end
end

-- I4：放置态拖动更新预览落点。
function M.drag_board(match, pres, x, z)
  if match.mode ~= "Playing" or not match.placing_kind then return end
  if not on_board(x, z) then return end
  pres:set_preview(x, z)
end

return M
