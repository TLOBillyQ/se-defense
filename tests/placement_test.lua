-- Unit tests for the placement rules (docs/gdd/04-placement.md R1–R10):
-- affordability, single pending type, legal spot (footprint / powered provide
-- circle / board bounds), confirm/cancel, charging.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")

TestPlacement = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

-- R1/R2：资金 ≥ 价格才可选；Core 与矿点不可建造。
function TestPlacement.test_selectable_requires_price()
  local g = new_playing()
  lu.assertTrue(g:selectable("Relay"))
  lu.assertTrue(g:selectable("Radar"))
  lu.assertTrue(g:selectable("Turret"))
  lu.assertTrue(g:selectable("Repair"))
  g.money = 99
  lu.assertFalse(g:selectable("Repair"))
  g.money = 9
  lu.assertFalse(g:selectable("Relay"))
end

function TestPlacement.test_core_and_site_not_buildable()
  local g = new_playing()
  lu.assertFalse(g:selectable("Core"))
  lu.assertFalse(g:selectable("Site"))
end

-- R5：合法落点确认 → 建造、扣费、退出放置态。
function TestPlacement.test_confirm_legal_spot_builds_and_charges()
  local g = new_playing()
  g:select("Relay")
  lu.assertTrue(g:placing())
  g:confirm(0, 3)
  lu.assertFalse(g:placing())
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
  advance_seconds(g, 1)
  lu.assertTrue(g.grid:powered(g.entities:find("Relay", 0, 3)))
end

-- R4：足迹圆相切算相交不能放置。
function TestPlacement.test_tangent_footprint_rejected()
  local g = new_playing()
  g:place("Turret", 0, -0.9)
  lu.assertFalse(g.entities:present("Turret"))
  lu.assertEquals(g.money, 100)
end

function TestPlacement.test_just_past_tangent_allowed()
  local g = new_playing()
  g:place("Turret", 0, -0.91)
  lu.assertTrue(g.entities:present("Turret"))
  lu.assertEquals(g.money, 50)
end

-- R4：落点须在通电供电圈内（Core 圈边界 4）。
function TestPlacement.test_spot_outside_powered_circle_rejected()
  local g = new_playing()
  g:place("Relay", 0, 4.01)
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertEquals(g.money, 100)
end

function TestPlacement.test_spot_on_circle_edge_allowed()
  local g = new_playing()
  g:place("Relay", 0, 4)
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
end

-- R4：只在未通电 Relay 圈内的落点不能放置。
function TestPlacement.test_unpowered_relay_circle_does_not_legalize()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 6)
  advance_seconds(g, 1)
  g:place("Radar", 0, 7)
  lu.assertFalse(g.entities:present("Radar"))
  lu.assertEquals(g.money, 103) -- 推进 1 秒间 3 个通电矿点各采一次
end

-- R4：矿点足迹挡住放置；矿点离场后可以放。
function TestPlacement.test_site_footprint_blocks_until_gone()
  local g = new_playing()
  g:place("Relay", 1.71, 0.06)
  lu.assertFalse(g.entities:present("Relay"))
  g.entities:remove(g.entities:find("Site", 1.71, 0.06))
  g:place("Relay", 1.71, 0.06)
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
end

-- R6/R7：非法确认仍处于放置态且不扣费；取消退出放置态。
function TestPlacement.test_illegal_confirm_keeps_placing_state()
  local g = new_playing()
  g:select("Relay")
  g:confirm(0, 4.01)
  lu.assertTrue(g:placing())
  lu.assertEquals(g.money, 100)
  g:cancel()
  lu.assertFalse(g:placing())
  lu.assertEquals(g.money, 100)
end

-- R9 连锁：确认后资金不足的同类型不可再选。
function TestPlacement.test_unaffordable_after_confirm_not_selectable()
  local g = new_playing()
  g:select("Repair")
  g:confirm(0, 3)
  lu.assertFalse(g:placing())
  lu.assertEquals(g.money, 0)
  lu.assertFalse(g:selectable("Repair"))
end

-- R3：放置态中选择另一类型须先取消。
function TestPlacement.test_selecting_other_kind_requires_cancel()
  local g = new_playing()
  g:select("Relay")
  g:select("Radar")
  lu.assertEquals(g.placing_kind, "Relay")
  g:cancel()
  g:select("Radar")
  lu.assertEquals(g.placing_kind, "Radar")
end

-- R2：资金不足时选择无效。
function TestPlacement.test_select_unaffordable_ignored()
  local g = new_playing()
  g.money = 9
  g:select("Relay")
  lu.assertFalse(g:placing())
end

-- R8：落点必须在棋盘范围内（供电圈延伸到界外也不算）。
function TestPlacement.test_spot_outside_board_rejected()
  local g = new_playing()
  for i = 1, 6 do g.entities:add_building("Relay", 0, 3.1 * i) end
  advance_seconds(g, 2)
  lu.assertTrue(g.grid:powered(g.entities:find("Relay", 0, 18.6)))
  g:place("Turret", 0, 21.4)
  lu.assertFalse(g.entities:present("Turret"))
end

-- R8（对局流程）：Pregame 忽略放置意图。
function TestPlacement.test_pregame_place_ignored()
  local g = match_flow.new()
  g:place("Relay", 0, 3)
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertFalse(g:placing())
end
