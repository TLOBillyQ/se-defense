-- Unit tests for tools/acceptance/repo_checks.lua, the pure predicates that
-- back the spoke-primitives engineering feature. These never boot a game;
-- they only inspect source text.
local lu = require("luaunit")
local repo = require("tools.acceptance.repo_checks")

TestReferencesCommonSpoke = {}

function TestReferencesCommonSpoke.test_facade_require()
  lu.assertTrue(repo.references_common_spoke('local spoke = require("common.spoke")'))
end

function TestReferencesCommonSpoke.test_submodule_require()
  lu.assertTrue(repo.references_common_spoke('local Epoch = require("common.spoke.runtime.epoch")'))
  lu.assertTrue(repo.references_common_spoke("local State = require('common.spoke.reactive.state')"))
end

function TestReferencesCommonSpoke.test_plain_require_is_not_spoke()
  lu.assertFalse(repo.references_common_spoke('local World = require("server.game.world")'))
end

function TestReferencesCommonSpoke.test_no_require()
  lu.assertFalse(repo.references_common_spoke("local x = 1"))
end

TestUsesSpokePrimitive = {}

function TestUsesSpokePrimitive.test_facade_access()
  lu.assertTrue(repo.uses_spoke_primitive("local State = spoke.State", "State"))
  lu.assertTrue(repo.uses_spoke_primitive("s:call(spoke.Memo.new('k', fn))", "Memo"))
end

function TestUsesSpokePrimitive.test_facade_access_word_boundary()
  lu.assertFalse(repo.uses_spoke_primitive("local x = spoke.StateMachine", "State"))
end

function TestUsesSpokePrimitive.test_facade_access_member()
  lu.assertTrue(repo.uses_spoke_primitive("local s = spoke.State.new(...)", "State"))
end

function TestUsesSpokePrimitive.test_subtable_access()
  lu.assertTrue(repo.uses_spoke_primitive("local a = spoke.reactive.state", "State"))
  lu.assertTrue(repo.uses_spoke_primitive("local a = spoke.runtime.epoch", "Epoch"))
end

function TestUsesSpokePrimitive.test_subtable_word_boundary()
  lu.assertFalse(repo.uses_spoke_primitive("local a = spoke.reactive.state_machine", "State"))
end

function TestUsesSpokePrimitive.test_direct_require()
  lu.assertTrue(repo.uses_spoke_primitive('local Trigger = require("common.spoke.reactive.trigger")', "Trigger"))
  lu.assertTrue(repo.uses_spoke_primitive('local Dock = require("common.spoke.runtime.dock")', "Dock"))
end

function TestUsesSpokePrimitive.test_direct_require_word_boundary()
  -- effect_builder ends with an underscore after "effect"; must not count as Effect.
  lu.assertFalse(repo.uses_spoke_primitive(
    'local EffectBuilder = require("common.spoke.reactive.effect_builder")', "Effect"))
end

function TestUsesSpokePrimitive.test_scoped_dock_compose_counts_as_dock()
  -- game_root_full composes a Dock through the EffectBuilder scope (ss:dock).
  lu.assertTrue(repo.uses_spoke_primitive(
    "local enemies_dock = ss:dock(\"enemies\")", "Dock"))
end

function TestUsesSpokePrimitive.test_scoped_dock_is_not_other_primitive()
  lu.assertFalse(repo.uses_spoke_primitive(
    "local enemies_dock = ss:dock(\"enemies\")", "State"))
end

TestNonServerRequires = {}

function TestNonServerRequires.test_only_server_prefix_is_ok()
  local body = 'local A = require("server.game.relay") local B = require "server.adapter.host"'
  lu.assertEquals(#repo.non_server_requires(body), 0)
end

function TestNonServerRequires.test_reports_non_server_prefix()
  local body = 'local A = require("server.game.relay") local B = require("client.eui_render")'
  lu.assertEquals(repo.non_server_requires(body), { "client.eui_render" })
end

function TestNonServerRequires.test_reports_spoke_require()
  local body = 'local S = require("common.spoke")'
  lu.assertEquals(repo.non_server_requires(body), { "common.spoke" })
end

TestNonSpokeModules = {}

function TestNonSpokeModules.test_filters_specs_by_reference()
  local specs = {
    { name = "uses_spoke", body = 'require("common.spoke")' },
    { name = "plain", body = "local x = 1" },
    { name = "server_only", body = 'require("server.game.world")' },
  }
  lu.assertEquals(repo.non_spoke_modules(specs), { "plain", "server_only" })
end
