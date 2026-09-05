-- Test runner for the inlined spoke runtime. Run from the se-defense repo root:
--   lua vendor/tests/run.lua
--
-- package.path: library modules resolve repo-root-relative, e.g.
--   require("vendor.spoke.runtime.epoch") -> ./vendor/spoke/runtime/epoch.lua
-- LuaUnit is vendored under vendor/tests/vendor so there are no env dependencies.
-- (The 蛋仔 host sandbox has no package library; there the runtime is physically
-- deployed at vendor/spoke/ under the script root, see tools/deploy.lua.)

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./vendor/tests/vendor/?.lua",
  package.path,
}, ";")

-- Discover vendor/tests/**/*_test.lua (tests mirror the source tree), sorted
-- for deterministic order. Property tests have their own runner: property/run.lua.
local files = {}
local pipe = io.popen("find vendor/tests -name '*_test.lua' 2>/dev/null")
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("no test files found (vendor/tests/**/*_test.lua)\n")
  os.exit(1)
end

-- Each test file defines global Test* tables and returns nothing; the suite runs once here.
for _, file in ipairs(files) do
  local mod = file:gsub("%.lua$", ""):gsub("/", ".")
  require(mod)
end

local lu = require("luaunit")
os.exit(lu.LuaUnit.run())
