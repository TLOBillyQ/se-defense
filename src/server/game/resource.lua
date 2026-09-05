-- 05_BaseDefence 矿点组件（Resource）。
--
-- 职责：独立于 Building 的可采集资源点；有电且非空袭时按 collect_time 产出金钱，
-- 采空后消失。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Resource.cs。
--
-- 既定裁剪（ADR）：
--   - 碎裂动画裁掉，采空直接 print 消息并 despawn/destroy 实体；
--   - 采集特效（harvestFX）裁掉；
--   - 无 Health，不可受伤。
--
-- 实体由外部注入（pool 或组合方拥有生命周期），本组件不自行 spawn 实体。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Phase = spoke.Phase
local Memo = spoke.Memo
local PowerNode = require("server.game.power_node")
local HealthBar = require("server.game.health_bar")
local ResourceHarvest = require("server.game.resource_harvest")

-- 注册 s:coroutine() 扩展。
require("server.game.coroutine")

local Resource = Epoch.extend("Resource", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.entity = config.entity or error("Resource requires entity", 2)
    self.radius = config.radius or 0.6
    self.collect_time = config.collect_time or 2
    self.start_resources = config.start_resources or 20
    self.power = config.power
    self.power_zone = config.power_zone
    self.ground_zone = config.ground_zone
    self.game_state = config.game_state or error("Resource requires game_state", 2)
    self.director = config.director
    self.game_tick = config.game_tick
    self.pool = config.pool
    self.pool_instance = config.pool_instance
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity
    local radius = self.radius
    local collect_time = self.collect_time
    local start_resources = self.start_resources
    local game_state = self.game_state
    local director = self.director
    local game_tick = self.game_tick

    -- 若未外部注入 power，但提供了 power_zone，则自建叶子 PowerNode 取电。
    if not self.power and self.power_zone then
      self.power = s:call(PowerNode.new({
        provide_range = 0,
        receive_range = 0.1,
        power_zone = self.power_zone,
        game_tick = game_tick,
        get_position = function()
          return entity:get_position()
        end,
      }))
    end
    local power = self.power or { has_power = State.new(true) }

    -- 1. 剩余资源。上游在 IsEnabled phase 内重置；本端口简化为 init 即设置。
    self.remaining = State.new(start_resources)

    -- 2. 悬浮提示。
    self.hover_info = State.new({
      description = "",
      coverage = "None",
      power_node = power,
    })

    s:call(Effect.new("Resource.hover_info", function(s2)
      local left = s2:d(self.remaining)
      local description
      if left > 0 then
        description = "RESOURCE\n\nGenerates $"
          .. ("%.2f"):format(1 / collect_time)
          .. "/s while powered. Harvesting pauses during an attack.\n\n"
          .. left .. " remaining."
      else
        description = "RESOURCE\n\nDepleted."
      end
      self.hover_info:set({
        description = description,
        coverage = "None",
        power_node = power,
      })
    end, self.remaining))

    -- 3. 血条：按剩余资源占比显示（HealthBar 统一处理显示/填充/颜色）。
    local resource_fraction = s:call(Memo.new("Resource.fraction", function(s2)
      return s2:d(self.remaining) / start_resources
    end, self.remaining))
    self.health_bar = s:call(HealthBar.new({
      host = host,
      path = "resource_" .. entity.id .. "_hp",
      fraction = resource_fraction,
      hide_when_empty = true,
    }))

    -- 4. Footprint：供点选/范围伤害使用。
    if self.ground_zone then
      s:use(self.ground_zone:add_collider(self, function()
        return { center = entity:get_position(), radius = radius }
      end))
    end

    -- 5. 存活资源计数：未采空时 resources_remaining +1，cleanup -1。
    local has_resources = s:call(Memo.new("Resource.has_resources", function(s2)
      return s2:d(self.remaining) > 0
    end, self.remaining))

    s:call(Phase.new("Resource.standing", has_resources, function(s2)
      game_state.resources_remaining:update(function(x)
        return x + 1
      end)
      s2:on_cleanup(function()
        game_state.resources_remaining:update(function(x)
          return x - 1
        end)
      end)
    end))

    -- 6. 采集：Playing 期间、有电且非空袭时产出金钱、消耗资源
    --    （实现见 resource_harvest）。
    ResourceHarvest.install(s, self, {
      has_resources = has_resources,
      power = power,
      director = director,
      game_state = game_state,
      game_tick = game_tick,
      collect_time = collect_time,
    })

    -- 7. 采空：实体消失。
    local is_depleted = s:call(Memo.new("Resource.is_depleted", function(s2)
      return not s2:d(has_resources)
    end, has_resources))

    s:call(Phase.new("Resource.depleted", is_depleted, function(s2)
      print("Resource depleted")
      self._despawned = true
      if self.pool and self.pool_instance then
        self.pool:despawn(self.pool_instance)
      elseif entity and entity.destroy then
        entity:destroy()
      end
    end))

    -- 8. 清理兜底：若实体仍活跃且未被 pool 收走，则 destroy。
    s:on_cleanup(function()
      if entity and host.entity.by_id[entity.id] and entity:is_active() and not self._despawned then
        entity:destroy()
      end
    end)
  end,
})

return Resource
