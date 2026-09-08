-- tools/acceptance/steps_placement.lua — 放置步骤（placement.feature，GDD 04
-- R1–R10）：资金设定、可选判定、选择待建/确认/取消、放置态读取。
-- 「玩家在 (x,z) 放置 X」复合步骤在 steps_match.lua。
--
-- tap/cancel 的点击边沿按 TAP_DELAY_STEPS（server/host/input.lua）在两个
-- 固定步长后才举起并被业务消费，因此确认/取消意图后推进 3 个步长（0.1 秒，
-- < 0.15 秒去抖、< 0.8 秒采集，不影响资金与通电断言）。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, expect_yes_no, known_kind =
  S.headless, S.needs_session, S.expect_yes_no, S.known_kind

return { patterns = {
  { "^资金设为(%d+)$", needs_session(function(w, s, n)
      headless.gm(s, "money", tonumber(n))
      return true end) },
  { "^(%w+)是否可选为(%S+)$", needs_session(function(w, s, kind, expect)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      local selectable, err = headless.selectable(s, kind)
      if selectable == nil then return nil, err end
      if selectable == want then return true end
      return nil, string.format("%s 可选期望 %s，实际 %s",
        kind, expect, selectable and "是" or "否") end) },
  { "^玩家选择待建(%w+)$", needs_session(function(w, s, kind)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      headless.send(s, { kind = "input", itype = "place", key = string.lower(kind) })
      return true end) },
  { "^玩家在%((%-?[%d.]+),(%-?[%d.]+)%)确认放置$", needs_session(function(w, s, x, z)
      headless.send(s, { kind = "input", itype = "tap", x = tonumber(x), z = tonumber(z) })
      headless.steps(s, 3)
      return true end) },
  { "^玩家取消放置$", needs_session(function(w, s)
      headless.send(s, { kind = "input", itype = "cancel" })
      headless.steps(s, 3)
      return true end) },
  { "^是否处于放置态为(%S+)$", needs_session(function(w, s, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      local placing = headless.placing(s) ~= nil
      if placing == want then return true end
      return nil, string.format("放置态期望 %s，实际 %s",
        expect, placing and "是" or "否") end) },
} }
