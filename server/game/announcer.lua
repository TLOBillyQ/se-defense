-- 05_BaseDefence 播报器（Announcer）。
--
-- 职责：在 Playing 期间播报波次事件——wave_started / wave_defeated 时在屏幕
-- 文本上闪出消息（定时消失），并在下一波方向揭示后闪烁对应屏幕边缘警告条。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/Announcer.cs。
--
-- 宿主等价物：uGUI Text → EUI 文本节点；边缘警告条 → 四个 EUI 节点
-- set_visible 闪烁。定时依赖 game_tick（s:coroutine + wait_seconds）。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect
local State = spoke.State

-- 确保 s:coroutine 扩展已加载。
require("server.game.spoke_coroutine")

local FRONT_PATHS = {
  North = "announce/warning/north",
  East = "announce/warning/east",
  South = "announce/warning/south",
  West = "announce/warning/west",
}

local Announcer = Epoch.extend("Announcer", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.game_state = config.game_state or error("Announcer requires game_state", 2)
    self.wave_director = config.wave_director or error("Announcer requires wave_director", 2)
    self.game_tick = config.game_tick or error("Announcer requires game_tick", 2)
    self.wave_warning_blink_time = config.wave_warning_blink_time or 0.5
    self.onscreen_message_time = config.onscreen_message_time or 4
  end,

  init = function(self, s)
    local host = self.host
    local game_state = self.game_state
    local wave_director = self.wave_director
    local game_tick = self.game_tick

    local onscreen = host.eui.node("announce/onscreen")
    onscreen:set_text("")

    local warnings = {}
    for _, front in ipairs({ "North", "East", "South", "West" }) do
      local node = host.eui.node(FRONT_PATHS[front])
      node:set_visible(false)
      warnings[front] = node
    end
    self.onscreen = onscreen
    self.warnings = warnings
    -- 边缘警示「显示」= 警示激活（正在闪烁），而非瞬时亮灭：闪烁 coroutine
    -- 每 0.5s 翻 visible，断言读 active（GDD 12 A3/A4；闪烁周期 =
    -- wave_warning_blink_time，经同名配置字段读取）。
    self.warning_active = {}
    for _, front in ipairs({ "North", "East", "South", "West" }) do
      self.warning_active[front] = State.new("Announcer.warning." .. front, false)
    end

    local is_playing = s:call(spoke.Memo.new("Announcer.is_playing", function(m)
      return m:d(game_state.mode) == "Playing"
    end, game_state.mode))

    s:call(spoke.Phase.new("Announcer.Playing", is_playing, function(s2)
      -- 波次警告：方向揭示（front ~= None）且尚未开打时闪烁对应边缘。
      s2:effect("Announcer.ShowWaveWarning", function(s3)
        local wave = s3:d(wave_director.wave)
        local front = wave.starts_in == 0 and "None" or wave.front
        local node = front ~= "None" and warnings[front] or nil
        if node == nil then
          return
        end

        node:set_visible(true)
        self.warning_active[front]:set(true)
        s3:on_cleanup(function()
          node:set_visible(false)
          self.warning_active[front]:set(false)
        end)

        s3:coroutine(game_tick, function(_, wait_seconds)
          while true do
            wait_seconds(self.wave_warning_blink_time)
            node:set_visible(not node.visible)
          end
        end)
      end)

      -- 事件消息：dock key "announce" 使新消息替换旧消息。
      local dock = s2:dock("announce")

      -- 订阅 wave 事件并闪出一条到点自动消失的消息（wave_started/wave_defeated 共用）。
      local function flash_wave(event, template)
        s2:subscribe(event, function(wave)
          dock:call("announce", Effect.new("Announcer.FlashMessage", function(s3)
            local message = template:format(wave.number)
            onscreen:set_text(message)
            s3:on_cleanup(function()
              onscreen:set_text("")
            end)
            s3:coroutine(game_tick, function(_, wait_seconds)
              wait_seconds(self.onscreen_message_time)
              onscreen:set_text("")
            end)
          end))
        end)
      end

      flash_wave(wave_director.wave_started, "Wave %d Incoming\nHarvesters Paused")
      flash_wave(wave_director.wave_defeated, "Wave %d Defeated")
    end))

    s:on_cleanup(function()
      onscreen:set_text("")
      for _, node in pairs(warnings) do
        node:set_visible(false)
      end
      host.eui.destroy(onscreen)
      for _, front in ipairs({ "North", "East", "South", "West" }) do
        host.eui.destroy(warnings[front])
      end
      self.onscreen = nil
      self.warnings = nil
      self.warning_active = nil
    end)
  end,
})

return Announcer
