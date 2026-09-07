-- 05_BaseDefence 雷达组件。
--
-- 职责：通电且存活时向 radar_zone 注册覆盖圈，为炮塔揭示敌人；
--       碟形天线持续旋转。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Radar.cs。
--
-- 既定裁剪（ADR）：
--   - 覆盖圈 → CollisionWorld collider（EUI ring 由调用方渲染层读取）；
--   - 碟形天线 → host.entity.spawn('RadarDish', ...) 独立实体；
--   - 不自建 GameObject 中间层。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Memo = spoke.Memo
local Phase = require("common.spoke.reactive.phase")
local Building = require("server.game.building")
local PowerNode = require("server.game.power_node")

-- 注册 s:coroutine() 扩展。
require("server.game.coroutine")

local Radar
Radar = Epoch.extend("Radar", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.entity = config.entity or error("Radar requires entity", 2)
    self.max_hp = config.max_hp or error("Radar requires max_hp", 2)
    self.display_name = config.display_name or "Radar"
    self.game_tick = config.game_tick or error("Radar requires game_tick", 2)

    self.range = config.range or 8
    -- Prefabs/RadarBuilding.prefab 序列化 dishRotationSpeed: 90（度/秒），
    -- Lua 侧 set_rotation 用弧度，故默认取 π/2（约 1.5708）。
    self.dish_rotation_speed = config.dish_rotation_speed or math.rad(90)

    self.power_zone = config.power_zone or error("Radar requires power_zone", 2)
    self.radar_zone = config.radar_zone or error("Radar requires radar_zone", 2)
    self.ground_zone = config.ground_zone
    self.radius = config.radius or 0.4
    self.pool = config.pool
    self.pool_instance = config.pool_instance

    self.building = nil
    self.power_node = nil
    self.hover_info = nil
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity

    -- 1. PowerNode 叶子：只取电，不供电。
    self.power_node = s:call(PowerNode.new({
      is_root = false,
      receive_range = 0.1,
      provide_range = 0,
      get_position = function()
        return entity:get_position()
      end,
      power_zone = self.power_zone,
      game_tick = self.game_tick,
    }))

    -- 2. 组合 Building 兄弟组件。
    self.building = s:call(Building.new({
      host = host,
      entity = entity,
      max_hp = self.max_hp,
      display_name = self.display_name,
      radius = self.radius,
      ground_zone = self.ground_zone,
      -- footprint owner 指向本组件（带 hover_info），悬停命中才能取到描述。
      ground_collider_owner = self,
      power = self.power_node,
      game_tick = self.game_tick,
      pool = self.pool,
      pool_instance = self.pool_instance,
    }))
    self.health = self.building.health

    -- 3. HoverInfo。
    self.hover_info = State.new({
      description = self.display_name:upper() .. "\n\n" ..
        "Reveals enemies inside its coverage to turrets.\n\n" ..
        "Turrets cannot fire at enemies that no radar has revealed.",
      coverage = "Radar",
      power_node = self.power_node,
    })

    -- 4. 运转阶段：存活且通电。
    local has_power = self.power_node.has_power
    local is_running = s:call(Memo.new("Radar.is_running", function(m)
      return m:d(self.building.health.is_alive) and m:d(has_power)
    end, self.building.health.is_alive, has_power))

    s:call(Phase.new("Radar.running", is_running, function(s2)
      -- 注册雷达覆盖圈。
      s2:use(self.radar_zone:add_collider(self, function()
        return { center = entity:get_position(), radius = self.range }
      end))

      -- 碟形天线：独立实体，cleanup 时销毁。
      local dish = host.entity.spawn("RadarDish", entity:get_position())
      s2:coroutine(self.game_tick, function(yield)
        local last_time = self.game_tick:time()
        while true do
          local now = self.game_tick:time()
          local dt = now - last_time
          last_time = now
          dish:set_rotation(dish:get_rotation() + self.dish_rotation_speed * dt)
          yield()
        end
      end)

      s2:on_cleanup(function()
        dish:destroy()
      end)
    end))
  end,
})

return Radar
