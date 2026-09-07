-- Property-test runner for the inlined spoke runtime.
-- Usage (repo root): lua5.4 tests/spoke/property/run.lua
--
-- Deliberately separate from tests/run.lua: properties are excluded from the
-- normal suite by name, so this runner discovers tests/spoke/property/**/*_property.lua
-- instead of tests/**/*_test.lua. The seed is printed by the harness before
-- any case runs; SPOKE_PROPERTY_SEED / SPOKE_PROPERTY_CASES tune it.

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local files = {}
local pipe = io.popen("find tests/spoke/property -name '*_property.lua' 2>/dev/null")
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("no property files found (tests/spoke/property/**/*_property.lua)\n")
  os.exit(1)
end

-- Property files register their properties by calling property.forall at
-- load time; the harness runs them once here.
local property = require("tests.spoke.property.support.property")
for _, file in ipairs(files) do
  local mod = file:gsub("%.lua$", ""):gsub("/", ".")
  require(mod)
end

os.exit(property.run_all() and 0 or 1)
