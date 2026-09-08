-- 05_BaseDefence 血条组件（HealthBar）。
--
-- 职责：把一个 [0,1] 的 HP 占比信号同步到宿主 EUI 血条节点——显示/隐藏、
-- 填充比例、阈值颜色（healthy/moderate/severe）与百分比文本。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/HealthBar.cs。
--
-- 宿主等价物（#18 Q8）：不建 Image/rectTransform 中间层；headless 节点
-- 用 set_fill / set_color / set_text 记录等价状态，真机部署时替换为 EUI
-- 血条节点即可。
--
-- 使用方式（在 Epoch init(s) 或 effect 块中）：
--   local HealthBar = require("server.units.health_bar")
--   local bar = s:call(HealthBar.new({
--     host = host,
--     path = "building_1_hp",
--     fraction = health.hp_fraction,
--     is_alive = health.is_alive,   -- 可选；缺省视为始终存活
--   }))
--   bar.node / bar.fraction 可在测试中读取。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local HealthBar = Epoch.extend("HealthBar", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.host")
    self.path = config.path or error("HealthBar requires path", 2)
    self.fraction = config.fraction or error("HealthBar requires fraction signal", 2)
    self.is_alive = config.is_alive
    -- 上游 Resource 在 frac<=0 时直接隐藏整个 HealthBar；默认跟随 Health
    -- 语义（alive=false 隐藏），需要“空值也隐藏”的调用方打开此开关。
    self.hide_when_empty = config.hide_when_empty == true

    -- GDD 15 F1 色板（与 steps_support 命名色一致）：绿 / 黄 / 红。
    self.healthy_colour = config.healthy_colour or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
    self.moderate_colour = config.moderate_colour or { r = 1, g = 0.85, b = 0, a = 1 }
    self.severe_colour = config.severe_colour or { r = 1, g = 0.25, b = 0.25, a = 1 }
  end,

  init = function(self, s)
    local node = self.host.eui.node(self.path)
    node:set_visible(false)
    node:set_fill(1)
    self.node = node

    s:call(Effect.new("HealthBar.sync", function(sb)
      local frac = clamp01(sb:d(self.fraction))
      local alive = self.is_alive == nil or sb:d(self.is_alive)

      local show = alive and frac < 1 and (not self.hide_when_empty or frac > 0)
      if show then
        local colour
        if frac > 0.7 then
          colour = self.healthy_colour
        elseif frac > 0.3 then
          colour = self.moderate_colour
        else
          colour = self.severe_colour
        end

        node:set_visible(true)
        node:set_fill(frac)
        node:set_color(colour)
        node:set_text(("%d%%"):format(math.floor(frac * 100 + 0.5)))
      else
        node:set_visible(false)
      end
    end, self.fraction, self.is_alive))

    s:on_cleanup(function()
      self.host.eui.destroy(node)
      self.node = nil
    end)
  end,
})

return HealthBar
