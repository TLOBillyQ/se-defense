-- tools/acceptance/cli/mutator.lua — host wrapper for the acceptance4lua
-- gherkin-mutator command. Run from the repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
-- Generated specs and the runner worker must see Lua 5.4 and the tool tree.
local args = { table.unpack(arg) }
local has_steps = false
for _, a in ipairs(args) do if a == "--steps-module" then has_steps = true end end
if not has_steps then
  args[#args + 1] = "--steps-module"
  args[#args + 1] = "tools.acceptance.steps"
end
os.exit(require("acceptance4lua.cli.mutator").main(args))
