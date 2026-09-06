-- Unit tests for the overlay shapes (docs/gdd/13-overlays.md O1–O6):
-- default power-tree link lines, hover → same-kind coverage circles + chain
-- to Core + 1.5×footprint highlight ring, placing → powered supply circles +
-- placing-kind coverage circles + green/red preview, Playing-only display.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local overlays = require("server.present.overlays")

TestOverlays = {}

local function advance_seconds(g, p, n)
  for _ = 1, math.floor(n * 30 + 0.5) do
    g:advance(1 / 30)
    p:tick(1 / 30)
  end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g, presenter.new(g)
end

local function has_line(s, ax, az, bx, bz)
  for _, l in ipairs(s.lines) do
    if math.abs(l.ax - ax) < 1e-9 and math.abs(l.az - az) < 1e-9
      and math.abs(l.bx - bx) < 1e-9 and math.abs(l.bz - bz) < 1e-9 then
      return true
    end
  end
  return false
end

local function circle_at(s, x, z)
  for _, c in ipairs(s.circles) do
    if math.abs(c.x - x) < 1e-9 and math.abs(c.z - z) < 1e-9 then return c end
  end
  return nil
end

-- O1：默认显示整棵供电树的链路线（建筑节点，矿点不算）；无功能覆盖圈。
function TestOverlays.test_default_shows_power_tree_links()
  local g, p = new_playing()
  g.entities:add_building("Relay", 0, 3)
  advance_seconds(g, p, 1)
  local s = overlays.compute(g, p)
  lu.assertEquals(#s.lines, 1) -- 3 个通电矿点不产生链路线
  lu.assertTrue(has_line(s, 0, 3, 0, 0))
  lu.assertEquals(#s.circles, 0)
end

-- O2：悬停 Turret → 全图同类射程圈 + 到 Core 的链 + 1.5×足迹高亮环。
function TestOverlays.test_hover_turret_coverage_chain_ring()
  local g, p = new_playing()
  g.entities:add_building("Relay", 0, 3)
  g.entities:add_building("Turret", 0, 5.5)
  g.entities:add_building("Turret", 2, 0)
  g.entities:add_building("Relay", -3, 0)
  advance_seconds(g, p, 1)
  lu.assertEquals(#overlays.compute(g, p).lines, 4)
  p:hover_at(0, 5.5)
  local s = overlays.compute(g, p)
  lu.assertEquals(#s.circles, 2)
  lu.assertEquals(circle_at(s, 0, 5.5).r, 5)
  lu.assertEquals(circle_at(s, 2, 0).r, 5)
  lu.assertEquals(circle_at(s, 0, 5.5).kind, "Turret") -- O5：按类型着色所需
  lu.assertEquals(#s.lines, 2)
  lu.assertTrue(has_line(s, 0, 5.5, 0, 3))
  lu.assertTrue(has_line(s, 0, 3, 0, 0))
  lu.assertAlmostEquals(s.ring.x, 0, 1e-9)
  lu.assertAlmostEquals(s.ring.z, 5.5, 1e-9)
  lu.assertAlmostEquals(s.ring.r, 0.6, 1e-9)
  p:clear_hover()
  s = overlays.compute(g, p)
  lu.assertEquals(#s.circles, 0)
  lu.assertEquals(#s.lines, 4)
  lu.assertNil(s.ring)
end

-- O3/O4：放置态显示通电供电圈 + 待建类型的通电覆盖圈 + 预览圆，不显示链路。
function TestOverlays.test_placing_supply_and_coverage_circles()
  local g, p = new_playing()
  g.entities:add_building("Relay", 0, 3)
  g.entities:add_building("Turret", 2, 0)
  g.entities:add_building("Turret", 0, 10) -- 未通电
  g.entities:add_building("Relay", 0, 13)  -- 未通电
  advance_seconds(g, p, 1)
  lu.assertEquals(#overlays.compute(g, p).supply, 0)
  g:select("Turret")
  local s = overlays.compute(g, p)
  lu.assertEquals(#s.supply, 2)
  lu.assertEquals(s.supply[1].r, 4) -- Core
  lu.assertEquals(#s.circles, 1)
  lu.assertNotNil(circle_at(s, 2, 0))
  lu.assertNil(circle_at(s, 0, 10))
  lu.assertNotNil(s.preview)
  lu.assertEquals(#s.lines, 0)
  g:cancel()
  g:select("Relay")
  s = overlays.compute(g, p)
  lu.assertEquals(#s.circles, 0) -- Relay 无功能覆盖圈
  lu.assertEquals(#s.supply, 2)
end

-- O3：预览圆随落点移动，合法绿/非法红（04 R4：相切算相交）。
function TestOverlays.test_preview_circle_legality()
  local g, p = new_playing()
  g:select("Turret")
  p:set_preview(0, 2)
  local s = overlays.compute(g, p)
  lu.assertAlmostEquals(s.preview.x, 0, 1e-9)
  lu.assertAlmostEquals(s.preview.z, 2, 1e-9)
  lu.assertAlmostEquals(s.preview.r, 0.4, 1e-9)
  lu.assertTrue(s.preview.legal)
  p:set_preview(0.9, 0)
  lu.assertFalse(overlays.compute(g, p).preview.legal)
  p:set_preview(0, 4.01)
  lu.assertFalse(overlays.compute(g, p).preview.legal)
end

-- O6：只在 Playing 显示。
function TestOverlays.test_hidden_outside_playing()
  local g = match_flow.new()
  local p = presenter.new(g)
  g.entities:add_building("Relay", 0, 3)
  lu.assertEquals(#overlays.compute(g, p).lines, 0) -- Pregame
  g:start()
  g.entities:kill("Core")
  advance_seconds(g, p, 3)
  lu.assertEquals(g.mode, "GameOver")
  lu.assertEquals(#overlays.compute(g, p).lines, 0)
end
