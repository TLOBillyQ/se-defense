-- tools/acceptance/steps_placement.lua — 放置步骤（placement.feature，04 R1–R10）：
-- 资金设定、可选判定、选择待建/确认/取消、放置态读取。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, needs_match, expect_yes_no, known_kind = S.headless, S.needs_session, S.needs_match, S.expect_yes_no, S.known_kind

return { patterns = {
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
} }
