-- 05_BaseDefence Enemy 单位（规则真源 docs/gdd/07-enemies-waves.md E1–E7）。
--
-- 行为：
--   - 出生时带固定航线（heading，指向「棋盘中心 ± 10」内一随机点，E2）；
--   - 目标选择（E3）：每拍对所有存活建筑评分 = 偏离航线（过出生点沿航线
--     方向的直线）的垂直距离 + 0.5 × 直线距离，取最小；目标离场或评分
--     易主即重选并重新接近；
--   - 移动（E1/E4）：直飞目标至距离 1.2 停下（越过停点当拍收敛到 1.2）；
--   - 投弹（E4/E5）：停稳后每 1 秒在目标位置投一枚炸弹，引信 0.3 秒后
--     对半径 1.2 内所有有血量建筑造成 0.5 伤害（矿点无血量，天然免伤）；
--   - 雷达（05）：存活期间注册 radar_zone sensor，被覆盖时 is_tracked=true；
--   - 死亡（E7）：无奖励，实体销毁由表现层（碎裂）接管前保持尸体 2 秒。
--   - 只有 Playing 推进（01 R3/W10）。
--
-- 数值集中在 server/game/world_data.lua（enemy_tiers / enemy_speed /
-- enemy_stop_distance / bomb_interval / bomb_fuse / bomb_radius / bomb_damage）。

local Epoch = require("common.spoke.runtime.epoch")
local Phase = require("common.spoke.reactive.phase")
local Memo = require("common.spoke.reactive.memo")
local Effect = require("common.spoke.reactive.effect")
local State = require("common.spoke.reactive.state")
local Health = require("server.game.health")
local HealthBar = require("server.game.health_bar")
local Building = require("server.game.building")
local World = require("server.game.world_data")
require("server.game.spoke_coroutine")

local EPS = 1e-9

-- E3：目标评分 = 偏离航线的垂直距离 + 0.5 × 直线距离。
local function score(route, pos, bpos)
  local dx, dz = bpos.x - pos.x, bpos.z - pos.z
  local dev = math.abs(route.x * dz - route.z * dx)
  return dev + 0.5 * math.sqrt(dx * dx + dz * dz)
end

