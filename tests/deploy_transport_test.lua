-- Regression guard for the deploy speed fix (tasks/优化deploy feature.md):
-- a workspace on the Linux side must be mirrored with local cp and must skip
-- the editor-cli finalization. Both of those are cmd.exe round trips, and on
-- the WSL dev box each one is a cross-system call the acceptance run pays per
-- scenario. Runs the real CLI against a throwaway workspace: on WSL the repo
-- (and therefore ./tmp) lives on the Linux side, so this asserts the operator's
-- actual case, not a macOS-only accident.
local lu = require("luaunit")

TestDeployTransport = {}

local function lua_bin()
  if arg then
    for i = -1, -4, -1 do
      local candidate = arg[i]
      if type(candidate) == "string" and not candidate:match("^%-") and candidate:match("lua") then
        return candidate
      end
    end
  end
  return "lua5.4"
end

function TestDeployTransport:setUp()
  self.ws = "tmp/deploy-transport-test"
  os.execute("rm -rf '" .. self.ws .. "' && mkdir -p '" .. self.ws .. "'")
  local h = io.popen("EGGY_WORKSPACE='" .. self.ws .. "' '" .. lua_bin()
    .. "' tools/deploy.lua 2>&1")
  self.out = h:read("a") or ""
  h:close()
end

function TestDeployTransport:tearDown()
  os.execute("rm -rf '" .. self.ws .. "'")
end

function TestDeployTransport:test_mirror_reports_success()
  lu.assertStrContains(self.out, "deploy ok")
end

-- robocopy 到 Linux 侧目的地要 Windows 反过来走 9P 回读，比本地 cp 更慢。
function TestDeployTransport:test_no_target_is_mirrored_via_robocopy()
  lu.assertNotStrContains(self.out, "robocopy")
end

function TestDeployTransport:test_every_target_is_copied_locally()
  local targets = 0
  for line in self.out:gmatch("[^\n]+") do
    if line:match("^%S+/%S+: %d+ 文件 %(") then
      targets = targets + 1
      lu.assertStrContains(line, "(cp)")
    end
  end
  lu.assertTrue(targets > 0, "部署没有报告任何子树")
end

function TestDeployTransport:test_editor_finalization_is_skipped()
  lu.assertStrContains(self.out, "跳过编辑器收尾")
  lu.assertNotStrContains(self.out, "validate")
end

-- 部署树确实落到工作区（镜像本身没被这条捷径跳过）。
function TestDeployTransport:test_mirror_still_lands_the_deploy_tree()
  for _, rel in ipairs({ "server/main.lua", "client/main.lua", "common/spoke/init.lua" }) do
    local f = io.open(self.ws .. "/" .. rel, "r")
    lu.assertNotNil(f, rel .. " 未落到工作区")
    f:close()
  end
end
