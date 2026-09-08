-- Unit tests for tools/deploy_plan.lua: the pure part of deploy — which subtrees
-- this repo owns (whitelist × directory listing) and whether the destination
-- really crosses the WSL→Windows seam. No filesystem, no subprocesses: the
-- listing is injected, so these run everywhere the mirror itself cannot.
local lu = require("luaunit")
local plan = require("tools.deploy_plan")

TestDeployPlan = {}

local function listing(byrealm)
  return function(realm) return byrealm[realm] or {} end
end

function TestDeployPlan:test_realms_are_the_official_workspace_roots()
  lu.assertEquals(plan.REALMS, { "client", "common", "server" })
end

function TestDeployPlan:test_targets_pair_repo_path_with_same_workspace_path()
  local targets = plan.targets("/ws", listing({
    server = { { name = "game", dir = true }, { name = "main.lua", dir = false } },
  }), { "server" })
  lu.assertEquals(#targets, 2)
  lu.assertEquals(targets[1], { rel = "server/game", dir = true,
    src = "server/game", dst = "/ws/server/game" })
  lu.assertEquals(targets[2], { rel = "server/main.lua", dir = false,
    src = "server/main.lua", dst = "/ws/server/main.lua" })
end

function TestDeployPlan:test_targets_follow_realm_order_then_listing_order()
  local targets = plan.targets("/ws", listing({
    client = { { name = "main.lua", dir = false } },
    common = { { name = "spoke", dir = true } },
    server = { { name = "net.lua", dir = false } },
  }))
  local rels = {}
  for _, t in ipairs(targets) do rels[#rels + 1] = t.rel end
  lu.assertEquals(rels, { "client/main.lua", "common/spoke", "server/net.lua" })
end

function TestDeployPlan:test_targets_of_empty_realm_contribute_nothing()
  lu.assertEquals(plan.targets("/ws", listing({}), { "server" }), {})
end

-- 盘符路径才值得 robocopy / editor-cli；其余一律本地 cp。
function TestDeployPlan:test_drive_letter_destination_crosses_the_seam()
  lu.assertIsTrue(plan.crosses_seam("C:\\Users\\x\\dev\\LuaSource"))
  lu.assertIsTrue(plan.crosses_seam("D:\\ws"))
end

function TestDeployPlan:test_unc_path_back_into_wsl_does_not_cross()
  lu.assertIsFalse(plan.crosses_seam("\\\\wsl.localhost\\Ubuntu\\home\\u\\repo\\tmp\\ws"))
end

function TestDeployPlan:test_no_wslpath_means_no_seam()
  lu.assertIsFalse(plan.crosses_seam(nil))
  lu.assertIsFalse(plan.crosses_seam(""))
end
