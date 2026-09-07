-- 项目性质测试统一运行器。
--
-- 用法（仓库根）：lua5.4 tests/property/run.lua
--
-- 与 tests/run.lua 分离：这里只发现 tests/**/*_property.lua（含内联 spoke 运行时
-- 与对局领域），是性质测试的独立显式命令。种子与用例数经
-- SPOKE_PROPERTY_SEED / SPOKE_PROPERTY_CASES 调优（见属性框架 doc）。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local files = {}
local pipe = io.popen("find tests -name '*_property.lua' 2>/dev/null")
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("no property files found (tests/**/*_property.lua)\n")
  os.exit(1)
end

-- 性质文件在 require 期通过 property.forall 注册；统一 run_all 一次执行。
local property = require("tests.spoke.property.support.property")
for _, file in ipairs(files) do
  local mod = file:gsub("%.lua$", ""):gsub("/", ".")
  require(mod)
end

os.exit(property.run_all() and 0 or 1)
