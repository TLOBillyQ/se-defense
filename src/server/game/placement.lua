-- src/server/game/placement.lua — 放置（规则真源 docs/gdd/04-placement.md）。
-- 选择待建（资金 ≥ 价格才可选，R1/R2；同一时刻最多一个待建类型，R3）、
-- 合法落点判定（足迹圆不相交——相切算相交；落点在某通电供电者的供电圈内；
-- 在棋盘内；R4/R8）、确认建造扣费并退出放置态（R5）、非法确认不退出（R6）、
-- 取消不扣费（R7）。不存在选中、拆除、退款（R10）。
--
-- 放置态存在 match.placing_kind 上；Pregame 忽略放置由 match_flow 把关
-- （01 R8），本模块假定对局已在 Playing。
local world = require("server.game.world")

local M = {}

-- 可选 = 可建造且资金够（R1/R2）。
function M.selectable(match, kind)
  local spec = world.specs[kind]
  return spec ~= nil and spec.price ~= nil and match.money >= spec.price
end

-- 选择待建类型：不可选或已在放置另一类型时无效（R2/R3）。
function M.select(match, kind)
  if not M.selectable(match, kind) then return false end
  if match.placing_kind and match.placing_kind ~= kind then return false end
  match.placing_kind = kind
  return true
end

-- 取消：退出放置态，不扣费（R7）。
function M.cancel(match)
  match.placing_kind = nil
end

-- 合法落点（R4/R8）：在棋盘内，足迹圆不与任何已有足迹圆相交（相切算相交），
-- 且落点位于某个通电供电者的供电圈内（问电网）。
function M.legal(match, kind, x, z)
  local spec = world.specs[kind]
  if not spec or not spec.price then return false end
  if x < world.board.min or x > world.board.max
    or z < world.board.min or z > world.board.max then
    return false
  end
  for _, e in ipairs(match.entities.list) do
    local r = world.specs[e.kind].footprint
    if world.dist(x, z, e.x, e.z) <= spec.footprint + r then return false end
  end
  return match.grid:covers(x, z)
end

-- 确认：合法落点 → 建造、扣费、退出放置态（R5）；非法 → 仍在放置态（R6）。
function M.confirm(match, x, z)
  local kind = match.placing_kind
  if not kind then return false end
  if not M.legal(match, kind, x, z) then return false end
  match.money = match.money - world.specs[kind].price
  match.entities:add_building(kind, x, z)
  match.placing_kind = nil
  return true
end

return M
