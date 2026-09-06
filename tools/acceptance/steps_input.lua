-- tools/acceptance/steps_input.lua — 棋盘输入步骤（board-input.feature，
-- GDD 16 I1–I8）：按钮点击、棋盘点击、拖动（经 RemoteEvent 真通道上行到
-- server.present.board_input），放置态读取。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, needs_match, expect_yes_no =
  S.headless, S.needs_session, S.needs_match, S.expect_yes_no

return { patterns = {
  { "^玩家点击(%S+)按钮$", needs_session(function(w, s, name)
      headless.send(s, { action = "click_button", name = name })
      return true end) },
  { "^玩家点击棋盘%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      headless.send(s, { action = "click_board", x = tonumber(x), z = tonumber(z) })
      return true end) },
  { "^玩家拖动到棋盘%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      headless.send(s, { action = "drag_board", x = tonumber(x), z = tonumber(z) })
      return true end) },
  { "^是否处于放置态为(%S+)$", needs_match(function(w, m, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m:placing() == want then return true end
      return nil, string.format("放置态期望 %s，实际 %s",
        expect, m:placing() and "是" or "否") end) },
} }
