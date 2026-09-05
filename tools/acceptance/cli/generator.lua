-- tools/acceptance/cli/generator.lua — host wrapper for the acceptance4lua
-- acceptance-entrypoint-generator command. Run from the repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
local args = { table.unpack(arg) }
local has_steps = false
for _, a in ipairs(args) do if a == "--steps-module" then has_steps = true end end
if not has_steps then
  table.insert(args, 1, "tools.acceptance.steps")
  table.insert(args, 1, "--steps-module")
end
os.exit(require("acceptance4lua.cli.generator").main(args))
