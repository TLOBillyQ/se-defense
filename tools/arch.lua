-- tools/arch.lua — host wrapper for the arch_view CLI (module dependency gate).
-- Usage from the repository root:
--   lua5.4 tools/arch.lua check
--   lua5.4 tools/arch.lua scan --out .arch_view/architecture.json
--   lua5.4 tools/arch.lua viewer --out-dir .arch_view/viewer
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.arch_bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end

-- cli.run returns true/false and never exits; swallowing that would turn a
-- failing gate silently green, so the host owns the exit code.
local cli = require("arch_view.cli")
local passed = cli.run(arg or {}, {
  command_name = "tools/arch.lua",
  default_config_path = "arch_view.config.json",
  default_project_root = ".",
  script_dir = bootstrap.tree .. "/share/lua/5.4",
})
os.exit(passed and 0 or 1)
