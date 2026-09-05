-- 05_BaseDefence 状态 UI（示例本地，不进核心库）。
--
-- 职责：在宿主 EUI 上创建一组极简文本 HUD 节点，并通过 Spoke Effect
-- 与 game_state / wave_director 的信号保持同步；在 epoch 卸载时销毁节点。
-- 对应上游 SideBar.Gameplay 中的文本显示部分，仅保留表现层，不做面板路由。

local Epoch = require("vendor.spoke.runtime.epoch")
local Effect = require("vendor.spoke.reactive.effect")

local StatusUI = Epoch.extend("StatusUI", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or error("StatusUI requires host", 2)
    self.game_state = config.game_state or error("StatusUI requires game_state", 2)
    self.wave_director = config.wave_director or error("StatusUI requires wave_director", 2)
  end,

  init = function(self, s)
    local host = self.host
    local gs = self.game_state
    local wd = self.wave_director

    local mode_node = host.eui.node("hud/mode")
    local money_node = host.eui.node("hud/money")
    local collect_node = host.eui.node("hud/collect_rate")
    local wave_node = host.eui.node("hud/wave")
    local core_node = host.eui.node("hud/core")

    s:use(function()
      host.eui.destroy(mode_node)
      host.eui.destroy(money_node)
      host.eui.destroy(collect_node)
      host.eui.destroy(wave_node)
      host.eui.destroy(core_node)
    end)

    s:call(Effect.new("status_mode", function(sb)
      mode_node:set_text("Mode: " .. tostring(sb:d(gs.mode)))
    end))

    s:call(Effect.new("status_money", function(sb)
      local money = sb:d(gs.money)
      local rate = sb:d(gs.collect_rate)
      money_node:set_text(("Money: $%.0f (+%.0f/s)"):format(money, rate))
    end))

    s:call(Effect.new("status_collect", function(sb)
      local rate = sb:d(gs.collect_rate)
      collect_node:set_text(("Collect: $%.0f/s"):format(rate))
    end))

    s:call(Effect.new("status_wave", function(sb)
      local wave = sb:d(wd.wave)
      local header = ("Wave %d"):format(wave.number)
      if wave.starts_in == 0 then
        wave_node:set_text(("%s: %s attacking"):format(header, wave.front))
      elseif wave.front ~= "None" then
        wave_node:set_text(("%s: %s in %ds"):format(header, wave.front, wave.starts_in))
      else
        wave_node:set_text(("%s: in %ds"):format(header, wave.starts_in))
      end
    end))

    s:call(Effect.new("status_core", function(sb)
      local frac = sb:d(gs.core.health.hp_fraction)
      core_node:set_text(("Core: %d%%"):format(math.floor(frac * 100 + 0.5)))
    end))
  end,
})

return StatusUI
