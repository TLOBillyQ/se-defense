-- Unit tests for tools/sync.lua: workspace → repo copy of the editor-owned
-- files (eggy.json, EggyAPI.lua) and the data/ directory mirror, CRLF
-- normalised to LF, all-or-nothing when a required source is missing.
local lu = require("luaunit")
local sync = require("tools.sync")

TestSync = {}

local function tmpdir()
  local path = os.tmpname()
  os.remove(path)
  assert(os.execute("mkdir -p '" .. path .. "'"))
  return path
end

local function write(path, data)
  local parent = path:match("^(.*)/[^/]+$")
  os.execute("mkdir -p '" .. parent .. "'")
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

local function seed_minimal(ws)
  write(ws .. "/eggy.json", '{"isSEMap": true}\n')
  write(ws .. "/EggyAPI.lua", "---@meta EggyAPI\r\nlocal x = 1\r\n")
  write(ws .. "/data/Prefab.lua", "return {}\r\n")
end

function TestSync:setUp()
  self.ws = tmpdir()
  self.repo = tmpdir()
end

function TestSync:tearDown()
  os.execute("rm -rf '" .. self.ws .. "' '" .. self.repo .. "'")
end

function TestSync:test_normalize_lf_only_touches_crlf()
  lu.assertEquals(sync.normalize_lf("a\r\nb\nc\r\n"), "a\nb\nc\n")
  lu.assertEquals(sync.normalize_lf("no newline"), "no newline")
end

function TestSync:test_copies_files_and_data_dir_with_lf()
  seed_minimal(self.ws)
  write(self.ws .. "/data/sub/UINodes.lua", "return {\r\n}\r\n")

  local report, err = sync.sync(self.ws, self.repo)
  lu.assertNil(err)
  lu.assertEquals(read(self.repo .. "/eggy.json"), '{"isSEMap": true}\n')
  lu.assertEquals(read(self.repo .. "/EggyAPI.lua"), "---@meta EggyAPI\nlocal x = 1\n")
  lu.assertEquals(read(self.repo .. "/data/Prefab.lua"), "return {}\n")
  lu.assertEquals(read(self.repo .. "/data/sub/UINodes.lua"), "return {\n}\n")
  lu.assertEquals(#report, 4)
  for _, r in ipairs(report) do lu.assertTrue(r.changed) end
end

function TestSync:test_data_mirror_removes_stale_repo_files()
  seed_minimal(self.ws)
  write(self.repo .. "/data/Old.lua", "gone\n")

  local report = assert(sync.sync(self.ws, self.repo))
  lu.assertNil(read(self.repo .. "/data/Old.lua"))
  lu.assertEquals(report[#report].dst, "data/Old.lua")
  lu.assertTrue(report[#report].removed)
end

function TestSync:test_reports_unchanged_when_content_matches()
  seed_minimal(self.ws)
  write(self.repo .. "/eggy.json", '{"isSEMap": true}\n')
  write(self.repo .. "/EggyAPI.lua", "---@meta EggyAPI\nlocal x = 1\n")
  write(self.repo .. "/data/Prefab.lua", "return {}\n")

  local report = assert(sync.sync(self.ws, self.repo))
  for _, r in ipairs(report) do lu.assertFalse(r.changed) end
end

function TestSync:test_missing_source_writes_nothing()
  write(self.ws .. "/eggy.json", "{}\n")
  write(self.ws .. "/data/Prefab.lua", "x\n")
  -- EggyAPI.lua absent on purpose

  local report, err = sync.sync(self.ws, self.repo)
  lu.assertNil(report)
  lu.assertStrContains(err, "EggyAPI.lua")
  lu.assertNil(read(self.repo .. "/eggy.json"))
  lu.assertNil(read(self.repo .. "/data/Prefab.lua"))
end

function TestSync:test_missing_data_dir_fails()
  write(self.ws .. "/eggy.json", "{}\n")
  write(self.ws .. "/EggyAPI.lua", "x\n")

  local report, err = sync.sync(self.ws, self.repo)
  lu.assertNil(report)
  lu.assertStrContains(err, "data")
end

function TestSync:test_main_rejects_arguments()
  lu.assertEquals(sync.main({ "extra" }), 2)
end
