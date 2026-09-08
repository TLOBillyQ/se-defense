-- Unit tests for tools/acceptance/arch_checks.lua. These are pure over
-- synthetic graph / config models; they never scan the repository or boot a
-- game. Whether the gate rejects a direction is not asserted here — that is
-- arch_view's call, covered in acceptance_arch_probe_test.lua.
local lu = require("luaunit")
local archc = require("tools.acceptance.arch_checks")

TestArchEdgeExists = {}

function TestArchEdgeExists.test_present_edge()
  local graph = { edges = {
    { from = "server.game.core", to = "server.game.power_node" },
    { from = "server.game.radar", to = "server.game.turret" },
  } }
  lu.assertTrue(archc.arch_edge_exists(graph, "server.game.core", "server.game.power_node"))
  lu.assertTrue(archc.arch_edge_exists(graph, "server.game.radar", "server.game.turret"))
end

function TestArchEdgeExists.test_absent_edge()
  local graph = { edges = {
    { from = "server.game.core", to = "server.game.power_node" },
  } }
  lu.assertFalse(archc.arch_edge_exists(graph, "server.game.power_node", "server.game.core"))
  lu.assertFalse(archc.arch_edge_exists(graph, "server.game.core", "server.game.turret"))
  lu.assertFalse(archc.arch_edge_exists({ edges = {} }, "a", "b"))
end

TestArchComponentLayer = {}

function TestArchComponentLayer.test_layered_component()
  local config = { component_rules = {
    { name = "client", match = { "^client%..+" }, component = "client", layer = 1 },
    { name = "game", match = { "^server%.game%..+" }, component = "game", layer = 3 },
  } }
  lu.assertEquals(archc.arch_component_layer(config, "client"), 1)
  lu.assertEquals(archc.arch_component_layer(config, "game"), 3)
end

function TestArchComponentLayer.test_substrate_component()
  local config = { component_rules = {
    { name = "spoke", match = { "^common%.spoke" }, component = "spoke", substrate = true },
  } }
  lu.assertEquals(archc.arch_component_layer(config, "spoke"), "基座")
end

function TestArchComponentLayer.test_undeclared_component()
  lu.assertNil(archc.arch_component_layer({ component_rules = {} }, "nope"))
end

TestArchUnwaivedCycleCount = {}

function TestArchUnwaivedCycleCount.test_counts_only_unwaived()
  local check = { projection_cycles = {
    { cycle = "a->b->a", waived = true },
    { cycle = "c->d->c", waived = false },
    { cycle = "e->f->e" },
  } }
  lu.assertEquals(archc.arch_unwaived_cycle_count(check), 2)
end

function TestArchUnwaivedCycleCount.test_empty_check()
  lu.assertEquals(archc.arch_unwaived_cycle_count({ projection_cycles = {} }), 0)
  lu.assertEquals(archc.arch_unwaived_cycle_count({}), 0)
end
