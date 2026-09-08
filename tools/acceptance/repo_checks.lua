-- tools/acceptance/repo_checks.lua — pure predicates over Lua source text,
-- backing features/engineering/spoke-primitives.feature and
-- features/source-layout.feature.
--
-- These are pure checks (no game boot, no filesystem, no side effects) so they
-- stay testable by unit tests and reusable by the step handlers in
-- steps_repo.lua, which owns the file reading.
-- Truth source: CONTEXT.md「spoke 原语约束」and the feature header comments.
-- The architecture-model predicates for dependencies.feature live in
-- arch_checks.lua; the gate query lives in arch_probe.lua.
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

-- Module names required by `body` that do not start with any of `prefixes`.
function M.requires_outside_prefixes(body, prefixes)
  local bad = {}
  for _, mod in ipairs(M.literal_requires(body)) do
    local allowed = false
    for _, prefix in ipairs(prefixes) do
      if mod:sub(1, #prefix) == prefix then
        allowed = true
        break
      end
    end
    if not allowed then bad[#bad + 1] = mod end
  end
  return bad
end

-- Module names required by `body` that are not server.-prefixed.
function M.non_server_requires(body)
  return M.requires_outside_prefixes(body, { "server." })
end

-- Module names required by `body` that are neither server.- nor common.-prefixed
-- (the spoke-first exemption rule allows both shared substrates).
function M.non_shared_requires(body)
  return M.requires_outside_prefixes(body, { "server.", "common." })
end

-- Strip comments and string literals so definition detection does not count
-- mentions in comments/strings. Replaced regions become a space to keep tokens
-- separated.
local function code_only(body)
  local out, i, n = {}, 1, #body
  while i <= n do
    local two = body:sub(i, i + 1)
    local c = body:sub(i, i)
    local rest = body:sub(i)
    local long_eq = rest:match("^%[(=*)%[")
    if two == "--" then
      local eq = rest:match("^%-%-%[(=*)%[")
      if eq then
        local close = "]" .. eq .. "]"
        local s = body:find(close, i + 4 + #eq, true)
        i = s and (s + #close) or (n + 1)
      else
        local nl = body:find("\n", i, true)
        i = nl or (n + 1)
      end
      out[#out + 1] = " "
    elseif long_eq then
      local close = "]" .. long_eq .. "]"
      local s = body:find(close, i + 2 + #long_eq, true)
      i = s and (s + #close) or (n + 1)
      out[#out + 1] = " "
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local cj = body:sub(j, j)
        if cj == "\\" then
          j = j + 2
        elseif cj == c then
          j = j + 1
          break
        else
          j = j + 1
        end
      end
      i = j
      out[#out + 1] = " "
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function function_keyword_defines(code, name)
  local i = 1
  while true do
    local s, e = code:find("function", i, true)
    if not s then return false end
    local before = code:sub(s - 1, s - 1)
    local after = code:sub(e + 1, e + 1)
    if not before:match("[%w_]") and not after:match("[%w_]") then
      local j = e + 1
      while code:sub(j, j):match("%s") do j = j + 1 end
      local chain = code:match("^([%w_][%w_%.%:]*)", j)
      if chain and chain:match("([%w_]+)$") == name then return true end
    end
    i = e + 1
  end
end

local function assignment_defines(code, name)
  local i = 1
  while true do
    local s, e = code:find(name, i, true)
    if not s then return false end
    local before = code:sub(s - 1, s - 1)
    local after = code:sub(e + 1, e + 1)
    if not before:match("[%w_]") and not after:match("[%w_]") then
      if code:sub(e + 1):match("^%s*=%s*function[%s%(]") then return true end
    end
    i = e + 1
  end
end

-- True if `body` defines a function named `name`: `function name(`,
-- `function t.name(`, `function t:name(`, `local function name(`, or an
-- assignment `name = function` / `t.name = function`. Comments, string
-- literals, calls, and forwarding assignments (`t.name = other.f`) do not count.
function M.defines_function(body, name)
  local code = code_only(body)
  return function_keyword_defines(code, name) or assignment_defines(code, name)
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
