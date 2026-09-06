-- tools/acceptance/steps.lua — Gherkin step handlers for features/*.feature.
--
-- acceptance4lua looks handlers up by exact step text (placeholders such as
-- <建筑> are kept in the key). Literal sentences that only differ by a value
-- share one implementation, so the table resolves unknown keys through Lua
-- patterns against the step text. Handlers receive
-- (world, example, step, resolved_text) and return true or nil plus a message.
-- Error messages avoid the phrase "not found": the runner treats it as an
-- infrastructure error.
--
-- Game steps for features/gameplay and features/presentation are written
-- alongside the greenfield rewrite (rules in docs/gdd/). Until then only the
-- repository-inspection steps in steps_repo.lua are registered.
local repo = require("tools.acceptance.steps_repo")

local M = {}

-- Each entry: Lua pattern on the resolved step text -> handler(w, captures...).
local PATTERNS = {}
for _, entry in ipairs(repo.patterns) do PATTERNS[#PATTERNS + 1] = entry end

local function dispatch(text)
  for _, entry in ipairs(PATTERNS) do
    local captures = { text:match(entry[1]) }
    if captures[1] ~= nil then return entry[2], captures end
  end
  return nil
end

-- Handler for a raw step text (with placeholders): resolve against the
-- example-substituted text at run time.
local function handler_for(key)
  if not dispatch((key:gsub("<[^<>]+>", "0"))) then return nil end
  return function(w, _, _, resolved_text)
    local fn, captures = dispatch(resolved_text)
    if not fn then return nil, "步骤无法匹配: " .. tostring(resolved_text) end
    return fn(w, table.unpack(captures))
  end
end

function M.handlers()
  return setmetatable({}, { __index = function(_, key)
    if type(key) ~= "string" then return nil end
    return handler_for(key)
  end })
end

M.patterns = PATTERNS
return M
