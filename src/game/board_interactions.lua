-- 05_BaseDefence 棋盘交互（悬停 + 放置）。
--
-- 职责：根据鼠标位置发布悬停单位、判断放置有效性并响应点击完成购买/放置。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/BoardInteractions.cs。
--
-- #23 表现层（覆盖圈/电力连线 → EUI ring/line 节点）已独立到
-- src.game.board_display，本文件只保留输入/选择与放置判定。
--
-- 关于 phase body 重跑：本端口 Phase 在 mount_when 为 true 期间，其 block 内
-- s:d 读取的信号变化时会重跑 body 并清理旧附件，与上游 BoardInteractions 靠
-- 此在 placing 变化时切换 FindHovered / PlaceBuilding 的行为一致。
--
-- 实现说明：
--   碰撞传感器在 init 层创建，确保 Manual 树在 game_tick:tick() 不自动 flush 时，
--   传感器仍能在首次 zone:tick() 就参与计算；hovering/placement_valid/点击响应
--   放在 Phase(is_playing) 内，只在 Playing 且鼠标在 bounds 内时生效。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Phase = require("vendor.spoke.reactive.phase")
local Memo = require("vendor.spoke.reactive.memo")

local BoardDisplay = require("src.game.board_display")
local BoardSensors = require("src.game.board_sensors")

local host_default = require("src.adapter.host")

local BoardInteractions = Epoch.extend("BoardInteractions", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or host_default
    self.game_state = config.game_state or error("BoardInteractions requires game_state", 2)
    self.input_signals = config.input_signals or error("BoardInteractions requires input_signals", 2)
    self.pool = config.pool or error("BoardInteractions requires pool", 2)
    -- 可选覆盖：宿主/完整组合根可在 spawn 后补填 pool_instance 等元数据。
    self.spawn = config.spawn or function(spec, position)
      return self.pool:spawn(spec, position)
    end

    if not self.game_state.ground_zone then
      error("BoardInteractions requires game_state.ground_zone", 2)
    end
    if not self.game_state.power_zone then
      error("BoardInteractions requires game_state.power_zone", 2)
    end

    self.placing = State.new("BoardInteractions.placing", nil)
    self.hovering = State.new("BoardInteractions.hovering", nil)
    self.hovering_circle = State.new("BoardInteractions.hovering_circle", nil)
    self.placement_valid = State.new("BoardInteractions.placement_valid", false)
  end,

  init = function(self, s)
    local host = self.host
    local game_state = self.game_state
    local input_signals = self.input_signals
    local view = input_signals.view
    local placing = self.placing
    local hovering = self.hovering
    local hovering_circle = self.hovering_circle
    local placement_valid = self.placement_valid

    -- 传感器在 init 层创建，随宿主输入移动；这样无论树是否 auto-flush，
    -- zone:tick() 都能采样到最新鼠标位置（实现见 board_sensors）。
    local hover_sensor, footprint_sensor, power_sensor = BoardSensors.create(s, {
      host = host,
      game_state = game_state,
      placing = placing,
    })

    local is_playing = s:call(Memo.new("BoardInteractions.is_playing", function(ss)
      return ss:d(game_state.mode) == "Playing"
    end, game_state.mode))

    local has_mouse_point = s:call(Memo.new("BoardInteractions.has_mouse_point", function(ss)
      local p = ss:d(view.mouse_point)
      if p == nil then
        return false
      end
      local b = game_state:level_bounds()
      return p.x >= b.min.x and p.x <= b.max.x
          and p.z >= b.min.z and p.z <= b.max.z
    end, view.mouse_point))

    -- 放置有效性：只在 Playing、有鼠标点、有放置项时计算。
    local is_valid = s:call(Memo.new("BoardInteractions.is_valid", function(ss)
      if not ss:d(is_playing) or not ss:d(has_mouse_point) then
        return false
      end
      local item = ss:d(placing)
      if item == nil then
        return false
      end
      local ground_overlaps = ss:d(footprint_sensor.overlaps)
      local power_overlaps = ss:d(power_sensor.overlaps)
      return #ground_overlaps == 0 and #power_overlaps > 0
    end, is_playing, has_mouse_point, placing, footprint_sensor.overlaps, power_sensor.overlaps))

    s:call(Effect.new("BoardInteractions.sync_validity", function(ss)
      placement_valid:set(ss:d(is_valid))
    end, is_valid))

    s:call(Effect.new("BoardInteractions.sync_hovering", function(ss)
      if not ss:d(is_playing) or not ss:d(has_mouse_point) or ss:d(placing) ~= nil then
        hovering:set(nil)
        return
      end
      local overlaps = ss:d(hover_sensor.overlaps)
      local hit = overlaps[1]
      if hit and hit.owner and hit.owner.hover_info then
        hovering:set(hit.owner)
        hovering_circle:set({
          center = {
            x = hit.circle.center.x,
            y = hit.circle.center.y,
            z = hit.circle.center.z,
          },
          radius = hit.circle.radius,
        })
      else
        hovering:set(nil)
        hovering_circle:set(nil)
      end
    end, is_playing, has_mouse_point, placing, hover_sensor.overlaps))

    s:call(Phase.new("BoardInteractions.playing", is_playing, function(ss)
      -- 离开 Playing 时取消当前放置；hovering/placement_valid 由上面的 effect 清。
      ss:on_cleanup(function()
        placing:set(nil)
      end)

      ss:subscribe(input_signals.left_click, function()
        if not is_valid:now() then
          return
        end
        local p = view.mouse_point:now()
        if p == nil then
          return
        end
        local item = placing:now()
        if item == nil then
          return
        end
        self.spawn(item, { x = p.x, y = 0, z = p.z })
        game_state.money:update(function(m)
          return m - item.cost
        end)
        placing:set(nil)
      end)

      ss:subscribe(input_signals.right_click, function()
        placing:set(nil)
      end)

      -- 表现层：覆盖圈 / 电力连线 / 高亮环 → EUI ring/line（board_display）。
      BoardDisplay.mount(ss, {
        host = host,
        game_state = game_state,
        view = view,
        placing = placing,
        hovering = hovering,
        hovering_circle = hovering_circle,
        placement_valid = placement_valid,
      })
    end))
  end,
})

return BoardInteractions
