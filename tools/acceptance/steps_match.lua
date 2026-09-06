-- tools/acceptance/steps_match.lua — 对局流程步骤（match-flow.feature，01 R1–R8）
-- 与所有 gameplay feature 共用的基础步骤：启动一局、玩家开始/重开/复合放置、
-- 推进秒数（记下资金、倒计时、矿点剩余量供「与推进前相同」比较）、
-- 实体在场/计数等编排动作与读取。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, needs_match, expect_yes_no, known_kind, EPS = S.headless, S.needs_session, S.needs_match, S.expect_yes_no, S.known_kind, S.EPS

return { patterns = {
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
} }
