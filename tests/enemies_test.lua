-- Unit tests for the enemy rules (docs/gdd/07-enemies-waves.md E1–E7):
-- tier stats, route-target scoring, flight at 1/s stopping at 1.2, bombing
-- cadence 1s with 0.3s fuse, bomb radius hurting all buildings but sites,
-- target reselection, Core death after 20 bombs.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local enemies = require("server.game.enemies")

TestEnemies = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

local function spawn(g, x, z, tier, dx, dz)
  return enemies.spawn(g, { x = x, z = z, tier = tier, heading = { x = dx, z = dz } })
end

-- E1：三层级仅血量与足迹不同。
function TestEnemies.test_tier_stats()
  local g = new_playing()
  local e1 = spawn(g, 0, 30, 1, 0, -1)
  local e2 = spawn(g, 0, 30, 2, 0, -1)
  local e3 = spawn(g, 0, 30, 3, 0, -1)
  lu.assertEquals({ e1.health, e1.footprint }, { 4, 0.3 })
  lu.assertEquals({ e2.health, e2.footprint }, { 8, 0.4 })
  lu.assertEquals({ e3.health, e3.footprint }, { 16, 0.5 })
end

-- E3/E4：直飞评分最低的目标，停在 1.2 处；1 秒后首弹，引信 0.3 秒。
function TestEnemies.test_flight_stop_and_first_bomb()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3)
  spawn(g, 0, 10, 1, 0, -1)
  advance_seconds(g, 6)
  local e = g.enemies.list[1]
  lu.assertAlmostEquals(e.x, 0, 1e-9)
  lu.assertAlmostEquals(e.z, 4.2, 1e-9)
  local relay = g.entities:find("Relay", 0, 3)
  lu.assertEquals(relay.health, 2) -- 6.8 投弹、7.1 才结算
  advance_seconds(g, 1)
  lu.assertEquals(relay.health, 2)
  advance_seconds(g, 0.3)
  lu.assertAlmostEquals(relay.health, 1.5, 1e-9)
end

-- E5：炸弹半径内所有建筑受伤，矿点免伤。
function TestEnemies.test_bomb_hits_all_buildings_in_radius_but_not_sites()
  local g = new_playing()
  g.entities:add_building("Relay", 0.47, 16.5)
  g.entities:add_building("Radar", 1.2, 16)
  spawn(g, 0.47, 25, 1, 0, -1)
  advance_seconds(g, 8.5)
  lu.assertEquals(g.entities:find("Relay", 0.47, 16.5).health, 2)
  lu.assertEquals(g.entities:find("Radar", 1.2, 16).health, 10)
  advance_seconds(g, 0.5)
  lu.assertAlmostEquals(g.entities:find("Relay", 0.47, 16.5).health, 1.5, 1e-9)
  lu.assertAlmostEquals(g.entities:find("Radar", 1.2, 16).health, 9.5, 1e-9)
  lu.assertEquals(g.entities:find("Site", 0.47, 15.53).remaining, 300)
end

-- E3：目标评分 = 偏离航线垂直距离 + 0.5 × 直线距离，取最小。
function TestEnemies.test_target_scoring_prefers_smaller_score()
  local g = new_playing()
  g.entities:add_building("Relay", 2, 7) -- 偏离 2 + 0.5×3.61 = 3.80 < Core 5
  spawn(g, 0, 10, 1, 0, -1)
  lu.assertEquals(g.enemies.list[1].target, g.entities:find("Relay", 2, 7))
  advance_seconds(g, 5)
  lu.assertTrue(g.entities:find("Relay", 2, 7).health < 2)
  lu.assertEquals(g.entities:find("Core", 0, 0).health, 10)
end

-- E3：目标离场后重选并继续飞行。
function TestEnemies.test_retarget_when_target_gone()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3)
  spawn(g, 0, 10, 1, 0, -1)
  advance_seconds(g, 6) -- 已停在 Relay 1.2 处
  g.entities:remove(g.entities:find("Relay", 0, 3))
  advance_seconds(g, 1)
  local e = g.enemies.list[1]
  lu.assertEquals(e.target, g.entities:find("Core", 0, 0))
  lu.assertTrue(e.z < 4.2 - 0.5) -- 继续朝 Core 飞
end

-- E4：生成在目标 1.2 以内时原地不动，仍每秒投弹。
function TestEnemies.test_spawned_within_stop_distance_stays_put()
  local g = new_playing()
  g.entities:add_building("Turret", 1.5, 3.5)
  spawn(g, 1.5, 4.6, 1, 0, -1)
  advance_seconds(g, 2)
  local e = g.enemies.list[1]
  lu.assertAlmostEquals(e.z, 4.6, 1e-9)
  lu.assertTrue(g.entities:find("Turret", 1.5, 3.5).health < 5)
end

-- E6：间距 < 0.6 时相互推开，不重叠堆叠。
function TestEnemies.test_separation_pushes_overlapping_enemies_apart()
  local g = new_playing()
  g.entities:remove(g.entities:find("Core", 0, 0)) -- 无目标可飞，隔离分离规则
  spawn(g, 0, 10, 1, 0, -1)
  spawn(g, 0.3, 10, 1, 0, -1)
  advance_seconds(g, 0.1)
  local a, b = g.enemies.list[1], g.enemies.list[2]
  lu.assertTrue(math.abs(a.x - b.x) + math.abs(a.z - b.z) > 0)
  lu.assertTrue(math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) >= 0.6 - 1e-9)
end

-- E4/E5 + 01 R6：Core 受满 20 枚炸弹死亡并离场，对局 GameOver。
function TestEnemies.test_core_dies_after_twenty_bombs()
  local g = new_playing()
  spawn(g, 0, 3, 1, 0, -1)
  advance_seconds(g, 21.5)
  lu.assertTrue(g.entities:present("Core"))
  lu.assertEquals(g.mode, "Playing")
  advance_seconds(g, 3.5)
  lu.assertFalse(g.entities:present("Core"))
  lu.assertEquals(g.mode, "GameOver")
end
