-- 客户端 GM 面（`$CLI exec --platform client` / tools/integration 驱动），挂 _G.bd_client。
-- 只做注入与读回，不承载逻辑：SimulateTap 走真实捕获层 / EUIButton → 意图链路。

local Players = game:GetService("Players")

local M = {}

local function screen_gui()
  return Players.LocalPlayer and Players.LocalPlayer.PlayerGui.ScreenGui
end

-- deps: log、renderer、camera、channel
function M.create(deps)
  local log, renderer, camera, channel = deps.log, deps.renderer, deps.camera, deps.channel
  return {
    -- 在 EUI 画布坐标注入一次点击（走真实捕获层 → tap → 意图链路；集成测试用）
    sim_tap = function(x, y)
      local sg = screen_gui()
      if not sg then log("sim_tap：ScreenGui 不可用") return end
      sg:SimulateTap(Vector2.New(tonumber(x), tonumber(y)))
      log("sim_tap(%s,%s) 已注入", tostring(x), tostring(y))
    end,
    -- 画布坐标 → 棋盘坐标（不发意图，只打印换算结果）
    probe = function(x, y)
      local p = camera:screen_to_board(tonumber(x), tonumber(y))
      log("probe(%s,%s) → %s k=%s", tostring(x), tostring(y),
        p and string.format("棋盘 (%.2f,%.2f)", p.x, p.z) or "无交点", camera:scale_text())
    end,
    stats = function()
      local s = renderer:stats()
      log("CSTATS live_state=%d labels=%d buttons=%d hp_bars=%d rings=%d none=%d pending_hp=%d seq=%d gen=%d got_first=%s",
        s.state, s.labels, s.buttons, s.bars, s.rings, s.none, s.pending,
        channel.last_seq, renderer.generation or 0, tostring(channel.got_first))
    end,
    -- 用 SimulateTap 打按钮中心（走真实 EUIButton OnClicked → 意图链路；集成测试用）
    tap_button = function(path)
      local x, y = renderer:node_position(path)
      if not x then log("tap_button(%s)：无此按钮", tostring(path)) return end
      local sg = screen_gui()
      if not sg then log("tap_button：ScreenGui 不可用") return end
      sg:SimulateTap(Vector2.New(x, y))
      log("tap_button(%s) → SimulateTap(%.0f,%.0f)", path, x, y)
    end,
    -- 棋盘坐标 → 画布坐标 → SimulateTap（走真实捕获层 → tap 意图；整局验收 #30 用）
    tap_board = function(bx, bz)
      local x, y = camera:board_to_screen(tonumber(bx), tonumber(bz))
      if not x then log("tap_board(%s,%s)：%s", tostring(bx), tostring(bz), tostring(y)) return end
      local sg = screen_gui()
      if not sg then log("tap_board：ScreenGui 不可用") return end
      local back = camera:screen_to_board(x, y)
      sg:SimulateTap(Vector2.New(x, y))
      log("tap_board(%s,%s) → SimulateTap(%.0f,%.0f) 回算 (%s)", tostring(bx), tostring(bz), x, y,
        back and string.format("%.2f,%.2f", back.x, back.z) or "无交点")
    end,
  }
end

return M
