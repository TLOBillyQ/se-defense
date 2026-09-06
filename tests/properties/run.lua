-- Property-test runner for se-defense (separate from unit/acceptance suites).
-- Run from the repo root:
--   lua5.4 tests/properties/run.lua
--
-- Discovers tests/properties/**/*_prop.lua, sorted for deterministic order.
-- Unit tests (tests/run.lua) glob *_test.lua and never pick these up; this
-- runner is the explicit property-test command of the verification surface.

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./src/?.lua",
  "./src/?/init.lua",
  package.path,
}, ";")

local files = {}
local pipe = io.popen("find tests/properties -name '*_prop.lua' 2>/dev/null")
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("no property files found (tests/properties/**/*_prop.lua)\n")
  os.exit(1)
end

for _, file in ipairs(files) do
  local mod = file:gsub("%.lua$", ""):gsub("/", ".")
  require(mod)
end

require("tests.properties.harness").exit()
