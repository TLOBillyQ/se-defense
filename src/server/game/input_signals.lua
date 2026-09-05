-- 05_BaseDefence 输入信号发布器。
--
-- 职责：把宿主输入轮询封装成响应式 Trigger/State，供 BoardInteractions 等订阅。
-- 对应上游 Examples/05_BaseDefence/Scripts/Controls/InputSignals.cs 及
-- CameraControls.View 的鼠标世界点部分。
--
-- 裁剪：本示例当前只需鼠标，因此未实现通用 key_down 字典；若后续 ticket 需要
-- 键盘输入，可仿照上游在此添加 KeyDown(key) 惰性 Trigger 机制。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Trigger = spoke.Trigger
local Effect = spoke.Effect

-- 确保 s:coroutine 扩展已加载。
require("server.game.coroutine")

local host_default = require("server.adapter.host")

local InputSignals = Epoch.extend("InputSignals", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or host_default
    self.game_tick = config.game_tick or error("InputSignals requires game_tick", 2)

    self.left_click = Trigger.new("InputSignals.left_click")
    self.right_click = Trigger.new("InputSignals.right_click")

    self.view = {
      mouse_point = State.new("InputSignals.view.mouse_point", nil),
    }
  end,

  init = function(self, s)
    local host = self.host
    local view = self.view

    s:call(Effect.new("InputSignals.poll", function(s2)
      s2:coroutine(self.game_tick, function(yield)
        while true do
          -- 先同步鼠标世界点，再触发点击事件；这样订阅者能在 click 回调里
          -- 读到本帧的鼠标位置（与上游 View.MousePoint 的更新顺序一致）。
          local p = host.input.get_mouse_world_point()
          view.mouse_point:set(p)

          if host.input.get_mouse_button_down(0) then
            self.left_click:invoke()
          end
          if host.input.get_mouse_button_down(1) then
            self.right_click:invoke()
          end

          yield()
        end
      end)
    end))
  end,
})

return InputSignals
