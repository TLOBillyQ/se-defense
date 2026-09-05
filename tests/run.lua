-- Test runner for project unit tests (se-defense repo, not vendor/).
-- Run from the repo root:
--   lua5.4 tests/run.lua
--
-- Discovers tests/**/*_test.lua, sorted for deterministic order. LuaUnit is
-- the vendored copy under vendor/tests/vendor (same as vendor/tests/run.lua).

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./src/?.lua",
  "./src/?/init.lua",
  "./vendor/tests/vendor/?.lua",
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
