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

-- ── 依赖关系约束（dependencies.feature）──
--
-- These predicates answer the gates feature against the arch_view model.
-- They are pure over the scanned architecture table (graph / modules) and the
-- raw arch_view config, so unit tests can feed synthetic models. The
-- forbidden / layer logic deliberately mirrors arch_view's
-- `internal/analyzer.lua` `_build_check` so the predicate agrees with the real
-- gate; scenario 1 (tools/arch check passes) is the independent Oracle that
-- keeps them honest.

-- True if the graph's edge list contains a direct from -> to edge.
-- `graph` is arch_view's `{ nodes = [...], edges = [{from,to}, ...] }`.
function M.arch_edge_exists(graph, from_id, to_id)
  for _, edge in ipairs((graph or {}).edges or {}) do
    if edge.from == from_id and edge.to == to_id then
      return true
    end
  end
  return false
end

-- The gate's declared layer for a module (arch_view ADR 0039 D2): an integer
-- for a layered component, the string "substrate" for a substrate component, or
-- nil when neither. Substrate deliberately carries no integer value.
local function _declared_layer(module)
  if module == nil then return nil end
  if module.component_substrate == true then return "substrate" end
  return module.component_layer
end

-- Mirrors arch_view `_is_layer_upward`: a lower layer depending on a higher one
-- (from_layer > to_layer) is the forbidden upward edge; substrate is qualitative
-- (anyone -> substrate legal, substrate -> any layered component illegal); edges
-- with no declared layer are not judged here.
local function _is_layer_upward(from_layer, to_layer)
  if from_layer == nil or to_layer == nil then return false end
  if from_layer == "substrate" then return to_layer ~= "substrate" end
  if to_layer == "substrate" then return false end
  return from_layer > to_layer
end

local function _matches_any(value, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if tostring(value):match(pattern) ~= nil then return true end
  end
  return false
end

-- True if the arch_view gate would reject an edge from_id -> to_id, i.e. either
-- a config forbidden_dependency_rules entry matches both ends, or the edge is a
-- layer-upward violation. The edge need not exist for this to be true: it is
-- the "fixed" assertion that the gate will refuse the direction.
function M.arch_edge_forbidden(config, modules, from_id, to_id)
  for _, rule in ipairs((config or {}).forbidden_dependency_rules or {}) do
    if _matches_any(from_id, rule.from) and _matches_any(to_id, rule.to) then
      return true
    end
  end
  return _is_layer_upward(
    _declared_layer((modules or {})[from_id]),
    _declared_layer((modules or {})[to_id])
  )
end

-- The declared gate layer for a component name, as configured. Returns the
-- integer layer, the string "基座" for a substrate component, or nil when the
-- component is not declared.
function M.arch_component_layer(config, component)
  for _, rule in ipairs((config or {}).component_rules or {}) do
    if rule.component == component then
      if rule.substrate == true then return "基座" end
      return rule.layer
    end
  end
  return nil
end

-- Count of reported projection cycles that are NOT waived by config
-- allowed_cycles: the ones the gate treats as violations.
function M.arch_unwaived_cycle_count(check)
  local count = 0
  for _, entry in ipairs((check or {}).projection_cycles or {}) do
    if entry.waived ~= true then count = count + 1 end
  end
  return count
end

return M