local Enemy = Epoch.extend("Enemy", {
  constructor = function(self, config)
    self.host = config.host
    self.game_tick = config.game_tick
    self.game_state = config.game_state
    self.position = config.position or { x = 0, y = 0, z = 0 }
    self.prefab = config.prefab or "enemy"
    self.tier = config.tier
    self.max_hp = config.max_hp or World.enemy_tiers[config.tier or 1].health
    self.move_speed = config.move_speed or World.enemy_speed
    self.stop_distance = config.stop_distance or World.enemy_stop_distance
    self.bomb_interval = config.bomb_interval or World.bomb_interval
    self.bomb_fuse = config.bomb_fuse or World.bomb_fuse
    self.bomb_radius = config.bomb_radius or World.bomb_radius
    self.damage = config.damage or World.bomb_damage
    self.radius = config.radius or World.enemy_tiers[config.tier or 1].footprint
    -- E2：出生航线（固定，目标评分只用它，不随位置变）。
    self.route = config.heading or { x = 0, z = -1 }
    self.enemy_zone = config.enemy_zone
    self.radar_zone = config.radar_zone
    self.entity = nil
    self.health = nil

    -- 上游 tracked 默认 false；无雷达区时保持旧行为（恒 true）以兼容旧测试。
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

    -- 揭示标记（GDD 15 F5）：被通电 Radar 揭示期间点亮标记节点。
    local mark_node = self.host.eui.node("enemy_" .. self.entity.id .. "_mark")
    mark_node:set_visible(false)
    s:call(Effect.new("Enemy.Mark", function(s2)
      mark_node:set_visible(s2:d(self.is_tracked))
    end, self.is_tracked))
    s:on_cleanup(function()
      self.host.eui.destroy(mark_node)
    end)

    -- RadarTrack：被任意通电雷达 collider 覆盖时 is_tracked=true。挂在组件
    -- 生命周期（而非存活阶段）：死亡碎裂的 2 秒里尸体仍在棋盘上，覆盖关系不变，
    -- 已揭示标志因此保持（rewrite enemies 同语义；Turret 选目标另查 is_alive，
    -- 不会以尸体为目标）。
    if self.radar_zone then
      local radar_sensor = s:use(self.radar_zone:add_sensor(function()
        -- 实体销毁（碎裂完毕离场）后不再被任何雷达覆盖。
        if not self.entity then
          return { center = { x = 0, y = 0, z = 1e9 }, radius = 0 }
        end
        return { center = self.entity:get_position(), radius = self.radius }
      end))
      local has_radar = s:call(Memo.new("Enemy.has_radar", function(m)
        return #m:d(radar_sensor.overlaps) > 0
      end, radar_sensor.overlaps))
      s:call(Phase.new("Enemy.Tracked", has_radar, function(ss)
        self.is_tracked:set(true)
        ss:on_cleanup(function()
          self.is_tracked:set(false)
        end)
      end))
    end

    -- 存活阶段：敌人碰撞体注册 + 移动/投弹主循环。
    s:call(Phase.new("Enemy.Alive", self.health.is_alive, function(s2)
      if self.enemy_zone then
        s2:use(self.enemy_zone:add_collider(self, function()
          return { center = self.entity:get_position(), radius = self.radius }
        end))
      end

      local game_state = self.game_state
      local route = self.route
      local move_speed = self.move_speed
      local stop_distance = self.stop_distance

      s2:coroutine(self.game_tick, function(yield, wait_seconds)
        local last_time = self.game_tick:time()
        local target = nil        -- 当前目标 Building 实例
        local stopped = false
        local bombs = {}          -- 飞行中的炸弹 {x, z, fuse}

        local function dt()
          local now = self.game_tick:time()
          local d = now - last_time
          last_time = now
          return d
        end

        -- E3：对所有存活建筑评分取最小。
        local function pick_target(pos)
          local best, best_s
          for _, b in ipairs(Building.all()) do
            if b.health.is_alive:now() then
              local s3 = score(route, pos, b.entity:get_position())
              if not best_s or s3 < best_s then
                best, best_s = b, s3
              end
            end
          end
          return best
        end

        while true do
          -- 只有 Playing 推进（W10）；冻结时炸弹引信也停。
          if game_state.mode:now() ~= "Playing" then
            yield()
            dt() -- 丢弃冻结期间的时间，恢复时不跳变
          else
            local pos = self.entity:get_position()
            local chosen = pick_target(pos)
            if chosen ~= target then
              -- E3：目标离场或评分易主即重选；已投出的炸弹位置既定，继续飞。
              target = chosen
              stopped = false
              self._bomb_left = self.bomb_interval -- 停稳后 1 秒首弹
            end
            if not target then
              yield()
            else
              local step_dt = dt()
              local tpos = target.entity:get_position()
              local dx, dz = tpos.x - pos.x, tpos.z - pos.z
              local dist = math.sqrt(dx * dx + dz * dz)

              if not stopped then
                if dist <= stop_distance + EPS then
                  stopped = true
                else
                  local step = math.min(move_speed * step_dt, dist - stop_distance)
                  self.entity:set_position({
                    x = pos.x + dx / dist * step,
                    y = pos.y,
                    z = pos.z + dz / dist * step,
                  })
                  if step < move_speed * step_dt - EPS then
                    stopped = true
                  end
                end
              else
                -- E4：停稳后每 1 秒在目标位置投一枚炸弹。
                self._bomb_left = self._bomb_left - step_dt
                if self._bomb_left <= EPS then
                  bombs[#bombs + 1] = { x = tpos.x, z = tpos.z, fuse = self.bomb_fuse }
                  self._bomb_left = self._bomb_left + self.bomb_interval
                end
              end

              -- E5：引信结算（半径 1.2 内所有有血量建筑 −0.5；矿点不在
              -- Building.all()，天然免伤）。
              if #bombs > 0 then
                local left = {}
                for _, bomb in ipairs(bombs) do
                  bomb.fuse = bomb.fuse - step_dt
                  if bomb.fuse <= EPS then
                    for _, b in ipairs(Building.all()) do
                      if b.health.is_alive:now() then
                        local bp = b.entity:get_position()
                        if World.dist(bomb.x, bomb.z, bp.x, bp.z) <= self.bomb_radius + EPS then
                          b.health:damage(self.damage)
                        end
                      end
                    end
                  else
                    left[#left + 1] = bomb
                  end
                end
                bombs = left
              end
              yield()
            end
          end
        end
      end)
    end))

    -- 死亡阶段：尸体保留 2 秒（碎裂，15 F5）后销毁实体离场。
    local is_dead = Memo.new("Enemy.IsDead", function(m)
      return not m:d(self.health.is_alive)
    end, self.health.is_alive)
    s:call(is_dead)

    s:call(Phase.new("Enemy.Dead", is_dead, function(s2)
      if not self.game_tick then
        if self.entity then self.host.entity.destroy(self.entity) end
        return
      end
      s2:coroutine(self.game_tick, function(_, wait_seconds)
        wait_seconds(World.crumble_seconds)
        if self.entity then
          self.host.entity.destroy(self.entity)
          self.entity = nil
        end
      end)
    end))

    -- 若 owner 在存活时直接 drop 本 epoch，也要清理实体，避免宿主泄漏。
    s:on_cleanup(function()
      if self.entity then
        self.host.entity.destroy(self.entity)
        self.entity = nil
      end
    end)
  end,
})

return Enemy
