-- Unit tests for src/server/game/entities.lua: the on-field entity registry
-- (initial layout, orchestration seams, crumble/depletion leaving, queries).
-- Phase gating of tick_crumble belongs to match_flow and is tested there.
local lu = require("luaunit")
local entities = require("server.game.entities")
local world = require("server.game.world")

TestEntities = {}

function TestEntities.test_new_registry_has_core_and_27_sites()
  local r = entities.new()
  lu.assertEquals(#r.list, 28)
  lu.assertTrue(r:present("Core"))
  lu.assertEquals(r:count_buildings(), 1)
  lu.assertEquals(r:count_sites(), 27)
  lu.assertEquals(r.list[2].remaining, world.site_remaining)
end

function TestEntities.test_add_building_assigns_unique_ids_and_spec_health()
  local r = entities.new()
  local a = r:add_building("Relay", 2, 0)
  local b = r:add_building("Turret", 3, 1)
  lu.assertNotEquals(a.id, b.id)
  lu.assertEquals(a.health, world.specs.Relay.health)
  lu.assertEquals(b.health, world.specs.Turret.health)
  lu.assertEquals(a.state, "alive")
  lu.assertEquals(r:count_buildings(), 3)
end

function TestEntities.test_add_building_rejects_unknown_or_unbuildable_kind()
  local r = entities.new()
  lu.assertError(function() r:add_building("Bogus", 0, 0) end)
  lu.assertError(function() r:add_building("Site", 0, 0) end)
end

function TestEntities.test_kill_marks_crumbling_and_leaves_after_crumble_seconds()
  local r = entities.new()
  local core = r:kill("Core")
  lu.assertEquals(core.health, 0)
  lu.assertEquals(core.state, "crumbling")
  r:tick_crumble(world.crumble_seconds - 0.5)
  lu.assertTrue(r:present("Core"))
  r:tick_crumble(0.5)
  lu.assertFalse(r:present("Core"))
  lu.assertEquals(r:count_buildings(), 0)
end

function TestEntities.test_kill_skips_crumbling_and_returns_nil_when_absent()
  local r = entities.new()
  r:add_building("Relay", 1, 0)
  r:add_building("Relay", 2, 0)
  local first = r:kill("Relay")
  local second = r:kill("Relay")
  lu.assertNotEquals(first.id, second.id)
  lu.assertNil(r:kill("Relay"))
  lu.assertNil(r:kill("Turret"))
end

function TestEntities.test_deplete_sites_removes_first_n_sites_immediately()
  local r = entities.new()
  r:deplete_sites(5)
  lu.assertEquals(r:count_sites(), 22)
  lu.assertEquals(r:count_buildings(), 1)
  r:deplete_sites(100)
  lu.assertEquals(r:count_sites(), 0)
end
