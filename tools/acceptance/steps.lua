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
-- Game steps for features/gameplay and features/presentation boot a fresh
-- headless match per scenario (tools/acceptance/headless.lua); repository
-- steps in steps_repo.lua never boot a game.
local repo = require("tools.acceptance.steps_repo")
local headless = require("tools.acceptance.headless")

local M = {}

-- Each entry: Lua pattern on the resolved step text -> handler(w, captures...).
local PATTERNS = {}
for _, entry in ipairs(repo.patterns) do PATTERNS[#PATTERNS + 1] = entry end

-- ── 对局步骤（features/gameplay，规则真源 docs/gdd/）──

-- 前置包装：handler 需要一局已启动的对局。needs_session 注入 session，
-- needs_match 注入规则层对局对象；未启动时返回统一错误。
local function needs_session(fn)
  return function(w, ...)
    if not w.session then return nil, "尚未启动对局（背景缺「一局新对局」）" end
    return fn(w, w.session, ...)
  end
end

local function needs_match(fn)
  return needs_session(function(w, s, ...)
    return fn(w, s.match, ...)
  end)
end

local function expect_yes_no(value)
  if value ~= "是" and value ~= "否" then
    return nil, "在场期望只能是 是/否，实际 " .. tostring(value)
  end
  return value == "是"
end

local EPS = 1e-6

local game_patterns = {
  { "^一局新对局$", function(w)
      w.session = headless.boot()
      return true end },
  { "^对局阶段为(%S+)$", needs_match(function(w, m, expect)
      if m.mode == expect then return true end
      return nil, string.format("对局阶段期望 %s，实际 %s", expect, m.mode) end) },
  { "^玩家开始对局$", needs_session(function(w, s)
      headless.send(s, { action = "start" })
      return true end) },
  { "^玩家重开$", needs_session(function(w, s)
      headless.send(s, { action = "restart" })
      return true end) },
  { "^玩家在%((%-?[%d.]+),(%-?[%d.]+)%)放置(%w+)$", needs_session(function(w, s, x, z, kind)
      headless.send(s, { action = "place", kind = kind, x = tonumber(x), z = tonumber(z) })
      return true end) },
  -- 「推进 N 秒」记下推进前的资金与波次倒计时，供「与推进前相同」比较。
  { "^推进(%d+)秒$", needs_session(function(w, s, seconds)
      w.before = { money = s.match.money, countdown = s.match.wave.countdown }
      headless.advance(s, tonumber(seconds))
      return true end) },
  { "^资金为(%d+)$", needs_match(function(w, m, expect)
      if m.money == tonumber(expect) then return true end
      return nil, string.format("资金期望 %s，实际 %s", expect, m.money) end) },
  { "^资金与推进前相同$", needs_match(function(w, m)
      if not w.before then return nil, "尚未推进（缺「与推进前相同」的基准）" end
      if m.money == w.before.money then return true end
      return nil, string.format("资金期望与推进前 %s 相同，实际 %s", w.before.money, m.money) end) },
  { "^波次倒计时与推进前相同$", needs_match(function(w, m)
      if not w.before then return nil, "尚未推进（缺「与推进前相同」的基准）" end
      if m.wave.countdown == w.before.countdown then return true end
      return nil, string.format("波次倒计时期望与推进前 %s 相同，实际 %s",
        w.before.countdown, m.wave.countdown) end) },
  { "^第(%d+)波倒计时为([%d.]+)秒$", needs_match(function(w, m, number, countdown)
      if m.wave.number ~= tonumber(number) then
        return nil, string.format("波号期望 %s，实际 %s", number, m.wave.number)
      end
      if math.abs(m.wave.countdown - tonumber(countdown)) <= EPS then return true end
      return nil, string.format("第 %s 波倒计时期望 %s 秒，实际 %s",
        number, countdown, m.wave.countdown) end) },
  { "^采空(%d+)个矿点$", needs_match(function(w, m, n)
      m:deplete_sites(tonumber(n))
      return true end) },
  { "^剩余矿点数为(%d+)$", needs_match(function(w, m, expect)
      local actual = m:count_sites()
      if actual == tonumber(expect) then return true end
      return nil, string.format("剩余矿点数期望 %s，实际 %s", expect, actual) end) },
  { "^(%w+)死亡$", needs_match(function(w, m, kind)
      if m:kill(kind) then return true end
      return nil, "场上没有可死亡的 " .. kind end) },
  { "^一座已建好的(%w+)位于%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_match(function(w, m, kind, x, z)
      m:add_building(kind, tonumber(x), tonumber(z))
      return true end) },
  { "^(%w+)是否在场为(%S+)$", needs_match(function(w, m, kind, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m:present(kind) == want then return true end
      return nil, string.format("%s 在场期望 %s，实际 %s",
        kind, expect, m:present(kind) and "是" or "否") end) },
  { "^场上建筑数为(%d+)$", needs_match(function(w, m, expect)
      local actual = m:count_buildings()
      if actual == tonumber(expect) then return true end
      return nil, string.format("场上建筑数期望 %s，实际 %s", expect, actual) end) },
}

for _, entry in ipairs(game_patterns) do PATTERNS[#PATTERNS + 1] = entry end

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
