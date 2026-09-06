-- Unit tests for src/server/game/match_flow.lua: the match-flow rule module
-- (docs/gdd/01-match-flow.md R1–R8). Four-phase state machine, time freeze,
-- win/lose judgement, restart; minimal wave state and building death/crumble.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")

TestMatchFlow = {}

local SECONDS = 30 -- host fixed step is 1/30s; advance_seconds drives n steps

local function advance_seconds(g, n)
  for _ = 1, n * SECONDS do g:advance(1 / SECONDS) end
end

-- R1/R2: new game is Pregame with wave 1 at 30s; start enters Playing, money 100
function TestMatchFlow.test_new_game_is_pregame_with_initial_layout()
  local g = match_flow.new()
  lu.assertEquals(g.mode, "Pregame")
  lu.assertEquals(g.wave.number, 1)
  lu.assertEquals(g.wave.countdown, 30)
  lu.assertFalse(g.wave.assault)
  lu.assertEquals(g.entities:count_buildings(), 1)
  lu.assertTrue(g.entities:present("Core"))
  lu.assertEquals(g.entities:count_sites(), 27)
end

function TestMatchFlow.test_start_enters_playing_and_sets_starting_money()
  local g = match_flow.new()
  lu.assertNotEquals(g.money, 100)
  g:start()
  lu.assertEquals(g.mode, "Playing")
  lu.assertEquals(g.money, 100)
end

-- R3: time freeze outside Playing
function TestMatchFlow.test_pregame_advance_freezes_countdown_and_money()
  local g = match_flow.new()
  local money, countdown = g.money, g.wave.countdown
  advance_seconds(g, 60)
  lu.assertEquals(g.mode, "Pregame")
  lu.assertEquals(g.wave.countdown, countdown)
  lu.assertEquals(g.money, money)
end

function TestMatchFlow.test_playing_advance_ticks_wave_countdown()
  local g = match_flow.new()
  g:start()
  advance_seconds(g, 1)
  lu.assertAlmostEquals(g.wave.countdown, 29, 1e-6)
end

-- R4: victory when every site is depleted and gone
function TestMatchFlow.test_victory_when_all_sites_gone()
  local g = match_flow.new()
  g:start()
  g.entities:deplete_sites(27)
  lu.assertEquals(g.entities:count_sites(), 0)
  advance_seconds(g, 1)
  lu.assertEquals(g.mode, "Victory")
end

function TestMatchFlow.test_no_victory_while_a_site_remains()
  local g = match_flow.new()
  g:start()
  g.entities:deplete_sites(26)
  advance_seconds(g, 1)
  lu.assertEquals(g.entities:count_sites(), 1)
  lu.assertEquals(g.mode, "Playing")
end

-- R5: defeat when Core leaves (death, then gone after 2s crumble)
function TestMatchFlow.test_core_death_crumbles_two_seconds_before_leaving()
  local g = match_flow.new()
  g:start()
  g.entities:kill("Core")
  advance_seconds(g, 1)
  lu.assertTrue(g.entities:present("Core"))
  lu.assertEquals(g.mode, "Playing")
  advance_seconds(g, 2)
  lu.assertFalse(g.entities:present("Core"))
  lu.assertEquals(g.mode, "GameOver")
end

-- R3 again: end phases freeze countdown and money
function TestMatchFlow.test_victory_freezes_time()
  local g = match_flow.new()
  g:start()
  g.entities:deplete_sites(27)
  advance_seconds(g, 1)
  lu.assertEquals(g.mode, "Victory")
  local money, countdown = g.money, g.wave.countdown
  advance_seconds(g, 60)
  lu.assertEquals(g.wave.countdown, countdown)
  lu.assertEquals(g.money, money)
end

function TestMatchFlow.test_gameover_freezes_time()
  local g = match_flow.new()
  g:start()
  g.entities:kill("Core")
  advance_seconds(g, 3)
  lu.assertEquals(g.mode, "GameOver")
  local money, countdown = g.money, g.wave.countdown
  advance_seconds(g, 60)
  lu.assertEquals(g.wave.countdown, countdown)
  lu.assertEquals(g.money, money)
end

-- R7: restart rebuilds the initial layout in Pregame
function TestMatchFlow.test_restart_rebuilds_initial_layout()
  local g = match_flow.new()
  g:start()
  g.entities:add_building("Relay", 2, 0)
  g.entities:deplete_sites(5)
  g.entities:kill("Core")
  advance_seconds(g, 3)
  lu.assertEquals(g.mode, "GameOver")
  g:restart()
  lu.assertEquals(g.mode, "Pregame")
  lu.assertTrue(g.entities:present("Core"))
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertEquals(g.entities:count_buildings(), 1)
  lu.assertEquals(g.entities:count_sites(), 27)
  lu.assertEquals(g.wave.number, 1)
  lu.assertEquals(g.wave.countdown, 30)
  g:start()
  lu.assertEquals(g.money, 100)
end

-- R8: Pregame ignores placement intents
function TestMatchFlow.test_pregame_ignores_placement()
  local g = match_flow.new()
  g:place("Relay", 2, 0)
  lu.assertEquals(g.mode, "Pregame")
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertEquals(g.entities:count_buildings(), 1)
end

function TestMatchFlow.test_playing_placement_builds_and_charges()
  local g = match_flow.new()
  g:start()
  g:place("Relay", 2, 0)
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
end

-- 放置守卫：未知建筑、不可建造（无价格）与资金不足都是无操作
function TestMatchFlow.test_place_unknown_kind_is_noop()
  local g = match_flow.new()
  g:start()
  g:place("Bogus", 2, 0)
  lu.assertEquals(g.money, 100)
  lu.assertEquals(g.entities:count_buildings(), 1)
end

function TestMatchFlow.test_place_unbuildable_core_is_noop()
  local g = match_flow.new()
  g:start()
  g:place("Core", 2, 0)
  lu.assertEquals(g.money, 100)
  lu.assertEquals(g.entities:count_buildings(), 1)
end

function TestMatchFlow.test_place_insufficient_funds_is_noop()
  local g = match_flow.new()
  g:start()
  g:place("Repair", 2, 0)
  lu.assertEquals(g.money, 0)
  g:place("Relay", 4, 0)
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertEquals(g.money, 0)
end

-- kill 未命中：场上没有该类型的活建筑时返回 nil 且布局不变
function TestMatchFlow.test_kill_absent_kind_returns_nil()
  local g = match_flow.new()
  lu.assertNil(g.entities:kill("Turret"))
  lu.assertEquals(g.entities:count_buildings(), 1)
end
