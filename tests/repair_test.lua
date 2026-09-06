-- Unit tests for the repair rules (docs/gdd/06-repair.md R1–R7): powered
-- Repair heals the lowest-ratio damaged building in its circle at 0.5/s,
-- excludes itself, retargets when full/out of circle/gone, unpowered Repair
-- idles, out-of-circle buildings are ignored.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")

TestRepair = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

-- 背景同 repair.feature：Repair (0,3.5) 通电去抖 1 秒。
local function new_with_repair()
  local g = new_playing()
  local r = g.entities:add_building("Repair", 0, 3.5)
  advance_seconds(g, 1)
  return g, r
end

-- R1/R3：圈内受伤建筑以 0.5 血/秒修至满血。
function TestRepair.test_heals_at_half_health_per_second_to_full()
  local g = new_with_repair()
  local t = g.entities:add_building("Turret", 2, 3.5)
  t.health = 3
  advance_seconds(g, 3)
  lu.assertAlmostEquals(t.health, 4.5, 1e-9)
  advance_seconds(g, 1)
  lu.assertAlmostEquals(t.health, 5, 1e-9)
  advance_seconds(g, 2)
  lu.assertAlmostEquals(t.health, 5, 1e-9)
end

-- R1/R4：先修血量比例最低者，修满后转修下一个。
function TestRepair.test_lowest_ratio_first_then_next()
  local g = new_with_repair()
  local relay = g.entities:add_building("Relay", 2, 3.5)
  relay.health = 1 -- 50%
  local turret = g.entities:add_building("Turret", -2, 3.5)
  turret.health = 3 -- 60%
  advance_seconds(g, 1)
  lu.assertAlmostEquals(relay.health, 1.5, 1e-9)
  lu.assertAlmostEquals(turret.health, 3, 1e-9)
  advance_seconds(g, 2)
  lu.assertAlmostEquals(relay.health, 2, 1e-9)
  lu.assertAlmostEquals(turret.health, 3.5, 1e-9)
end

-- R2：Repair 不修自己。
function TestRepair.test_no_self_repair()
  local g, r = new_with_repair()
  r.health = 5
  advance_seconds(g, 4)
  lu.assertAlmostEquals(r.health, 5, 1e-9)
end

-- R2：两座 Repair 互修。
function TestRepair.test_two_repairs_heal_each_other()
  local g, r1 = new_with_repair()
  local r2 = g.entities:add_building("Repair", 2, 3.5)
  advance_seconds(g, 1)
  r1.health = 5
  r2.health = 5
  advance_seconds(g, 2)
  lu.assertAlmostEquals(r1.health, 6, 1e-9)
  lu.assertAlmostEquals(r2.health, 6, 1e-9)
end

-- R6：未通电 Repair 不维修。
function TestRepair.test_unpowered_repair_does_not_heal()
  local g = new_with_repair()
  local r = g.entities:add_building("Repair", 0, 9)
  local t = g.entities:add_building("Turret", 2, 9)
  t.health = 3
  advance_seconds(g, 4)
  lu.assertFalse(g.grid:powered(r))
  lu.assertAlmostEquals(t.health, 3, 1e-9)
end

-- R7：维修圈 5 与目标足迹圆相交判定（Turret 足迹 0.4）。
function TestRepair.test_circle_boundary()
  local g = new_with_repair()
  local inside = g.entities:add_building("Turret", 0, 8.8)
  inside.health = 3
  local outside = g.entities:add_building("Turret", 0, 9.5)
  outside.health = 3
  advance_seconds(g, 4)
  lu.assertAlmostEquals(inside.health, 5, 1e-9)
  lu.assertAlmostEquals(outside.health, 3, 1e-9)
end
