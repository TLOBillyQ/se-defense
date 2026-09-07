-- Unit tests for tools/deploy_plan.lua: the pure mirror plan behind
-- tools/deploy.lua. The repo root is aligned with the SE workspace root, so the
-- plan mirrors <端>/<child> for the whitelisted realms client/common/server only
-- (spoke lives at common/spoke, no special case); nothing else in the workspace is touched.
local lu = require("luaunit")
local plan = require("tools.deploy_plan")

TestDeployPlan = {}

local function entry(name, dir)
  return { name = name, dir = dir == true }
end

-- Fake repo root: the three realms plus non-deploy content that must be ignored.
local function fake_entries()
  local tree = {
    ["common"] = { entry("spoke", true) },
    ["client"] = { entry("main.lua"), entry("eui_render.lua") },
    ["server"] = { entry("main.lua"), entry("adapter", true), entry("game", true) },
    ["data"] = { entry("Prefab.lua") },
    ["tools"] = { entry("deploy.lua") },
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

function TestDeployPlan.test_whitelist_is_the_official_workspace_roots()
  lu.assertEquals(plan.REALMS, { "client", "common", "server" })
end

function TestDeployPlan.test_mirrors_each_realm_child_to_same_workspace_path()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertEquals(m["server/main.lua"], "server/main.lua")
  lu.assertEquals(m["server/game"], "server/game")
  lu.assertEquals(m["server/adapter"], "server/adapter")
  lu.assertEquals(m["client/main.lua"], "client/main.lua")
  lu.assertEquals(m["client/eui_render.lua"], "client/eui_render.lua")
end

function TestDeployPlan.test_ignores_repo_root_content_outside_whitelist()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertNil(m["data/Prefab.lua"])
  lu.assertNil(m["tools/deploy.lua"])
  for _, dst in pairs(m) do
    lu.assertNotNil(dst:match("^client/") or dst:match("^common/") or dst:match("^server/"))
  end
end

function TestDeployPlan.test_spoke_mirrored_like_any_realm_child()
  local m = mirrors(plan.build(fake_entries()))
  lu.assertEquals(m["common/spoke"], "common/spoke")
  lu.assertNil(m["vendor/spoke"])
end

function TestDeployPlan.test_build_removes_only_workspace_junk()
  lu.assertEquals(plan.JUNK, { ".gm", "server.TableMgr", "unit_scripts" })
  lu.assertEquals(removals(plan.build(fake_entries())), plan.JUNK)
end

function TestDeployPlan.test_missing_realms_still_remove_junk()
  local ops = plan.build(function() return {} end)
  lu.assertEquals(mirrors(ops), {})
  lu.assertEquals(removals(ops), plan.JUNK)
end

function TestDeployPlan.test_clean_removes_every_build_target_and_nothing_else()
  local build_dsts = {}
  for _, op in ipairs(plan.build(fake_entries())) do build_dsts[#build_dsts + 1] = op.dst end
  local clean_ops = plan.clean(fake_entries())
  lu.assertEquals(#clean_ops, #build_dsts)
  for i, op in ipairs(clean_ops) do
    lu.assertEquals(op.kind, "remove")
    lu.assertEquals(op.dst, build_dsts[i])
  end
end
