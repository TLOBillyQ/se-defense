-- Unit tests for tools/acceptance/arch_probe.lua: the gate query behind
-- features/engineering/dependencies.feature scenario 3.
--
-- These deliberately exercise the REAL arch_view gate under the repository's
-- real arch_view.config.json, because the point of the module is that this
-- repository does not restate arch_view's rules. They run against a throwaway
-- two-module tree, not the repository source, so they stay fast.
local lu = require("luaunit")
local probe = require("tools.acceptance.arch_probe")

TestArchProbeForbidden = {}

-- A same-layer pair named by a forbidden_dependency_rules entry.
function TestArchProbeForbidden.test_forbidden_rule_same_layer()
  local rejected, kind = probe.rejects_edge("server.game.power_node", "server.game.core")
  lu.assertTrue(rejected)
  lu.assertEquals(kind, "forbidden_dependency")
end

-- Same layer, not named by any rule: the gate allows it.
function TestArchProbeForbidden.test_same_layer_unlisted_is_allowed()
  lu.assertFalse(probe.rejects_edge("server.game.power_node", "server.game.repair"))
end

-- adapter (L4) -> game (L3) is the upward edge the layer gate exists to stop.
function TestArchProbeForbidden.test_layer_upward_adapter_to_game()
  local rejected, kind = probe.rejects_edge("server.adapter.host", "server.game.core")
  lu.assertTrue(rejected)
  lu.assertEquals(kind, "layer_violation")
end

-- The same pair the other way round is the intended direction.
function TestArchProbeForbidden.test_allowed_downward_game_to_adapter()
  lu.assertFalse(probe.rejects_edge("server.game.core", "server.adapter.host"))
end

-- game (L3) may not reach up into server_support (L2) or client (L1).
function TestArchProbeForbidden.test_game_may_not_reach_support_or_client()
  lu.assertTrue(probe.rejects_edge("server.game.core", "server.gm"))
  lu.assertTrue(probe.rejects_edge("server.game.core", "client.eui_render"))
end

TestArchProbeSubstrate = {}

-- Anyone may depend on the spoke substrate; the substrate may not depend back.
function TestArchProbeSubstrate.test_substrate_direction()
  lu.assertFalse(probe.rejects_edge("server.game.core", "common.spoke.reactive.state"))
  lu.assertTrue(probe.rejects_edge("common.spoke.reactive.state", "server.game.core"))
end

TestArchProbeHygiene = {}

-- The probe must leave no tree behind, so acceptance runs stay repeatable.
function TestArchProbeHygiene.test_probe_tree_is_cleaned_up()
  probe.rejects_edge("server.game.power_node", "server.game.core")
  local ok, _, code = os.execute("test -d '" .. probe.PROBE_ROOT .. "'")
  lu.assertFalse(ok ~= nil and code == 0)
end

-- A malformed id must not be able to write outside the probe root.
function TestArchProbeHygiene.test_rejects_path_traversal_in_module_id()
  lu.assertErrorMsgContains("非法模块名", probe.rejects_edge, "../../etc/x", "server.game.core")
  lu.assertErrorMsgContains("非法模块名", probe.rejects_edge, "server.game.core", "a/b")
end
