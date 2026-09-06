-- src/server/present/overlays.lua — 覆盖圈与链路形状（规则真源
-- docs/gdd/13-overlays.md O1–O6）。从对局现况与显示侧状态（悬停/放置/
-- 预览落点）算出本拍应显示的形状集合：链路线、功能覆盖圈、供电圈、
-- 高亮环、预览圆。纯函数、无状态、无宿主依赖；形状不进快照（双路由），
-- 由 server.adapter.shapes 就地渲为 EffectUnit。
local world = require("server.game.world")
local placement = require("server.game.placement")

local M = {}

local function shape_set()
  return { lines = {}, circles = {}, supply = {}, ring = nil, preview = nil }
end

local function alive(e) return e.state == "alive" end

local function line(out, a, b)
  out.lines[#out.lines + 1] = { ax = a.x, az = a.z, bx = b.x, bz = b.z }
end

-- O4：Core/Relay 的供电圈只按通电状态显示（Core 恒通电）。
-- O5：形状携带 kind，目的地按类型着色（并集轮廓为纯表现，客户端渲染）。
local function supply_circles(match, out)
  for _, e in ipairs(match.entities.list) do
    local provide = world.specs[e.kind].provide or 0
    if provide > 0 and alive(e) and match.grid:powered(e) then
      out.supply[#out.supply + 1] = { x = e.x, z = e.z, r = provide, kind = e.kind }
    end
  end
end

-- O2/O4：同类功能覆盖圈（Radar 8 / Turret 5 / Repair 5），未通电不注册。
local function coverage_circles(match, kind, out)
  local range = world.specs[kind].range
  if not range then return end
  for _, e in ipairs(match.entities.list) do
    if e.kind == kind and alive(e) and match.grid:powered(e) then
      out.circles[#out.circles + 1] = { x = e.x, z = e.z, r = range, kind = kind }
    end
  end
end

-- 建筑沿供电者链上溯到 Core 的链路线。
local function chain_lines(match, e, out)
  local cur = e
  while cur do
    local provider = match.grid:provider(cur)
    if not provider then return end
    line(out, cur, provider)
    cur = provider
  end
end

-- O3：放置态 = 通电供电圈 + 待建类型（非 Relay）的全图覆盖圈 + 预览圆。
local function placing_shapes(match, pres, out)
  supply_circles(match, out)
  local kind = match.placing_kind
  if kind ~= "Relay" then coverage_circles(match, kind, out) end
  local pt = pres:preview_point()
  out.preview = { x = pt.x, z = pt.z, r = world.specs[kind].footprint,
    legal = placement.legal(match, kind, pt.x, pt.z) }
end

-- O2：悬停 = 同类全图覆盖圈 + 到 Core 的供电链 + 1.5 倍足迹高亮环。
local function hover_shapes(match, hover, out)
  local spec = world.specs[hover.kind]
  if spec.range then
    coverage_circles(match, hover.kind, out)
  elseif (spec.provide or 0) > 0 then -- Power 类：同类供电圈
    for _, e in ipairs(match.entities.list) do
      if e.kind == hover.kind and alive(e) and match.grid:powered(e) then
        out.supply[#out.supply + 1] = { x = e.x, z = e.z, r = spec.provide, kind = e.kind }
      end
    end
  end
  if hover.kind ~= "Site" then chain_lines(match, hover, out) end
  out.ring = { x = hover.x, z = hover.z, r = 1.5 * spec.footprint }
end

-- O1：默认 = 整棵供电树的链路线（建筑节点，矿点不算）。
local function tree_lines(match, out)
  for _, e in ipairs(match.entities.list) do
    if e.kind ~= "Site" and e.kind ~= "Core" then
      local provider = match.grid:provider(e)
      if provider then line(out, e, provider) end
    end
  end
end

-- O6：只在 Playing 显示。
function M.compute(match, pres)
  local out = shape_set()
  if match.mode ~= "Playing" then return out end
  if match.placing_kind then
    placing_shapes(match, pres, out)
  elseif pres.hover then
    hover_shapes(match, pres.hover, out)
  else
    tree_lines(match, out)
  end
  return out
end

return M
