-- 05_BaseDefence 主基地组件（Core）。
--
-- 职责：作为电网根节点与游戏失败条件，组合一个 Building 兄弟组件负责生命值、
-- footprint 与受击反馈。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Core.cs。
--
-- 既定裁剪（ADR）：
--   - 命中闪烁 → 实体变色（由 Building 统一实现）；
--   - 碎裂/爆炸特效裁掉，死亡时 print 消息并回收/销毁实体；
--   - 真实 PowerNode 作为电网根，provide_range 覆盖范围内为其他节点供电。
--
-- 建筑实体由外部注入（pool 或组合方拥有生命周期），本组件不自行 spawn 实体。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Building = require("server.units.building")
local PowerNode = require("server.power.power_node")

local Core = Epoch.extend("Core", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.host")
    self.entity = config.entity or error("Core requires entity", 2)
    self.max_hp = config.max_hp or error("Core requires max_hp", 2)
    self.display_name = config.display_name or "Core"
    self.provide_range = config.provide_range or 4
    self.radius = config.radius or 0.5
    self.power_zone = config.power_zone
    self.ground_zone = config.ground_zone
    self.game_tick = config.game_tick
    self.pool = config.pool
    self.pool_instance = config.pool_instance
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity
    local display_name = self.display_name
    local provide_range = self.provide_range
    local power_zone = self.power_zone

    -- Core 是电网根：真实 PowerNode，恒有电，向覆盖范围提供电力。
    local power_node = s:call(PowerNode.new({
      is_root = true,
      provide_range = provide_range,
      power_zone = power_zone,
      game_tick = self.game_tick,
      get_position = function()
        return entity:get_position()
      end,
    }))
    self.power_node = power_node

    -- 组合 Building 负责生命值、footprint、受击闪烁、死亡回收。
    -- footprint 的 owner 设为 Core，使 BoardInteractions 悬停时能返回 Core 实例。
    self.building = s:call(Building.new({
      host = host,
      entity = entity,
      max_hp = self.max_hp,
      display_name = display_name,
      radius = self.radius,
      ground_zone = self.ground_zone,
      ground_collider_owner = self,
      power = power_node,
      game_tick = self.game_tick,
      pool = self.pool,
      pool_instance = self.pool_instance,
    }))

    -- 对外暴露组合根，敌人/game_state 靠 .entity / .health 找到 Core。
    self.health = self.building.health
    self.entity = entity

    -- 悬浮提示。
    self.hover_info = State.new({
      description = display_name:upper()
        .. "\n\nSeeds the power grid, all buildings must trace a path to it for receiving power.\n\n"
        .. "Game is over if this building is destroyed.",
      coverage = "Power",
      power_node = power_node,
    })

    -- 死亡爆炸（GDD 15 F3：Core 死亡额外播放爆炸）：碎裂 2 秒期间点亮
    -- core_explosion 节点，Core 离场（departed）时熄灭。
    local explosion = host.eui.node("core_explosion")
    explosion:set_visible(false)
    s:call(Effect.new("Core.explosion", function(s2)
      local gone = not s2:d(self.health.is_alive)
      explosion:set_visible(gone and not self.building.departed:now())
    end, self.health.is_alive, self.building.departed))
    s:on_cleanup(function()
      host.eui.destroy(explosion)
    end)

    -- 死亡消息（上游爆炸特效的裁剪对应物）。
    s:call(Effect.new("Core.death_message", function(s2)
      if not s2:d(self.health.is_alive) then
        print(display_name .. " destroyed")
      end
    end, self.health.is_alive))
  end,
})

return Core
