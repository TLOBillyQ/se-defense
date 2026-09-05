-- tools/acceptance/steps.lua — Gherkin step handlers for features/*.feature.
--
-- acceptance4lua looks handlers up by exact step text (placeholders such as
-- <建筑> are kept in the key). Literal sentences that only differ by a number
-- ("游戏推进100个tick" / "游戏推进4个tick") share one implementation, so the
-- table resolves unknown keys through Lua patterns against the step text.
-- Handlers receive (world, example, step, resolved_text) and return true or
-- nil plus a message. Error messages avoid the phrase "not found": the runner
-- treats it as an infrastructure error.
local headless = require("tools.acceptance.headless")
local repo = require("tools.acceptance.steps_repo")

local M = {}

local function session(w)
  if not w.game then error("对局尚未启动（缺少背景步骤「一局全新的无头游戏」）") end
  return w.game
end

local function eq(actual, expected, label)
  if actual == expected then return true end
  return nil, string.format("%s 期望 %s，实际 %s", label, tostring(expected), tostring(actual))
end

local function num(v) return tonumber(v) or v end

-- Each entry: Lua pattern on the resolved step text -> handler(w, captures...).
local PATTERNS = {
  { "^一局全新的无头游戏$", function(w) w.game = headless.boot() return true end },
  { "^客户端已就绪$", function(w) headless.send(session(w), { kind = "client_ready" }) return true end },
  { "^游戏推进(%d+)个tick$", function(w, n) headless.steps(session(w), tonumber(n)) return true end },
  { "^客户端发送放置意图(%S+)$", function(w, key)
      headless.send(session(w), { kind = "input", itype = "place", key = key }) return true end },
  { "^客户端点击棋盘(%S+) (%S+)$", function(w, x, z)
      w.money_before = headless.money(session(w))
      headless.send(session(w), { kind = "input", itype = "tap", x = num(x), z = num(z) }) return true end },
  { "^客户端重开对局$", function(w) headless.send(session(w), { kind = "input", itype = "restart" }) return true end },
  { "^GM把金钱设为(%d+)$", function(w, n) headless.gm(session(w), "money", tonumber(n)) return true end },
  { "^GM采空全部资源$", function(w) headless.gm(session(w), "mine_out") return true end },
  { "^GM摧毁核心$", function(w) headless.gm(session(w), "kill_core") return true end },
  { "^游戏处于(%S+)模式$", function(w, mode) return eq(headless.mode(session(w)), mode, "游戏模式") end },
  { "^没有建筑处于放置中$", function(w) return eq(headless.placing(session(w)), nil, "放置中的建筑") end },
  { "^金钱为(%d+)$", function(w, n) return eq(headless.money(session(w)), tonumber(n), "金钱") end },
  { "^金钱减少了(%d+)$", function(w, n)
      if w.money_before == nil then return nil, "尚未记录点击前的金钱" end
      return eq(w.money_before - headless.money(session(w)), tonumber(n), "金钱减少量") end },
  { "^棋盘上实体总数为(%d+)$", function(w, n) return eq(#headless.entities(session(w)), tonumber(n), "实体总数") end },
  { "^棋盘上(%S+)的数量为(%d+)$", function(w, prefab, n)
      return eq(#headless.entities(session(w), prefab), tonumber(n), prefab .. " 数量") end },
  { "^(%S+)已通电$", function(w, prefab)
      for _, e in ipairs(headless.entities(session(w), prefab)) do
        if headless.has_power(e) then return true end
      end
      return nil, prefab .. " 没有任何实体通电" end },
  { "^(%S+)横幅可见$", function(w, name)
      return eq(headless.node_visible(session(w), "sidebar/" .. name), true, name .. " 横幅可见") end },
}

-- Repository-inspection steps (source layout, deploy mirror) live in
-- steps_repo.lua; they share the same dispatch table.
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
