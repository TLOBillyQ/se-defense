-- tools/acceptance/cli/ir_dry.lua — host wrapper for the acceptance4lua
-- gherkin-ir-dry-checker command. Run from the repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
os.exit(require("acceptance4lua.cli.ir_dry").main(arg))
