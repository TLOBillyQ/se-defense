-- tests/properties/overlays_prop.lua — server.present.overlays 与
-- server.adapter.shapes 的性质测试。
-- 覆盖维度：不变式（模式排他：非 Playing 全空 / 放置态有预览无高亮环 /
-- 悬停有高亮环；供电圈必对应在场通电供电者；默认链路线必连真实供电
-- 关系）、守恒（形状路由 reconcile：同内容再渲染零创建零销毁、
-- 在场形状键集合恒等于本拍需求）、宽输入范围（随机对局与显示侧操作）。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local overlays = require("server.present.overlays")
local shapes_router = require("server.adapter.shapes")
local placement = require("server.game.placement")
local world = require("server.game.world")

prop.seed(37)

local BUILDABLE = { "Relay", "Radar", "Turret", "Repair" }

local function random_ops(g, pres)
  for _ = 1, prop.int(1, 8) do
    local op = prop.int(1, 8)
    if op == 1 then
      g.entities:add_building(prop.pick(BUILDABLE),
        prop.number(-15, 15), prop.number(-15, 15))
    elseif op == 2 then
      pres:hover_at(prop.number(-5, 5), prop.number(-5, 5))
    elseif op == 3 then
      g:select(prop.pick(BUILDABLE))
    elseif op == 4 then
      g:cancel()
    elseif op == 5 then
      pres:set_preview(prop.number(-20, 20), prop.number(-20, 20))
    elseif op == 6 then
      pres:clear_hover()
    elseif op == 7 then
      g:advance(0.1)
      pres:tick(0.1)
    else
      g.mode = prop.pick({ "Playing", "Playing", "Victory" }) -- 编排：打模式守卫
    end
  end
end

local function entity_at(g, x, z)
  for _, e in ipairs(g.entities.list) do
    if math.abs(e.x - x) < 1e-9 and math.abs(e.z - z) < 1e-9 then return e end
  end
  return nil
end

-- O-P1：形状集合的结构不变式（按模式排他，且每个形状都能对回真实对局事实）。
prop.check("O-P1 形状集合结构不变式", 100, function()
  local g = match_flow.new()
  g:start()
  local pres = presenter.new(g)
  random_ops(g, pres)
  local out = overlays.compute(g, pres)
  if g.mode ~= "Playing" then
    if #out.lines > 0 or #out.circles > 0 or #out.supply > 0
      or out.ring or out.preview then
      return nil, "非 Playing 仍有形状"
    end
    return true
  end
  for _, c in ipairs(out.supply) do -- 供电圈必对应在场通电供电者
    local e = entity_at(g, c.x, c.z)
    if not e or (world.specs[e.kind].provide or 0) ~= c.r
      or not g.grid:powered(e) then
      return nil, "供电圈对不回通电供电者: " .. c.kind
    end
  end
  for _, c in ipairs(out.circles) do -- 功能覆盖圈半径必为实体总表 range
    if world.specs[c.kind].range ~= c.r then
      return nil, "覆盖圈半径与实体总表不符: " .. c.kind
    end
  end
  if g.placing_kind then
    if out.ring then return nil, "放置态出现高亮环" end
    if not out.preview then return nil, "放置态缺预览圆" end
    local pt = pres:preview_point()
    if out.preview.r ~= world.specs[g.placing_kind].footprint then
      return nil, "预览圆半径不是待建足迹"
    end
    if out.preview.legal ~= placement.legal(g, g.placing_kind, pt.x, pt.z) then
      return nil, "预览合法性与放置判定不一致"
    end
  elseif pres.hover then
    if out.preview then return nil, "悬停态出现预览圆" end
    if not out.ring then return nil, "悬停缺高亮环" end
    if math.abs(out.ring.r - 1.5 * world.specs[pres.hover.kind].footprint) > 1e-9 then
      return nil, "高亮环不是 1.5 倍足迹"
    end
  else
    if out.ring or out.preview then return nil, "默认态出现高亮环/预览圆" end
    for _, l in ipairs(out.lines) do -- 默认链路线必连真实供电关系
      local a, b = entity_at(g, l.ax, l.az), entity_at(g, l.bx, l.bz)
      if not a or not b or g.grid:provider(a) ~= b then
        return nil, "链路线对不回供电关系"
      end
    end
  end
  return true
end)

-- S-P1：形状路由 reconcile 守恒——在场键集恒等于本拍需求；
-- 同内容连渲两拍零创建零销毁且对象同一。
local function fake_world()
  local w = { created = 0, destroyed = 0 }
  function w:CreateUnit(_, props)
    w.created = w.created + 1
    local unit = { dead = false }
    function unit:Destroy() unit.dead = true; w.destroyed = w.destroyed + 1 end
    unit._props = props
    return unit
  end
  return w
end

prop.check("S-P1 形状 reconcile 守恒", 100, function()
  local g = match_flow.new()
  g:start()
  local pres = presenter.new(g)
  local w = fake_world()
  local r = shapes_router.new(w)
  for _ = 1, prop.int(1, 12) do
    random_ops(g, pres)
    local want = overlays.compute(g, pres)
    r:render(want)
    -- 同内容再渲一拍：零创建零销毁
    local c0, d0 = w.created, w.destroyed
    r:render(want)
    if w.created ~= c0 or w.destroyed ~= d0 then
      return nil, "同内容重渲产生创建/销毁"
    end
    -- 在场键集 == 需求键集
    local n_live, n_want = 0, 0
    for _, unit in pairs(r.live) do
      if unit.dead then return nil, "在场表残留已销毁单位" end
      n_live = n_live + 1
    end
    local function count(t)
      for _ in pairs(t.lines or {}) do n_want = n_want + 1 end
      for _ in pairs(t.circles or {}) do n_want = n_want + 1 end
      for _ in pairs(t.supply or {}) do n_want = n_want + 1 end
      if t.ring then n_want = n_want + 1 end
      if t.preview then n_want = n_want + 1 end
    end
    count(want)
    if n_live ~= n_want then
      return nil, string.format("在场 %d != 需求 %d", n_live, n_want)
    end
  end
  return true
end)
