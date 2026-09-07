-- Unit tests for the arch-view dependency predicate group in
-- tools/acceptance/repo_checks.lua. These are pure over synthetic graph /
-- config models; they never scan the repository or boot a game.
local lu = require("luaunit")
local repo = require("tools.acceptance.repo_checks")

local function module_with_layer(layer)
  return { component_layer = layer }
end

TestArchEdgeExists = {}

function TestArchEdgeExists.test_present_edge()
  local graph = { edges = {
    { from = "server.game.core", to = "server.game.power_node" },
    { from = "server.game.radar", to = "server.game.turret" },
  } }
  lu.assertTrue(repo.arch_edge_exists(graph, "server.game.core", "server.game.power_node"))
  lu.assertTrue(repo.arch_edge_exists(graph, "server.game.radar", "server.game.turret"))
end

function TestArchEdgeExists.test_absent_edge()
  local graph = { edges = {
    { from = "server.game.core", to = "server.game.power_node" },
  } }
  lu.assertFalse(repo.arch_edge_exists(graph, "server.game.power_node", "server.game.core"))
  lu.assertFalse(repo.arch_edge_exists(graph, "server.game.core", "server.game.turret"))
  lu.assertFalse(repo.arch_edge_exists({ edges = {} }, "a", "b"))
end

TestArchEdgeForbidden = {}

function TestArchEdgeForbidden.test_forbidden_rule_same_layer()
  local config = { forbidden_dependency_rules = {
    { from = { "^server%.game%.power_node$" }, to = { "^server%.game%.core$" } },
  } }
  local modules = {
    ["server.game.power_node"] = module_with_layer(3),
    ["server.game.core"] = module_with_layer(3),
  }
  lu.assertTrue(repo.arch_edge_forbidden(config, modules, "server.game.power_node", "server.game.core"))
end

function TestArchEdgeForbidden.test_rule_pattern_must_match_both_ends()
  local config = { forbidden_dependency_rules = {
    { from = { "^server%.game%.power_node$" }, to = { "^server%.game%.core$" } },
  } }
  local modules = {
    ["server.game.power_node"] = module_with_layer(3),
    ["server.game.turret"] = module_with_layer(3),
  }
  -- The rule forbids power_node -> core; power_node -> turret is not covered.
  lu.assertFalse(repo.arch_edge_forbidden(config, modules, "server.game.power_node", "server.game.turret"))
end

function TestArchEdgeForbidden.test_layer_upward_adapter_to_game()
  local config = { forbidden_dependency_rules = {} }
  local modules = {
    ["server.adapter.host"] = module_with_layer(4),
    ["server.game.core"] = module_with_layer(3),
  }
  lu.assertTrue(repo.arch_edge_forbidden(config, modules, "server.adapter.host", "server.game.core"))
end

function TestArchEdgeForbidden.test_allowed_downward_game_to_adapter()
  local config = { forbidden_dependency_rules = {} }
  local modules = {
    ["server.game.core"] = module_with_layer(3),
    ["server.adapter.host"] = module_with_layer(4),
  }
  lu.assertFalse(repo.arch_edge_forbidden(config, modules, "server.game.core", "server.adapter.host"))
end

function TestArchEdgeForbidden.test_same_layer_unlisted_is_allowed()
  local config = { forbidden_dependency_rules = {} }
  local modules = {
    ["a"] = module_with_layer(3),
    ["b"] = module_with_layer(3),
  }
  lu.assertFalse(repo.arch_edge_forbidden(config, modules, "a", "b"))
end

function TestArchEdgeForbidden.test_substrate_direction()
  local config = { forbidden_dependency_rules = {} }
  local modules = {
    ["server.game.x"] = module_with_layer(3),
    ["common.spoke"] = { component_substrate = true },
  }
  -- Anyone -> substrate is legal; substrate -> any layered component is forbidden.
  lu.assertFalse(repo.arch_edge_forbidden(config, modules, "server.game.x", "common.spoke"))
  lu.assertTrue(repo.arch_edge_forbidden(config, modules, "common.spoke", "server.game.x"))
end

function TestArchEdgeForbidden.test_no_declared_layer_is_not_judged()
  local config = { forbidden_dependency_rules = {} }
  local modules = { a = { component = "unclassified" }, b = {} }
  lu.assertFalse(repo.arch_edge_forbidden(config, modules, "a", "b"))
end

TestArchComponentLayer = {}

function TestArchComponentLayer.test_layered_component()
  local config = { component_rules = {
    { name = "client", match = { "^client%..+" }, component = "client", layer = 1 },
    { name = "game", match = { "^server%.game%..+" }, component = "game", layer = 3 },
  } }
  lu.assertEquals(repo.arch_component_layer(config, "client"), 1)
  lu.assertEquals(repo.arch_component_layer(config, "game"), 3)
end

function TestArchComponentLayer.test_substrate_component()
  local config = { component_rules = {
    { name = "spoke", match = { "^common%.spoke" }, component = "spoke", substrate = true },
  } }
  lu.assertEquals(repo.arch_component_layer(config, "spoke"), "基座")
end

function TestArchComponentLayer.test_undeclared_component()
  lu.assertNil(repo.arch_component_layer({ component_rules = {} }, "nope"))
end

TestArchUnwaivedCycleCount = {}

function TestArchUnwaivedCycleCount.test_counts_only_unwaived()
  local check = { projection_cycles = {
    { cycle = "a->b->a", waived = true },
    { cycle = "c->d->c", waived = false },
    { cycle = "e->f->e" },
  } }
  lu.assertEquals(repo.arch_unwaived_cycle_count(check), 2)
end

function TestArchUnwaivedCycleCount.test_empty_check()
  lu.assertEquals(repo.arch_unwaived_cycle_count({ projection_cycles = {} }), 0)
  lu.assertEquals(repo.arch_unwaived_cycle_count({}), 0)
end
