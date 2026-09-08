-- tools/acceptance/steps_input.lua — 棋盘输入步骤（board-input.feature，
-- GDD 16 I1–I8）：按钮点击（建筑按钮 = place 意图，再点当前类型 = 取消；
-- 开始/重开按钮按阶段路由）、棋盘点击（tap）与拖动（hover）。
-- tap 边沿两个步长后才举起（server/host/input.lua TAP_DELAY_STEPS），
-- 点击棋盘后推进 3 个步长再返回。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, known_kind = S.headless, S.needs_session, S.known_kind

return { patterns = {
  { "^玩家点击(%S+)按钮$", needs_session(function(w, s, name)
      if name == "开始" then
        headless.send(s, { kind = "input", itype = "start" })
        return true
      end
      if name == "重开" then
        headless.send(s, { kind = "input", itype = "restart" })
        return true
      end
      local _, bad = known_kind(name)
      if bad then return nil, bad end
      headless.send(s, { kind = "input", itype = "place", key = string.lower(name) })
      return true end) },
  { "^玩家点击棋盘%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      headless.send(s, { kind = "input", itype = "tap", x = tonumber(x), z = tonumber(z) })
      headless.steps(s, 3)
      return true end) },
  { "^玩家拖动到棋盘%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      headless.send(s, { kind = "input", itype = "hover", x = tonumber(x), z = tonumber(z) })
      return true end) },
} }
