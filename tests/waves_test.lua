-- Unit tests for the wave rules (docs/gdd/07-enemies-waves.md W1–W10):
-- calm countdown 30s, direction reveal at ≤5s, budget/tier caps, spawn
-- interval per wave, spawn point offboard, assault window, wave advance only
-- when the wave is fully cleared.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local waves = require("server.game.waves")

TestWaves = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

local function alive_enemies(g)
  local n = 0
  for _, e in ipairs(g.enemies.list) do
    if e.alive then n = n + 1 end
  end
  return n
end

-- W1/W2：新对局第 1 波倒计时 30，方向未知。
function TestWaves.test_initial_wave_state()
  local g = new_playing()
  lu.assertEquals(g.wave.number, 1)
  lu.assertEquals(g.wave.countdown, 30)
  lu.assertFalse(g.wave.assault)
  lu.assertNil(waves.revealed_direction(g))
end

-- W2：倒计时 > 5 方向未知，≤ 5 公布且属于东南西北。
function TestWaves.test_direction_revealed_at_five_seconds()
  local g = new_playing()
  advance_seconds(g, 24.5)
  lu.assertNil(waves.revealed_direction(g))
  advance_seconds(g, 1)
  local d = waves.revealed_direction(g)
  lu.assertTrue(d == "东" or d == "南" or d == "西" or d == "北")
end

-- W3/W6/W8：第 1 波预算 2 → 2 个 1 型；进攻期从首个生成起。
function TestWaves.test_wave1_spawns_two_tier1_enemies()
  local g = new_playing()
  advance_seconds(g, 29.5)
  lu.assertEquals(#g.enemies.list, 0)
  lu.assertFalse(g.wave.assault)
  advance_seconds(g, 1)
  lu.assertEquals(#g.enemies.list, 1)
  lu.assertTrue(g.wave.assault)
  advance_seconds(g, 1)
  lu.assertEquals(#g.enemies.list, 2)
  for _, e in ipairs(g.enemies.list) do lu.assertEquals(e.tier, 1) end
end

-- W4：生成间隔 max(0.25, 1 − 0.1(N−1))；第 8 波 0.3 秒。
function TestWaves.test_spawn_interval_shortens_by_wave()
  local g = new_playing()
  waves.set_wave(g, 8)
  advance_seconds(g, 30.4)
  lu.assertEquals(#g.enemies.list, 2)
  advance_seconds(g, 0.2)
  lu.assertEquals(#g.enemies.list, 3)
end

-- W5/W6：随机源固定最大值时各波的数量、最高层级与成本总和。
function TestWaves.test_budget_and_tier_caps_with_max_rng()
  local g = new_playing()
  g.rng01 = function() return 1 end

  waves.set_wave(g, 3)
  advance_seconds(g, 35)
  lu.assertEquals(#g.enemies.list, 4)
  lu.assertEquals(g.wave.cost_sum, 4)
  for _, e in ipairs(g.enemies.list) do lu.assertEquals(e.tier, 1) end
end

function TestWaves.test_wave4_with_max_rng()
  local g = new_playing()
  g.rng01 = function() return 1 end
  waves.set_wave(g, 4)
  advance_seconds(g, 35)
  lu.assertEquals(#g.enemies.list, 4)
  lu.assertAlmostEquals(g.wave.cost_sum, 5.5, 1e-9)
  local max_tier = 0
  for _, e in ipairs(g.enemies.list) do max_tier = math.max(max_tier, e.tier) end
  lu.assertEquals(max_tier, 2)
end

function TestWaves.test_wave8_with_max_rng()
  local g = new_playing()
  g.rng01 = function() return 1 end
  waves.set_wave(g, 8)
  advance_seconds(g, 35)
  lu.assertEquals(#g.enemies.list, 4)
  lu.assertAlmostEquals(g.wave.cost_sum, 9, 1e-9)
  local max_tier = 0
  for _, e in ipairs(g.enemies.list) do max_tier = math.max(max_tier, e.tier) end
  lu.assertEquals(max_tier, 3)
end

-- W6：预算 > 0 就继续、最后一个可超支；第 4 波成本总和落在 [5, 5.5]。
function TestWaves.test_wave4_cost_sum_bounds_for_any_rng()
  for seed = 1, 20 do
    math.randomseed(seed)
    local g = new_playing()
    waves.set_wave(g, 4)
    advance_seconds(g, 35)
    lu.assertTrue(g.wave.cost_sum >= 5 - 1e-9)
    lu.assertTrue(g.wave.cost_sum <= 5.5 + 1e-9)
  end
  math.randomseed(os.time())
end

-- W9：本波生成完毕且全灭才进入下一波（波号+1、倒计时 30、方向未知）。
function TestWaves.test_wave_advances_only_when_fully_cleared()
  local g = new_playing()
  advance_seconds(g, 32)
  lu.assertEquals(alive_enemies(g), 2)
  g.enemies.list[1].health = 0
  g.enemies.list[1].alive = false
  advance_seconds(g, 1)
  lu.assertEquals(g.wave.number, 1)
  lu.assertTrue(g.wave.assault)
  g.enemies.list[2].health = 0
  g.enemies.list[2].alive = false
  advance_seconds(g, 1)
  lu.assertEquals(g.wave.number, 2)
  lu.assertAlmostEquals(g.wave.countdown, 29, 1e-6)
  lu.assertFalse(g.wave.assault)
  lu.assertNil(waves.revealed_direction(g))
end

-- W7：生成点在所选边界外 6 单位；随机源固定最大值 → 方向北、另一轴取棋盘边。
function TestWaves.test_spawn_point_six_units_offboard()
  local g = new_playing()
  g.rng01 = function() return 1 end
  waves.set_wave(g, 1) -- 方向在波次开始时选定，固定随机源后重置
  advance_seconds(g, 30) -- 生成当拍即开始飞行，容差含首步位移
  local e = g.enemies.list[1]
  lu.assertAlmostEquals(e.x, 20, 0.1)
  lu.assertAlmostEquals(e.z, 26, 0.1)
end
