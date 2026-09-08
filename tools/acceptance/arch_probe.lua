-- tools/acceptance/arch_probe.lua — ask the real arch_view gate whether one
-- dependency direction is rejected (features/engineering/dependencies.feature
-- scenario 3, "架构门禁禁止模块 A 依赖模块 B").
--
-- The gate's rule engine — forbidden_dependency_rules matching plus the layer
-- ordering — belongs to arch_view. Re-deriving it here would be a copy of
-- somebody else's decision procedure that can drift from the tool `tools/arch
-- check` actually runs, and the drift would be invisible: these edges do not
-- exist in the real tree, so the real gate never judges them. Instead we hand
-- arch_view a throwaway two-module tree containing exactly the edge in
-- question, under the repository's real arch_view.config.json, and report the
-- verdict it gives.
--
-- This module owns the probe-tree IO; the pure model predicates live in
-- arch_checks.lua.
local M = {}

-- Probe trees are rebuilt per query under ./tmp (worktree scratch, per the
-- repository's temporary-file convention).
M.PROBE_ROOT = "tmp/arch-probe"

local function shell_quote(path)
  return "'" .. path .. "'"
end

-- "server.game.core" -> "<root>/server/game/core.lua". Ids are rejected unless
-- they are dot-separated identifiers: the result is used to create files and
-- sits next to an `rm -rf`, so a "../" smuggled in from a feature table must
-- not be able to reach outside PROBE_ROOT.
local function module_file(root, module_id)
  -- Lua patterns have no grouped quantifier, so spell the shape out: only word
  -- characters and dots, no empty segment (which is what "../" would need).
  local ok = type(module_id) == "string"
    and module_id ~= ""
    and not module_id:find("[^%w_%.]")
    and not module_id:find("%.%.")
    and module_id:sub(1, 1) ~= "."
    and module_id:sub(-1) ~= "."
  assert(ok, "非法模块名: " .. tostring(module_id))
  return root .. "/" .. module_id:gsub("%.", "/") .. ".lua"
end

local function write_module(root, module_id, body)
  local path = module_file(root, module_id)
  os.execute("mkdir -p " .. shell_quote(path:match("^(.*)/[^/]+$")))
  local f = assert(io.open(path, "w"), "无法写入探针文件 " .. path)
  f:write(body)
  f:close()
end

-- Materialize a tree whose only dependency edge is from_id -> to_id, so any
-- edge-shaped violation arch_view reports about that pair is a verdict on the
-- direction itself rather than on unrelated repository content.
local function build_probe(from_id, to_id)
  os.execute("rm -rf " .. shell_quote(M.PROBE_ROOT))
  write_module(M.PROBE_ROOT, from_id,
    string.format('local dep = require("%s")\nreturn dep\n', to_id))
  write_module(M.PROBE_ROOT, to_id, "return {}\n")
end

-- The arch_view check table for a tree containing only from_id -> to_id.
-- config_path stays the repository's real gate config, so the probe is judged
-- by the same rules as `tools/arch check`.
function M.check_edge(from_id, to_id)
  require("tools.arch_bootstrap").ensure()
  local arch = require("arch_view")
  build_probe(from_id, to_id)
  local model, err = arch.analyze({
    project_root = M.PROBE_ROOT,
    config_path = "arch_view.config.json",
  })
  os.execute("rm -rf " .. shell_quote(M.PROBE_ROOT))
  if model == nil then return nil, err end
  return model.check
end

-- True if the gate rejects a from_id -> to_id dependency. Only violations
-- naming exactly that pair count, so an unrelated finding (an unclassified
-- probe module, say) can never make this quietly true. Returns the violation
-- kind as the second value for reporting.
function M.rejects_edge(from_id, to_id)
  local check, err = M.check_edge(from_id, to_id)
  if check == nil then return nil, err end
  for _, violation in ipairs(check.violations or {}) do
    if violation.from == from_id and violation.to == to_id then
      return true, violation.kind
    end
  end
  return false
end

return M
