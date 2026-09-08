-- 05_BaseDefence 棋盘交互（悬停 + 放置）。
--
-- 职责：根据鼠标位置发布悬停单位、判断放置有效性并响应点击完成购买/放置。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/BoardInteractions.cs。
--
-- #23 表现层（覆盖圈/电力连线 → EUI ring/line 节点）已独立到
-- server.game.board_display，本文件只保留输入/选择与放置判定。
--
-- 关于 phase body 重跑：本端口 Phase 在 mount_when 为 true 期间，其 block 内
-- s:d 读取的信号变化时会重跑 body 并清理旧附件，与上游 BoardInteractions 靠
-- 此在 placing 变化时切换 FindHovered / PlaceBuilding 的行为一致。
--
-- 实现说明：
--   碰撞传感器在 init 层创建，确保 Manual 树在 game_tick:tick() 不自动 flush 时，
--   传感器仍能在首次 zone:tick() 就参与计算；hovering/placement_valid/点击响应
--   放在 Phase(is_playing) 内，只在 Playing 且鼠标在 bounds 内时生效。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Phase = require("common.spoke.reactive.phase")
local Memo = require("common.spoke.reactive.memo")

local BoardDisplay = require("server.game.board_display")
local BoardSensors = require("server.game.board_sensors")

local host_default = require("server.adapter.host")

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
    self.op_log = config.op_log

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
    -- 落点为什么不合法（GDD 04 R4 的两条各自的成因）：nil 未在放置态、
    -- "offboard" 指针不在棋盘上、"overlap" 压到已有足迹、"unpowered" 不在通电圈内、
    -- "ok" 合法。消息行按此分文案（#42 决策 4）。
    self.placement_reason = State.new("BoardInteractions.placement_reason", nil)
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
    local placement_reason = self.placement_reason

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

    -- 放置有效性：只在 Playing、有鼠标点、有放置项时计算。合法性与「为什么不合法」
    -- 是同一次判定的两个读数，所以先算成因，有效性由它派生（避免两套规则漂移）。
    -- 两条 R4 都不满足时报 overlap：压到东西比没电更具体，玩家先挪位置。
    local reason = s:call(Memo.new("BoardInteractions.reason", function(ss)
      if ss:d(placing) == nil then
        return nil
      end
      if not ss:d(is_playing) or not ss:d(has_mouse_point) then
        return "offboard"
      end
      if #ss:d(footprint_sensor.overlaps) > 0 then
        return "overlap"
      end
      if #ss:d(power_sensor.overlaps) == 0 then
        return "unpowered"
      end
      return "ok"
    end, is_playing, has_mouse_point, placing, footprint_sensor.overlaps, power_sensor.overlaps))

    local is_valid = s:call(Memo.new("BoardInteractions.is_valid", function(ss)
      return ss:d(reason) == "ok"
    end, reason))

    s:call(Effect.new("BoardInteractions.sync_validity", function(ss)
      placement_valid:set(ss:d(is_valid))
      placement_reason:set(ss:d(reason))
    end, is_valid, reason))

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
        local item = placing:now()
        if item == nil then
          return
        end
        -- 放置失败：落点不满足 GDD 04 R3（足迹悬空 / 未接入供电圈）。
        if not is_valid:now() then
          if self.op_log then
            local label = item.display_name
              or (item.key and (item.key:gsub("^%l", string.upper)) or "建筑")
            self.op_log:push("error", ("无法放置 %s：需在通电圈内且无重叠"):format(label))
          end
          return
        end
        local p = view.mouse_point:now()
        if p == nil then
          return
        end
        self.spawn(item, { x = p.x, y = 0, z = p.z })
        game_state.money:update(function(m)
          return m - item.cost
        end)
        if self.op_log then
          local label = item.display_name
            or (item.key and (item.key:gsub("^%l", string.upper)) or "建筑")
          self.op_log:push("success", ("已放置 %s，花费 $%d"):format(label, item.cost or 0))
        end
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
