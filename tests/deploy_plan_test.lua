-- Unit tests for tools/deploy_plan.lua: the pure mirror plan behind
-- tools/deploy.lua. The plan maps src/<端>/<child> onto the workspace root
-- (spoke lives at src/common/spoke, no special case) and removes legacy trees.
local lu = require("luaunit")
local plan = require("tools.deploy_plan")

TestDeployPlan = {}

local function entry(name, dir)
  return { name = name, dir = dir == true }
end

-- Fake directory tree shaped like the post-restructure src/.
local function fake_entries()
  local tree = {
    ["src"] = { entry("client", true), entry("common", true), entry("server", true), entry("notes.txt") },
    ["src/common"] = { entry("spoke", true) },
    ["src/client"] = { entry("main.lua"), entry("eui_render.lua") },
    ["src/server"] = { entry("main.lua"), entry("adapter", true), entry("game", true) },
  }
  return function(dir) return tree[dir] or {} end
end

local function mirrors(ops)
  local out = {}
  for _, op in ipairs(ops) do
    if op.kind == "mirror" then out[op.src] = op.dst end
  end
  return out
end

local function removals(ops)
  local out = {}
  for _, op in ipairs(ops) do
    if op.kind == "remove" then out[#out + 1] = op.dst end
  end
  return out
end

function TestDeployPlan.test_mirrors_each_realm_child_to_workspace_root()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertEquals(m["src/server/main.lua"], "server/main.lua")
  lu.assertEquals(m["src/server/game"], "server/game")
  lu.assertEquals(m["src/server/adapter"], "server/adapter")
  lu.assertEquals(m["src/client/main.lua"], "client/main.lua")
  lu.assertEquals(m["src/client/eui_render.lua"], "client/eui_render.lua")
end

function TestDeployPlan.test_skips_plain_files_at_src_top_level()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertNil(m["src/notes.txt"])
end

function TestDeployPlan.test_spoke_mirrored_like_any_realm_child()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertEquals(m["src/common/spoke"], "common/spoke")
  lu.assertNil(m["vendor/spoke"])
end

function TestDeployPlan.test_removes_legacy_layout_trees()
  local r = removals(plan.build(fake_entries()))
  lu.assertEquals(r, { "src", "examples", "vendor/spoke" })
end

function TestDeployPlan.test_empty_src_still_cleans_legacy_trees()
  local ops = plan.build(function() return {} end)
  lu.assertEquals(removals(ops), { "src", "examples", "vendor/spoke" })
  lu.assertEquals(mirrors(ops), {})
end
