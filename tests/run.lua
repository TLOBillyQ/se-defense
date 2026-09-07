-- Test runner for all unit tests: project tests plus the inlined spoke runtime
-- suite under tests/spoke/ (upstream sync: see docs/spoke-upstream.md).
-- Run from the repo root:
--   lua5.4 tests/run.lua
--
-- Discovers tests/**/*_test.lua, sorted for deterministic order. Property tests
-- have their own runner: tests/spoke/property/run.lua. LuaUnit lives
-- at tests/lib/luaunit.lua.

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./src/?.lua",
  "./src/?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local files = {}
local pipe = io.popen("find tests -name '*_test.lua' 2>/dev/null")
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("no test files found (tests/**/*_test.lua)\n")
  os.exit(1)
end

for _, file in ipairs(files) do
  local mod = file:gsub("%.lua$", ""):gsub("/", ".")
  require(mod)
end

local lu = require("luaunit")
os.exit(lu.LuaUnit.run())
