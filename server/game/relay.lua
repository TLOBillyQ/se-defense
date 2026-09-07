-- 05_BaseDefence 中继站组件（Relay）。
--
-- 职责：扩展电力网覆盖范围；真正的接力逻辑由内部 PowerNode 承担，
--       本组件只组合 Building 通用能力与悬浮提示。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Relay.cs。
--
-- 既定裁剪（ADR）：
--   - 命中闪烁 / 断电变暗 / 死亡回收全部委托给 Building；
--   - 覆盖圈 / 电力线等表现由外部 BoardInteractions 根据 hover_info 绘制；
--   - 不自建 GameObject 中间层，entity 由外部注入。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Building = require("server.game.building")
local PowerNode = require("server.game.power_node")

local Relay
Relay = Epoch.extend("Relay", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.entity = config.entity or error("Relay requires entity", 2)
    self.max_hp = config.max_hp or error("Relay requires max_hp", 2)
    self.display_name = config.display_name or "Relay"
    self.provide_range = config.provide_range or 4
    self.receive_range = config.receive_range or 0.1
    self.power_zone = config.power_zone or error("Relay requires power_zone", 2)
    self.ground_zone = config.ground_zone
    self.game_tick = config.game_tick or error("Relay requires game_tick", 2)
    self.pool = config.pool
    self.pool_instance = config.pool_instance

    self.building = nil
    self.power_node = nil
    self.health = nil
    self.hover_info = nil
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity

    -- 1. PowerNode：负责真正的接力供电逻辑。
    self.power_node = s:call(PowerNode.new({
      get_position = function()
        return entity:get_position()
      end,
      receive_range = self.receive_range,
      provide_range = self.provide_range,
      power_zone = self.power_zone,
      game_tick = self.game_tick,
    }))

    -- 暴露常用字段别名，方便调用方像操作普通 PowerNode 一样操作 Relay。
    self.is_enabled = self.power_node.is_enabled
    self.has_power = self.power_node.has_power
    self.parent = self.power_node.parent

    -- 2. Building 兄弟组件：生命值、footprint、受击闪烁、死亡回收。
    -- footprint 的 owner 设为 Relay 自身，使 BoardInteractions 悬停时返回 Relay 实例。
    self.building = s:call(Building.new({
      host = host,
      entity = entity,
      max_hp = self.max_hp,
      display_name = self.display_name,
      ground_zone = self.ground_zone,
      ground_collider_owner = self,
      power = self.power_node,
      game_tick = self.game_tick,
      pool = self.pool,
      pool_instance = self.pool_instance,
    }))
    self.health = self.building.health

    -- 3. 悬浮提示。
    self.hover_info = State.new({
      description = self.display_name:upper() .. "\n\n" ..
        "Extends the power grid, relaying power to any building inside its coverage.\n\n" ..
        "Buildings lose power when their path to the Core is broken.",
      coverage = "Power",
      power_node = self.power_node,
    })
  end,
})

return Relay
