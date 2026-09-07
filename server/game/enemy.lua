-- 05_BaseDefence Enemy 单位。
--
-- 忠实对应上游 Enemy.cs 的生命周期与行为：
--   - 出生时在配置位置生成宿主实体并挂载 Health；
--   - 存活期间通过 s:coroutine 每 tick 向 core 移动，进入 stop_distance 后以
--     fire_rate 频率攻击 core.health；
--   - 存活期间若提供 radar_zone，则注册 RadarTrack sensor，被雷达覆盖时
--     self.is_tracked 置 true，离开覆盖或死亡时置 false；
--   - 死亡时销毁实体（上游 shatter FX 在切片中省略）。
--
-- 本切片简化项：
--   - 目标固定为 game_state.core.entity，不做 heading-line 建筑选择；
--   - 不做 separation、bob 等表现/寻路细节；
--   - RadarTrack 的 showOnTracked 表现层已裁剪，仅暴露 is_tracked State。

local Epoch = require("common.spoke.runtime.epoch")
local Phase = require("common.spoke.reactive.phase")
local Memo = require("common.spoke.reactive.memo")
local Health = require("server.game.health")
local HealthBar = require("server.game.health_bar")
require("server.game.coroutine")

local Enemy = Epoch.extend("Enemy", {
  constructor = function(self, config)
    self.host = config.host
    self.game_tick = config.game_tick
    self.game_state = config.game_state
    self.position = config.position or { x = 0, y = 0, z = 0 }
    self.prefab = config.prefab or "enemy"
    self.max_hp = config.max_hp or 10
    self.move_speed = config.move_speed or 2
    self.stop_distance = config.stop_distance or 1.2
    self.fire_rate = config.fire_rate or 1
    self.damage = config.damage or 5
    self.enemy_zone = config.enemy_zone
    self.radar_zone = config.radar_zone
    self.radius = config.radius or 0.5
    self.entity = nil
    self.health = nil

    -- 上游 tracked 默认 false；无雷达区时保持旧行为（恒 true）以兼容旧测试。
    local State = require("common.spoke.reactive.state")
    self.is_tracked = State.new("Enemy.is_tracked", not self.radar_zone)
  end,

  init = function(self, s)
    self.entity = self.host.entity.spawn(self.prefab, self.position)
    self.health = Health.attach(s, { max_hp = self.max_hp })

    -- 血条：与上游 Enemy.cs 的 healthBar 对应，死亡/满血时隐藏。
    self.health_bar = s:call(HealthBar.new({
      host = self.host,
      path = "enemy_" .. self.entity.id .. "_hp",
      fraction = self.health.hp_fraction,
      is_alive = self.health.is_alive,
    }))

    -- 存活阶段：移动 + 攻击 + 雷达区注册
    s:call(Phase.new("Enemy.Alive", self.health.is_alive, function(s)
      if self.enemy_zone then
        s:use(self.enemy_zone:add_collider(self, function()
          return { center = self.entity:get_position(), radius = self.radius }
        end))
      end

      -- RadarTrack：被任意雷达 collider 覆盖时 is_tracked=true。
      if self.radar_zone then
        local radar_sensor = s:use(self.radar_zone:add_sensor(function()
          return { center = self.entity:get_position(), radius = self.radius }
        end))
        local has_radar = s:memo(function(m)
          return #m:d(radar_sensor.overlaps) > 0
        end)
        s:call(Phase.new("Enemy.Tracked", has_radar, function(ss)
          self.is_tracked:set(true)
          ss:on_cleanup(function()
            self.is_tracked:set(false)
          end)
        end))
      end

      s:coroutine(self.game_tick, function(yield, wait_seconds)
        local last_time = self.game_tick:time()
        local function dt()
          local now = self.game_tick:time()
          local d = now - last_time
          last_time = now
          return d
        end

        while true do
          local target = self.game_state.core.entity
          if not target then
            break
          end

          local target_pos = target:get_position()
          local pos = self.entity:get_position()
          local dx = target_pos.x - pos.x
          local dz = target_pos.z - pos.z
          local dist = math.sqrt(dx * dx + dz * dz)

          if dist <= self.stop_distance + 1e-6 then
            wait_seconds(1 / self.fire_rate)
            self.game_state.core.health:damage(self.damage)
            yield()
          else
            local step = math.min(self.move_speed * dt(), dist - self.stop_distance)
            local ratio = step / dist
            self.entity:set_position({
              x = pos.x + dx * ratio,
              y = pos.y,
              z = pos.z + dz * ratio,
            })
            yield()
          end
        end
      end)
    end))

    -- 死亡阶段：实体消失（上游 shatter 特效在本切片中省略）
    local is_dead = Memo.new("Enemy.IsDead", function(m)
      return not m:d(self.health.is_alive)
    end, self.health.is_alive)
    s:call(is_dead)

    s:call(Phase.new("Enemy.Dead", is_dead, function(s)
      if self.entity then
        self.host.entity.destroy(self.entity)
      end
    end))

    -- 若 owner 在存活时直接 drop 本 epoch，也要清理实体，避免宿主泄漏。
    s:on_cleanup(function()
      if self.entity then
        self.host.entity.destroy(self.entity)
      end
    end)
  end,
})

return Enemy
