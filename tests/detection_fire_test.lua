-- Unit tests for detection and fire rules (docs/gdd/05-detection-fire.md
-- R1–R8): powered Radar reveals enemies on circle intersection, Turret fires
-- only at revealed enemies in range, nearest-target selection, 180°/s turning
-- with ≤2° fire angle, 0.5 damage per shot with 0.05s beam settle, 2/s
-- cadence, power gating, range gating.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local enemies = require("server.game.enemies")

TestDetectionFire = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

local function spawn(g, x, z, dx, dz)
  return enemies.spawn(g, { x = x, z = z, tier = 1, heading = { x = dx, z = dz } })
end

local function face_north(e) e.muzzle = { x = 0, z = 1 } end

-- 标准阵地：Radar (0,3.5) + Turret (1.5,3.5) 朝北，通电去抖 1 秒。
local function new_outpost()
  local g = new_playing()
  g.entities:add_building("Radar", 0, 3.5)
  local turret = g.entities:add_building("Turret", 1.5, 3.5)
  face_north(turret)
  advance_seconds(g, 1)
  return g
end

-- R1：探测圈 8 与敌人足迹圆（0.3）相交判定。
function TestDetectionFire.test_reveal_boundary()
  local g = new_playing()
  g.entities:add_building("Radar", 0, 3.5)
  advance_seconds(g, 1)
  spawn(g, 0, 11.6, 0, -1)
  advance_seconds(g, 0.1)
  lu.assertTrue(g.enemies.list[1].revealed)
  spawn(g, 0, 12.2, 0, -1)
  advance_seconds(g, 0.1)
  lu.assertFalse(g.enemies.list[2].revealed)
end

-- R2/R6：无 Radar 揭示时射程内敌人不受伤害。
function TestDetectionFire.test_no_damage_without_reveal()
  local g = new_playing()
  local turret = g.entities:add_building("Turret", 1.5, 3.5)
  face_north(turret)
  advance_seconds(g, 1)
  local e = spawn(g, 1.5, 4.6, 0, -1)
  advance_seconds(g, 4)
  lu.assertFalse(e.revealed)
  lu.assertEquals(e.health, 4)
end

-- R5/R7：已揭示且在射程内，持续射击至死亡（8 发 × 0.5）。
function TestDetectionFire.test_shot_cadence_kills_tier1_in_four_seconds()
  local g = new_outpost()
  local e = spawn(g, 1.5, 4.6, 0, -1)
  advance_seconds(g, 2)
  lu.assertAlmostEquals(e.health, 2, 1e-9)
  advance_seconds(g, 1.4)
  lu.assertAlmostEquals(e.health, 0.5, 1e-9)
  lu.assertTrue(e.alive)
  advance_seconds(g, 0.6)
  lu.assertEquals(e.health, 0)
  lu.assertFalse(e.alive)
end

-- R3：射程内已揭示敌人中打更近的。
function TestDetectionFire.test_fires_at_nearer_enemy()
  local g = new_outpost()
  local near = spawn(g, 1.5, 4.6, 0, -1)
  local far = spawn(g, 1.5, 7, 0, -1)
  advance_seconds(g, 1)
  lu.assertAlmostEquals(near.health, 3, 1e-9)
  lu.assertEquals(far.health, 4)
end

-- R6/R1：Radar 断电后停火，恢复后继续。
function TestDetectionFire.test_fire_pauses_while_radar_unpowered()
  local g = new_outpost()
  local e = spawn(g, 1.5, 4.6, 0, -1)
  advance_seconds(g, 1)
  lu.assertAlmostEquals(e.health, 3, 1e-9)
  -- 拆掉 Radar：断电去抖期间至多再吃一枪，之后血量冻结。
  g.entities:remove(g.entities:find("Radar", 0, 3.5))
  advance_seconds(g, 0.5)
  lu.assertFalse(e.revealed)
  local frozen = e.health
  advance_seconds(g, 2)
  lu.assertEquals(e.health, frozen)
  g.entities:add_building("Radar", 0, 3.5)
  advance_seconds(g, 2)
  lu.assertTrue(e.revealed)
  lu.assertTrue(e.health < frozen)
end

-- R6：未通电 Turret 不开火（敌人已揭示）。
function TestDetectionFire.test_unpowered_turret_does_not_fire()
  local g = new_playing()
  g.entities:add_building("Radar", 0, 3.5)
  local turret = g.entities:add_building("Turret", 0, 6)
  face_north(turret)
  advance_seconds(g, 1)
  lu.assertFalse(g.grid:powered(turret))
  local e = spawn(g, 0, 7.1, 0, -1)
  advance_seconds(g, 4)
  lu.assertTrue(e.revealed)
  lu.assertEquals(e.health, 4)
end

-- R2：敌人离开射程后停火。
function TestDetectionFire.test_fire_stops_when_enemy_leaves_range()
  local g = new_outpost()
  g.entities:add_building("Relay", 1.5, 11.5)
  spawn(g, 1.5, 8.5, 0, 1) -- 朝北飞向 Relay，远离 Turret
  advance_seconds(g, 1)
  lu.assertAlmostEquals(g.enemies.list[1].health, 3.5, 1e-9)
  advance_seconds(g, 2)
  lu.assertAlmostEquals(g.enemies.list[1].health, 3.5, 1e-9)
end

-- R4：目标在正后方时转向 1 秒后才开第一枪。
function TestDetectionFire.test_turnaround_delays_first_shot()
  local g = new_playing()
  g.entities:add_building("Radar", 0, 3.5)
  local turret = g.entities:add_building("Turret", 1.5, 3.5)
  turret.muzzle = { x = 0, z = -1 }
  advance_seconds(g, 1)
  local e = spawn(g, 1.5, 4.6, 0, -1)
  advance_seconds(g, 0.9)
  lu.assertEquals(e.health, 4)
  advance_seconds(g, 0.5)
  lu.assertAlmostEquals(e.health, 3.5, 1e-9)
end
