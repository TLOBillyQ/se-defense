-- Behavior-level unit tests for server/game semantics landed by the rewrite
-- feature migration (docs/gdd/ rules). Pure-module checks go straight at the
-- module; component behavior boots a fresh headless game per test via
-- tools/acceptance/headless.lua (real adapter over the SE stub, no mocks).
local lu = require("luaunit")
local CollisionBody = require("server.game.collision_body")
local headless = require("tools.acceptance.headless")

TestCollision = {}

-- GDD 04 R4 / 03 R2：足迹圆相切算相交。
function TestCollision.test_tangent_circles_overlap()
  local a = { center = { x = 0, z = 0 }, radius = 0.5 }
  local b = { center = { x = 0.8, z = 0 }, radius = 0.3 }
  lu.assertTrue(CollisionBody.circles_overlap(a, b))
end

function TestCollision.test_separated_circles_do_not_overlap()
  local a = { center = { x = 0, z = 0 }, radius = 0.5 }
  local b = { center = { x = 0.800001, z = 0 }, radius = 0.3 }
  lu.assertFalse(CollisionBody.circles_overlap(a, b))
end

TestGame = {}

local function boot_playing()
  local s = headless.boot()
  headless.send(s, { kind = "input", itype = "start" })
  headless.steps(s, 3)
  return s
end

-- GDD 01 R2/R6：手动开局；start 前 Pregame、资金未发。
function TestGame.test_pregame_waits_for_start()
  local s = headless.boot()
  lu.assertEquals(headless.mode(s), "Pregame")
  lu.assertEquals(headless.money(s), 0)
  headless.advance(s, 5)
  lu.assertEquals(headless.mode(s), "Pregame") -- 无自动开局
  headless.send(s, { kind = "input", itype = "start" })
  headless.steps(s, 3)
  lu.assertEquals(headless.mode(s), "Playing")
  lu.assertEquals(headless.money(s), 100)
end

-- GDD 00 实体总表：Turret 足迹 0.4、Relay 0.3（Building 默认值 0.6 不得泄漏）。
-- 中心距 0.75：0.4+0.3 不相交可放；若任一方按 0.6 则必被挡。
function TestGame.test_building_footprint_radius_threaded()
  local s = boot_playing()
  headless.gm(s, "spawn_building", "Turret", 3, 0)
  headless.steps(s, 2)
  headless.send(s, { kind = "input", itype = "place", key = "relay" })
  headless.send(s, { kind = "input", itype = "tap", x = 3, z = 0.75 })
  headless.steps(s, 3)
  lu.assertTrue(headless.building_present(s, "Relay"))
  lu.assertEquals(headless.money(s), 90)
end

-- GDD 04：矿点足迹占落点；采空离场后落点放开。
function TestGame.test_site_footprint_released_on_depleted()
  local s = boot_playing()
  headless.send(s, { kind = "input", itype = "place", key = "relay" })
  headless.send(s, { kind = "input", itype = "tap", x = 1.71, z = 0.06 })
  headless.steps(s, 3)
  lu.assertFalse(headless.building_present(s, "Relay"))
  headless.gm(s, "set_site", 1.71, 0.06, 0)
  headless.steps(s, 3)
  headless.send(s, { kind = "input", itype = "tap", x = 1.71, z = 0.06 })
  headless.steps(s, 3)
  lu.assertTrue(headless.building_present(s, "Relay"))
  lu.assertEquals(headless.money(s), 90)
end

-- GDD 02 R3/R6：开局 3 个通电矿点，速率 3.75/s，每 0.8s 各兑 $1。
function TestGame.test_initial_harvest()
  local s = boot_playing()
  lu.assertEquals(headless.collect_rate(s), 3.75)
  headless.advance(s, 0.8)
  lu.assertEquals(headless.money(s), 103)
end

-- GDD 03：Relay 经去抖通电；上游被毁后下游同拍断电（目标态递推）。
function TestGame.test_power_chain_same_tick_cutoff()
  local s = boot_playing()
  headless.gm(s, "spawn_building", "Relay", 0, 3)
  headless.gm(s, "spawn_building", "Relay", 0, 5.5)
  headless.advance(s, 0.5) -- 两级去抖：r1 0.15s 通电后 r2 再去抖 0.15s
  local r1 = headless.building_at(s, "Relay", 0, 3)
  local r2 = headless.building_at(s, "Relay", 0, 5.5)
  lu.assertTrue(headless.building_power(r1))
  lu.assertTrue(headless.building_power(r2))
  local prov = headless.provider_pos(r2)
  lu.assertTrue(prov and math.abs(prov.x) < 1e-6 and math.abs(prov.z - 3) < 1e-6,
    "r2 应经 r1 取电")
  headless.gm(s, "destroy_at", "Relay", 0, 3)
  headless.advance(s, 0.2)
  lu.assertFalse(headless.building_power(r2))
end

-- GDD 07 W1：首波倒计时 30 秒，随时间递减。
function TestGame.test_first_wave_countdown()
  local s = boot_playing()
  local c0 = headless.wave(s).countdown
  lu.assertAlmostEquals(c0, 30, 0.2) -- 开局起即倒数
  headless.advance(s, 1)
  lu.assertAlmostEquals(headless.wave(s).countdown, c0 - 1, 0.05)
end

-- GDD 05 R1/R3：被雷达揭示的敌人在射程内受击，每发 0.5 伤。
function TestGame.test_turret_fires_on_revealed_enemy()
  local s = boot_playing()
  headless.gm(s, "spawn_building", "Radar", 0, -3)
  headless.gm(s, "spawn_building", "Turret", 0, 3)
  headless.advance(s, 0.2)
  headless.gm(s, "spawn_enemy_at", 4, 0, "西", 1)
  headless.advance(s, 0.2)
  local e = headless.enemy_nth(s, 1)
  lu.assertTrue(headless.enemy_tracked(e))
  local hp0 = headless.enemy_hp(e)
  headless.advance(s, 2)
  lu.assertTrue(headless.enemy_hp(e) < hp0, "敌人血量应下降（" .. tostring(hp0) .. " → " .. tostring(headless.enemy_hp(e)) .. "）")
end

-- GDD 06 R1/R3：Repair 以 0.5/s 维修范围内受伤建筑。
function TestGame.test_repair_heals_damaged_building()
  local s = boot_playing()
  headless.gm(s, "spawn_building", "Repair", 0, 3.5)
  headless.advance(s, 1) -- 先让 Repair 通电去抖生效（repair.feature 约定）
  headless.gm(s, "spawn_building", "Radar", 0, -1, 5) -- 血量置 5/10
  local r = headless.building_at(s, "Radar", 0, -1)
  local hp0 = headless.building_hp(r)
  headless.advance(s, 2)
  lu.assertAlmostEquals(headless.building_hp(r) - hp0, 1.0, 0.15) -- 0.5/s × 2s
end

-- GDD 01 R4/R5：矿点全采空 → Victory；Core 毁 → 碎裂 2 秒后 GameOver。
function TestGame.test_match_endings()
  local s = boot_playing()
  headless.gm(s, "mine_out")
  headless.steps(s, 3)
  lu.assertEquals(headless.mode(s), "Victory")

  local s2 = boot_playing()
  headless.gm(s2, "kill_core")
  headless.steps(s2, 3)
  lu.assertEquals(headless.mode(s2), "Playing") -- 碎裂期间仍 Playing
  headless.advance(s2, 2.2)
  lu.assertEquals(headless.mode(s2), "GameOver")
end
