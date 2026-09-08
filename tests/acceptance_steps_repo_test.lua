-- Unit tests for the deploy-mirror step handlers in
-- tools/acceptance/steps_repo.lua. The feature passes space-separated path
-- lists (one deployment per scenario); these tests pin that list semantics
-- without running a real deployment.
local lu = require("luaunit")
local steps = require("tools.acceptance.steps_repo")

TestDeployMirrorSteps = {}

local function handler_for(fragment)
  for _, entry in ipairs(steps.patterns) do
    if entry[1]:find(fragment, 1, true) then return entry[2] end
  end
  error("步骤表里找不到包含 " .. fragment .. " 的模式")
end

local function write(path, body)
  local parent = path:match("^(.*)/[^/]+$")
  if parent then os.execute("mkdir -p '" .. parent .. "'") end
  local f = assert(io.open(path, "w"))
  f:write(body or "-- preset\n")
  f:close()
end

local function exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

function TestDeployMirrorSteps:setUp()
  self.ws = "tmp/steps-repo-unit-test"
  os.execute("rm -rf '" .. self.ws .. "'")
  os.execute("mkdir -p '" .. self.ws .. "'")
  self.world = { workspace = self.ws }
end

function TestDeployMirrorSteps:tearDown()
  os.execute("rm -rf '" .. self.ws .. "'")
end

function TestDeployMirrorSteps:test_preset_creates_every_path_in_list()
  local ok, err = handler_for("临时工作区预置文件")(self.world,
    "server/_trigger/GlobalVars.lua data/Prefab.lua eggy.json")
  lu.assertTrue(ok, err)
  lu.assertTrue(exists(self.ws .. "/server/_trigger/GlobalVars.lua"))
  lu.assertTrue(exists(self.ws .. "/data/Prefab.lua"))
  lu.assertTrue(exists(self.ws .. "/eggy.json"))
end

function TestDeployMirrorSteps:test_preset_ignores_extra_whitespace()
  local ok, err = handler_for("临时工作区预置文件")(self.world,
    "  server/main.lua\tclient/main.lua   eggy.json  ")
  lu.assertTrue(ok, err)
  lu.assertTrue(exists(self.ws .. "/server/main.lua"))
  lu.assertTrue(exists(self.ws .. "/client/main.lua"))
  lu.assertTrue(exists(self.ws .. "/eggy.json"))
end

function TestDeployMirrorSteps:test_exists_requires_every_path_in_list()
  write(self.ws .. "/server/main.lua")
  write(self.ws .. "/client/main.lua")
  local ok, err = handler_for("临时工作区存在文件")(self.world,
    "server/main.lua client/main.lua")
  lu.assertTrue(ok, err)
end

function TestDeployMirrorSteps:test_exists_reports_missing_path()
  write(self.ws .. "/server/main.lua")
  local ok, err = handler_for("临时工作区存在文件")(self.world,
    "server/main.lua client/main.lua")
  lu.assertNil(ok)
  lu.assertStrContains(err, "client/main.lua")
end

function TestDeployMirrorSteps:test_exists_accepts_single_path()
  write(self.ws .. "/eggy.json")
  local ok, err = handler_for("临时工作区存在文件")(self.world, "eggy.json")
  lu.assertTrue(ok, err)
end

function TestDeployMirrorSteps:test_exists_accepts_empty_file()
  write(self.ws .. "/eggy.json", "")
  local ok, err = handler_for("临时工作区存在文件")(self.world, "eggy.json")
  lu.assertTrue(ok, err)
end

function TestDeployMirrorSteps:test_handler_requires_workspace()
  self.world.workspace = nil
  local ok, err = handler_for("临时工作区存在文件")(self.world, "eggy.json")
  lu.assertNil(ok)
  lu.assertStrContains(err, "尚未创建临时工作区")
end
