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
-- needs_match 注入规则层对局对象（编排动作与实体读取走 m.entities）；
-- 未启动时返回统一错误。
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

-- 实体名必须来自实体总表，拒绝拼写变体（杀软变异存活体）。只在对局已启动后调用：
-- 实体总表随每场景的模块复位重新加载，因此按需 require 而非模块顶部捕获。
local function known_kind(kind)
  if require("server.game.world").specs[kind] then return true end
  return nil, "未知实体: " .. tostring(kind)
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
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      headless.send(s, { action = "place", kind = kind, x = tonumber(x), z = tonumber(z) })
      return true end) },
  -- 「推进 N 秒」记下推进前的资金、波次倒计时与每个矿点的剩余量，
  -- 供「与推进前相同」比较。
  { "^推进([%d.]+)秒$", needs_session(function(w, s, seconds)
      local sites = {}
      for _, e in ipairs(s.match.entities.list) do
        if e.kind == "Site" then sites[#sites + 1] = { x = e.x, z = e.z, remaining = e.remaining } end
      end
      w.before = { money = s.match.money, countdown = s.match.wave.countdown, sites = sites }
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
      m.entities:deplete_sites(tonumber(n))
      return true end) },
  { "^剩余矿点数为(%d+)$", needs_match(function(w, m, expect)
      local actual = m.entities:count_sites()
      if actual == tonumber(expect) then return true end
      return nil, string.format("剩余矿点数期望 %s，实际 %s", expect, actual) end) },
  { "^(%w+)死亡$", needs_match(function(w, m, kind)
      if m.entities:kill(kind) then return true end
      return nil, "场上没有可死亡的 " .. kind end) },
  { "^一座已建好的(%w+)位于%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_match(function(w, m, kind, x, z)
      m.entities:add_building(kind, tonumber(x), tonumber(z))
      return true end) },
  { "^(%w+)是否在场为(%S+)$", needs_match(function(w, m, kind, expect)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m.entities:present(kind) == want then return true end
      return nil, string.format("%s 在场期望 %s，实际 %s",
        kind, expect, m.entities:present(kind) and "是" or "否") end) },
  { "^场上建筑数为(%d+)$", needs_match(function(w, m, expect)
      local actual = m.entities:count_buildings()
      if actual == tonumber(expect) then return true end
      return nil, string.format("场上建筑数期望 %s，实际 %s", expect, actual) end) },
  -- ── 电网（power-grid.feature，03 R1–R10）──
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)是否通电为(%S+)$", needs_match(function(w, m, x, z, kind, expect)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      local e = m.entities:find(kind, tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      if m.grid:powered(e) == want then return true end
      return nil, string.format("位于(%s,%s)的%s通电期望 %s，实际 %s",
        x, z, kind, expect, m.grid:powered(e) and "是" or "否") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)被摧毁$", needs_match(function(w, m, x, z, kind)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local e = m.entities:find(kind, tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      m.entities:remove(e) -- 编排动作：摧毁即离场，不经碎裂
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)的供电者位于%((%-?[%d.]+),(%-?[%d.]+)%)$",
    needs_match(function(w, m, x, z, kind, px, pz)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local e = m.entities:find(kind, tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      local p = m.grid:provider(e)
      if not p then return nil, string.format("位于(%s,%s)的%s没有供电者", x, z, kind) end
      if math.abs(p.x - tonumber(px)) < EPS and math.abs(p.z - tonumber(pz)) < EPS then
        return true
      end
      return nil, string.format("位于(%s,%s)的%s的供电者期望位于(%s,%s)，实际位于(%s,%s)",
        x, z, kind, px, pz, p.x, p.z) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)受到炸弹伤害([%d.]+)$", needs_match(function(w, m, x, z, kind, dmg)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local e = m.entities:find(kind, tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      m.entities:hurt(e, tonumber(dmg))
      return true end) },
  -- ── 经济与矿点（economy.feature，02 R1–R8）──
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量为(%d+)$", needs_match(function(w, m, x, z, expect)
      local e = m.entities:find("Site", tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有矿点", x, z) end
      if e.remaining == tonumber(expect) then return true end
      return nil, string.format("位于(%s,%s)的矿点剩余量期望 %s，实际 %s",
        x, z, expect, e.remaining) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量设为(%d+)$", needs_match(function(w, m, x, z, n)
      local e = m.entities:find("Site", tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有矿点", x, z) end
      e.remaining = tonumber(n)
      if e.remaining <= 0 then m.entities:remove(e) end -- 设为 0 即离场
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量与推进前相同$", needs_match(function(w, m, x, z)
      if not w.before or not w.before.sites then
        return nil, "尚未推进（缺「与推进前相同」的基准）"
      end
      local e = m.entities:find("Site", tonumber(x), tonumber(z))
      if not e then return nil, string.format("(%s,%s) 处没有矿点", x, z) end
      for _, b in ipairs(w.before.sites) do
        if math.abs(b.x - e.x) < EPS and math.abs(b.z - e.z) < EPS then
          if e.remaining == b.remaining then return true end
          return nil, string.format("位于(%s,%s)的矿点剩余量期望与推进前 %s 相同，实际 %s",
            x, z, b.remaining, e.remaining)
        end
      end
      return nil, string.format("推进前 (%s,%s) 处没有矿点记录", x, z) end) },
  { "^进入进攻期$", needs_match(function(w, m)
      m.wave.assault = true
      return true end) },
  { "^本波全灭$", needs_match(function(w, m)
      m.wave.assault = false
      return true end) },
  { "^采集速率为([%d.]+)$", needs_match(function(w, m, expect)
      local actual = m.economy:rate()
      if math.abs(actual - tonumber(expect)) <= EPS then return true end
      return nil, string.format("采集速率期望 %s，实际 %s", expect, actual) end) },
  -- ── 放置（placement.feature，04 R1–R10）──
  { "^资金设为(%d+)$", needs_match(function(w, m, n)
      m.money = tonumber(n)
      return true end) },
  { "^(%w+)是否可选为(%S+)$", needs_match(function(w, m, kind, expect)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m:selectable(kind) == want then return true end
      return nil, string.format("%s 可选期望 %s，实际 %s",
        kind, expect, m:selectable(kind) and "是" or "否") end) },
  { "^玩家选择待建(%w+)$", needs_session(function(w, s, kind)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      headless.send(s, { action = "select", kind = kind })
      return true end) },
  { "^玩家在%((%-?[%d.]+),(%-?[%d.]+)%)确认放置$", needs_session(function(w, s, x, z)
      headless.send(s, { action = "confirm", x = tonumber(x), z = tonumber(z) })
      return true end) },
  { "^玩家取消放置$", needs_session(function(w, s)
      headless.send(s, { action = "cancel" })
      return true end) },
  { "^是否处于放置态为(%S+)$", needs_match(function(w, m, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m:placing() == want then return true end
      return nil, string.format("放置态期望 %s，实际 %s",
        expect, m:placing() and "是" or "否") end) },
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
