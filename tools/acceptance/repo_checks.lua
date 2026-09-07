-- tools/acceptance/repo_checks.lua — pure predicates that back the
-- features/engineering/spoke-primitives.feature repository inspections.
--
-- These are pure string checks (no game boot, no filesystem, no side effects)
-- so they stay testable by unit tests and reusable by the step handlers in
-- steps_repo.lua, which owns the file reading. The rule truth source is CONTEXT.md「spoke 原语约束」and the
-- feature's header comment.
local M = {}

-- True if `body` references the common.spoke facade (require("common.spoke"))
-- or any of its reactive/runtime submodules (require("common.spoke.reactive.X")
-- / require("common.spoke.runtime.X")). Matches only require-statement
-- prefixes, not comments that merely mention the name.
function M.references_common_spoke(body)
  return body:find("require[%s%(]*[\"']common%.spoke") ~= nil
end

-- True if `body` uses spoke primitive `prim` (CamelCase, e.g. "State").
-- Per the feature rule, any one of:
--   spoke.<Prim>                        facade access
--   spoke.reactive.<snake> / spoke.runtime.<snake>  subtable access
--   require("common.spoke.reactive.<snake>") / require("common.spoke.runtime.<snake>")
-- where <snake> is the lowercase primitive name.
-- for Dock, an EffectBuilder-scoped compose call (`ss:dock(...)`) also counts;
-- it is the Dock primitive reached through the EffectBuilder compose surface.
function M.uses_spoke_primitive(body, prim)
  local snake = prim:lower()
  if M._has_identifier(body, "spoke." .. prim)
      or M._has_identifier(body, "spoke.reactive." .. snake)
      or M._has_identifier(body, "spoke.runtime." .. snake)
      or body:find("require[%s%(]*[\"']common%.spoke%.reactive%." .. snake .. "([^%w_])") ~= nil
      or body:find("require[%s%(]*[\"']common%.spoke%.runtime%." .. snake .. "([^%w_])") ~= nil then
    return true
  end
  if snake == "dock" and body:find(":dock%(") then
    return true
  end
  return false
end

-- Module names required as string literals in `body`. Non-literal requires
-- (dynamic keys) are not matched; the exempt helpers under test use literals.
function M.literal_requires(body)
  local mods = {}
  for mod in body:gmatch("require[%s%(]*[\"']([^\"']+)") do
    mods[#mods + 1] = mod
  end
  return mods
end

-- Module names required by `body` that are not server.-prefixed.
function M.non_server_requires(body)
  local bad = {}
  for _, mod in ipairs(M.literal_requires(body)) do
    if not mod:match("^server%.") then bad[#bad + 1] = mod end
  end
  return bad
end

-- Names of `specs` ({name, body}) that do NOT reference common.spoke, sorted.
function M.non_spoke_modules(specs)
  local names = {}
  for _, s in ipairs(specs) do
    if not M.references_common_spoke(s.body) then names[#names + 1] = s.name end
  end
  table.sort(names)
  return names
end

-- True if `prefix` is followed by a non-identifier char (or end of text) in
-- `body`, so `spoke.State` is not fooled by `spoke.StateMachine`.
function M._has_identifier(body, prefix)
  local i = 1
  while true do
    local s, e = body:find(prefix, i, true)
    if not s then return false end
    local nextc = body:sub(e + 1, e + 1)
    if nextc == "" or not nextc:match("[%w_]") then return true end
    i = e + 1
  end
end

return M
