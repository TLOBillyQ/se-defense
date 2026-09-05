-- 05_BaseDefence 炮塔组件。
--
-- 职责：在通电且存活时扫描 enemy_zone，转向并攻击被雷达追踪的最近敌人；
--       无目标时随机闲逛；死后/断电时停止运转。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Turret.cs。
--
-- 既定裁剪（ADR）：
--   - 没有单独的 pivot/fireFrom GameObject，entity rotation 即炮塔朝向；
--   - 光束用 EUI line 节点表达；
--   - 没有雷达模块，本组件通过 enemy_zone sensor + owner.is_tracked 接口依赖雷达。
--
-- 转向/闲逛/攻击行为在 src.game.turret_behaviour，本组件只负责
-- 选择目标并按 is_running 挂载行为。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Memo = spoke.Memo
local Phase = require("vendor.spoke.reactive.phase")
local Building = require("src.game.building")
local PowerNode = require("src.game.power_node")
local TurretBehaviour = require("src.game.turret_behaviour")

-- 注册 s:coroutine() 扩展。
require("src.game.coroutine")

local Turret
Turret = Epoch.extend("Turret", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("src.adapter.host")
    self.entity = config.entity or error("Turret requires entity", 2)
    self.max_hp = config.max_hp or error("Turret requires max_hp", 2)
    self.display_name = config.display_name or "Turret"
    self.game_tick = config.game_tick or error("Turret requires game_tick", 2)

    self.power = config.power
    self.power_zone = config.power_zone
    self.enemy_zone = config.enemy_zone
    self.turret_zone = config.turret_zone
    self.ground_zone = config.ground_zone

    self.range = config.range or 5
    self.rotation_speed = config.rotation_speed or math.pi
    self.damage = config.damage or 1
    self.fire_rate = config.fire_rate or 2
    self.fire_angle = config.fire_angle or math.rad(5)
    self.beam_flash_time = config.beam_flash_time or 0.05

    self.rng = config.rng or function(lo, hi)
      return math.random() * (hi - lo) + lo
    end

    self.pool = config.pool
    self.pool_instance = config.pool_instance

    self.building = nil
    self.health = nil
    self.hover_info = nil
    self.target_direction = nil
    self.beam_node = nil
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity

    -- 0. 若未外部注入 power，但提供了 power_zone，则自建叶子 PowerNode 取电。
    if not self.power and self.power_zone then
      self.power = s:call(PowerNode.new({
        provide_range = 0,
        receive_range = 0.1,
        power_zone = self.power_zone,
        game_tick = self.game_tick,
        get_position = function()
          return entity:get_position()
        end,
      }))
    end

    -- 1. 组合 Building 兄弟组件，暴露 health/entity。
    self.building = s:call(Building.new({
      host = host,
      entity = entity,
      max_hp = self.max_hp,
      display_name = self.display_name,
      ground_zone = self.ground_zone,
      power = self.power,
      game_tick = self.game_tick,
      pool = self.pool,
      pool_instance = self.pool_instance,
    }))
    self.health = self.building.health

    -- 2. HoverInfo。
    self.hover_info = State.new({
      description = self.display_name:upper() .. "\n\n" ..
        "Fires at enemies inside its coverage that radar has revealed.\n\n" ..
        "Pair with radar coverage — a turret alone sees nothing.",
      coverage = "Turret",
      power_node = self.power,
    })

    -- 3. 初始朝向为 entity 当前朝向。
    local rot = entity:get_rotation()
    self.target_direction = { x = math.cos(rot), z = math.sin(rot) }

    -- 4. 光束 EUI 节点。
    local beam_path = "turret_" .. entity.id .. "_beam"
    local beam_node = host.eui.node(beam_path)
    -- 行为方法经 self.beam_node 复用同一节点（闭包捕获），不重查
    -- host.eui.nodes 内部表——真机适配器只需实现 eui.node()，无需复刻
    -- mock 的 nodes 映射。
    self.beam_node = beam_node
    beam_node:set_visible(false)

    -- 5. 运转阶段：存活且通电（上游 IsEnabled && HasPower）。
    local has_power = self.power and self.power.has_power
    local is_running = s:call(Memo.new("Turret.is_running", function(m)
      return m:d(self.health.is_alive) and (not has_power or m:d(has_power))
    end, self.health.is_alive, has_power))

    s:call(Phase.new("Turret.running", is_running, function(s2)
      -- 转向：每 tick 把 entity rotation 朝 target_direction 插值。
      s2:coroutine(self.game_tick, function(yield)
        local last_time = self.game_tick:time()
        while true do
          local now = self.game_tick:time()
          local dt = now - last_time
          last_time = now
          TurretBehaviour.rotate(self, dt)
          yield()
        end
      end)

      -- 注册 turret_zone 碰撞体（覆盖圈）。
      if self.turret_zone then
        s2:use(self.turret_zone:add_collider(self, function()
          return { center = entity:get_position(), radius = self.range }
        end))
      end

      -- enemy_zone sensor：扫描进入射程的敌人。
      local sensor
      if self.enemy_zone then
        sensor = s2:use(self.enemy_zone:add_sensor(function()
          return { center = entity:get_position(), radius = self.range }
        end))
      end

      -- 最近被追踪的敌人。
      local target = s2:call(Memo.new("Turret.target", function(m)
        if not sensor then
          return nil
        end
        for _, body in ipairs(m:d(sensor.overlaps)) do
          local owner = body.owner
          if owner and owner.is_tracked then
            if m:d(owner.is_tracked) then
              return owner
            end
          end
        end
        return nil
      end, sensor and sensor.overlaps))

      -- 根据是否有目标切换闲逛/攻击行为。
      s2:call(Effect.new("Turret.behaviour", function(s3)
        local t = s3:d(target)
        if t then
          TurretBehaviour.attack(self, s3, t)
        else
          TurretBehaviour.idle(self, s3)
        end
      end, target))

      s2:on_cleanup(function()
        beam_node:set_visible(false)
      end)
    end))

    s:on_cleanup(function()
      host.eui.destroy(beam_node)
    end)
  end,
})

return Turret
