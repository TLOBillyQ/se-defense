-- Unit tests for the economy rules (docs/gdd/02-economy.md R1–R8):
-- harvest cadence 0.8s per powered site, assault pause, depletion removal,
-- harvest rate readout, relay-chain powered sites.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")

TestEconomy = {}

local function advance_seconds(g, n)
  for _ = 1, math.floor(n * 30 + 0.5) do g:advance(1 / 30) end
end

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g
end

local function site_at(g, x, z)
  return g.entities:find("Site", x, z)
end

-- R3：通电矿点非进攻期每 0.8 秒兑 1 单位为 $1（开局 3 个通电矿点）。
function TestEconomy.test_no_harvest_before_interval()
  local g = new_playing()
  advance_seconds(g, 0.7)
  lu.assertEquals(site_at(g, 1.71, 0.06).remaining, 300)
  lu.assertEquals(g.money, 100)
end

function TestEconomy.test_first_harvest_at_interval()
  local g = new_playing()
  advance_seconds(g, 0.8)
  lu.assertEquals(site_at(g, 1.71, 0.06).remaining, 299)
  lu.assertEquals(g.money, 103)
end

function TestEconomy.test_harvest_over_eight_seconds()
  local g = new_playing()
  advance_seconds(g, 8)
  lu.assertEquals(site_at(g, 1.71, 0.06).remaining, 290)
  lu.assertEquals(g.money, 130)
end

-- R2：未通电矿点不采集。
function TestEconomy.test_unpowered_site_does_not_harvest()
  local g = new_playing()
  advance_seconds(g, 8)
  lu.assertEquals(site_at(g, 0.47, 15.53).remaining, 300)
  lu.assertEquals(g.money, 130)
end

-- R4：进攻期停采，全灭后恢复。
function TestEconomy.test_assault_pauses_harvest()
  local g = new_playing()
  g.wave.assault = true
  advance_seconds(g, 8)
  lu.assertEquals(g.money, 100)
  lu.assertEquals(site_at(g, 1.71, 0.06).remaining, 300)
end

function TestEconomy.test_harvest_resumes_after_assault()
  local g = new_playing()
  g.wave.assault = true
  advance_seconds(g, 8)
  g.wave.assault = false
  advance_seconds(g, 0.8)
  lu.assertEquals(g.money, 103)
end

-- R5：剩余量到 0 离场。
function TestEconomy.test_depleted_site_leaves()
  local g = new_playing()
  site_at(g, 1.71, 0.06).remaining = 1
  advance_seconds(g, 0.7)
  lu.assertEquals(g.entities:count_sites(), 27)
  advance_seconds(g, 0.1)
  lu.assertEquals(g.entities:count_sites(), 26)
  lu.assertNil(site_at(g, 1.71, 0.06))
end

-- R6：采集速率 = 采集中矿点数 × 1.25/s。
function TestEconomy.test_harvest_rate()
  local g = new_playing()
  lu.assertAlmostEquals(g.economy:rate(), 3.75, 1e-9)
  g.entities:remove(site_at(g, -1.99, -0.10))
  advance_seconds(g, 1)
  lu.assertAlmostEquals(g.economy:rate(), 2.5, 1e-9)
end

function TestEconomy.test_rate_zero_during_assault()
  local g = new_playing()
  g.wave.assault = true
  lu.assertAlmostEquals(g.economy:rate(), 0, 1e-9)
end

-- R8：经 Relay 链通电的矿点可采集（去抖 0.15 秒逐段生效）。
function TestEconomy.test_relay_chain_site_harvests()
  local g = new_playing()
  g.entities:add_building("Relay", 2.8, -2.8)
  g.entities:add_building("Relay", 4.5, -5.3)
  advance_seconds(g, 1.5)
  lu.assertEquals(site_at(g, 6.15, -7.75).remaining, 299)
end

-- 摧毁供电 Relay 后矿点断电停采。
function TestEconomy.test_harvest_stops_when_relay_destroyed()
  local g = new_playing()
  g.entities:add_building("Relay", 2.8, -2.8)
  g.entities:add_building("Relay", 4.5, -5.3)
  advance_seconds(g, 1.5)
  g.entities:remove(g.entities:find("Relay", 2.8, -2.8))
  advance_seconds(g, 9)
  lu.assertEquals(site_at(g, 6.15, -7.75).remaining, 299)
end
