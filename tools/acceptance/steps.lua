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
-- This file only aggregates and dispatches. Step tables live one per system
-- next to the feature they serve (规则真源 docs/gdd/): steps_match /
-- steps_grid / steps_economy / steps_placement boot a fresh headless match per
-- scenario (tools/acceptance/headless.lua, shared helpers in steps_support);
-- repository steps in steps_repo.lua never boot a game.
local SOURCES = {
  "tools.acceptance.steps_repo",
  "tools.acceptance.steps_match",
  "tools.acceptance.steps_grid",
  "tools.acceptance.steps_economy",
  "tools.acceptance.steps_placement",
  "tools.acceptance.steps_waves",
  "tools.acceptance.steps_fire",
  "tools.acceptance.steps_repair",
}

local M = {}

-- Each entry: Lua pattern on the resolved step text -> handler(w, captures...).
local PATTERNS = {}
for _, name in ipairs(SOURCES) do
  for _, entry in ipairs(require(name).patterns) do PATTERNS[#PATTERNS + 1] = entry end
end

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
