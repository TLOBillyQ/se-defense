-- Unit tests for the power grid rules (docs/gdd/03-power-grid.md R1–R10)
-- exercised through the match: Core-rooted provider tree, attach boundary,
-- debounce 0.15s, outage propagation, provider preemption, cycle guard.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")

TestPowerGrid = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

local function at(g, kind, x, z)
  return g.entities:find(kind, x, z)
end

-- 开局即接入 Core 的矿点恰有 3 个，开始对局时已通电（无启动去抖）。
function TestPowerGrid.test_initial_sites_near_core_powered_from_boot()
  local g = new_playing()
  lu.assertTrue(g.grid:powered(at(g, "Site", 1.71, 0.06)))
  lu.assertTrue(g.grid:powered(at(g, "Site", -1.30, -1.26)))
  lu.assertTrue(g.grid:powered(at(g, "Site", -1.99, -0.10)))
  lu.assertFalse(g.grid:powered(at(g, "Site", 0.47, 15.53)))
  lu.assertTrue(g.grid:powered(at(g, "Core", 0, 0)))
end

-- R2/R3：Core 圈内 Relay 通电，圈外不通电；去抖后生效。
function TestPowerGrid.test_relay_inside_core_circle_powered()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 4)
  advance_seconds(g, 1)
  lu.assertTrue(g.grid:powered(at(g, "Relay", 0, 4)))
end

function TestPowerGrid.test_relay_outside_core_circle_unpowered()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 4.3)
  advance_seconds(g, 1)
  lu.assertFalse(g.grid:powered(at(g, "Relay", 0, 4.3)))
end

-- R2 边界：圆心距恰好等于半径和（4 + 0.1）时接入。
function TestPowerGrid.test_attach_at_exact_radius_sum()
  local g = new_playing()
  g.entities:add_building("Radar", 0, 4.1)
  advance_seconds(g, 1)
  lu.assertTrue(g.grid:powered(at(g, "Radar", 0, 4.1)))
end

-- R4/R8：Relay 链送电，每段都要过去抖。
function TestPowerGrid.test_relay_chain_powers_remote_radar()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Relay", 0, 6.5)
  g.entities:add_building("Radar", 0, 9.5)
  advance_seconds(g, 1)
  lu.assertTrue(g.grid:powered(at(g, "Relay", 0, 6.5)))
  lu.assertTrue(g.grid:powered(at(g, "Radar", 0, 9.5)))
end

-- R7/R8：摧毁上游 Relay，0.15 秒去抖后下游整条分支断电。
function TestPowerGrid.test_outage_propagates_after_debounce()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Relay", 0, 6.5)
  g.entities:add_building("Radar", 0, 9.5)
  advance_seconds(g, 1)
  g.entities:remove(at(g, "Relay", 0, 3.5))
  advance_seconds(g, 0.1)
  lu.assertTrue(g.grid:powered(at(g, "Relay", 0, 6.5)))
  advance_seconds(g, 0.2)
  lu.assertFalse(g.grid:powered(at(g, "Relay", 0, 6.5)))
  lu.assertFalse(g.grid:powered(at(g, "Radar", 0, 9.5)))
end

-- 补回上游 Relay 后下游恢复通电。
function TestPowerGrid.test_rebuilt_relay_restores_branch()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Relay", 0, 6.5)
  g.entities:add_building("Radar", 0, 9.5)
  advance_seconds(g, 1)
  g.entities:remove(at(g, "Relay", 0, 3.5))
  advance_seconds(g, 1)
  g.entities:add_building("Relay", 0, 3.5)
  advance_seconds(g, 1)
  lu.assertTrue(g.grid:powered(at(g, "Relay", 0, 6.5)))
  lu.assertTrue(g.grid:powered(at(g, "Radar", 0, 9.5)))
end

-- R6：更近的通电供电者出现才切换；更远的不切换。
function TestPowerGrid.test_preemption_switches_to_closer_provider()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Radar", 1.5, 5.5)
  advance_seconds(g, 1)
  g.entities:add_building("Relay", 1.5, 3.5)
  advance_seconds(g, 1)
  local p = g.grid:provider(at(g, "Radar", 1.5, 5.5))
  lu.assertEquals({ p.x, p.z }, { 1.5, 3.5 })
end

function TestPowerGrid.test_no_preemption_for_farther_provider()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Radar", 1.5, 5.5)
  advance_seconds(g, 1)
  g.entities:add_building("Relay", 2.5, 3)
  advance_seconds(g, 1)
  local p = g.grid:provider(at(g, "Radar", 1.5, 5.5))
  lu.assertEquals({ p.x, p.z }, { 0, 3.5 })
end

-- R6 环保护：下游 Relay 更近也不能成为上游的供电者。
function TestPowerGrid.test_downstream_relay_cannot_provide_upstream()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 3.5)
  g.entities:add_building("Relay", 0, 6.5)
  advance_seconds(g, 1)
  local pa = g.grid:provider(at(g, "Relay", 0, 3.5))
  local pb = g.grid:provider(at(g, "Relay", 0, 6.5))
  lu.assertEquals({ pa.x, pa.z }, { 0, 0 })
  lu.assertEquals({ pb.x, pb.z }, { 0, 3.5 })
end

-- R10：未通电 Relay 不对外供电。
function TestPowerGrid.test_unpowered_relay_provides_nothing()
  local g = new_playing()
  g.entities:add_building("Relay", 0, 6)
  g.entities:add_building("Radar", 0, 8)
  advance_seconds(g, 1)
  lu.assertFalse(g.grid:powered(at(g, "Relay", 0, 6)))
  lu.assertFalse(g.grid:powered(at(g, "Radar", 0, 8)))
end
