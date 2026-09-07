-- 05_BaseDefence 波次导演器（WaveDirector）。
--
-- 职责：在 game_state.mode == "Playing" 时驱动“平静→来袭→清场”循环。
-- 单波切片实现：固定 enemy_count、spawn_interval，不实现随波数升级的
-- tier/budget 系统（后续 ticket）。表现层替换：敌人死亡后由表现层自行处理，
-- 导演器只通过 health.is_alive 追踪存活数。
--
-- 注入的 spawn_enemy(front, position) 必须返回一个 handle，handle 需暴露：
--   handle.health.is_alive —— 可读信号（具备 :now()），true 表示仍存活。
-- 导演器内部会为每个 handle 挂载一个 tracker effect，在 is_alive 首次变为 false
-- 时减少剩余存活计数并自动卸载该 tracker。
--
-- 本组件只保留状态机壳（wave 状态、wave_started/wave_defeated 触发器与按
-- mode 路由的 root effect）；平静/来袭 phase 内的行为见
-- server.game.wave_cycle。

local Epoch = require("common.spoke.runtime.epoch")
local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")
local Effect = require("common.spoke.reactive.effect")

local WaveCycle = require("server.game.wave_cycle")

local WaveDirector = Epoch.extend("WaveDirector", {
  constructor = function(self, config)
    config = config or {}
    -- 规范化默认值，供 wave_cycle 与 wave_enemy_config 读取。
    config.lull_duration = config.lull_duration or 8
    config.front_reveal_time = config.front_reveal_time or 5
    config.spawn_interval = config.spawn_interval or 1
    config.enemy_count = config.enemy_count or 4
    config.spawn_margin = config.spawn_margin or 2
    self._config = config
    self._waves = config.waves
    self.wave = State.new("wave", {
      number = 1,
      front = "None",
      starts_in = math.ceil(config.lull_duration),
    })
    self.wave_started = Trigger.new("wave_started")
    self.wave_defeated = Trigger.new("wave_defeated")
  end,

  -- 当前波次的组合配置：支持全局回退的 per-wave enemy_count/spawn_interval/
  -- enemy 变体键与敌人属性覆盖。返回表可直接传给 spawn_enemy 的第三参数。
  wave_enemy_config = function(self)
    local config = self._config
    local global_enemy = config.enemy or {}
    local wave = self._waves and self._waves[self.wave:now().number]
    local wave_enemy = wave and wave.enemy or {}
    return {
      enemy_count = wave and wave.enemy_count or config.enemy_count,
      spawn_interval = wave and wave.spawn_interval or config.spawn_interval,
      prefab = wave_enemy.prefab or global_enemy.prefab or "enemy",
      max_hp = wave_enemy.max_hp or global_enemy.max_hp,
      move_speed = wave_enemy.move_speed or global_enemy.move_speed,
      stop_distance = wave_enemy.stop_distance or global_enemy.stop_distance,
      fire_rate = wave_enemy.fire_rate or global_enemy.fire_rate,
      damage = wave_enemy.damage or global_enemy.damage,
      radius = wave_enemy.radius or global_enemy.radius,
    }
  end,

  init = function(self, s)
    local config = self._config
    local game_state = config.game_state

    s:call(Effect.new("WaveDirectorRoot", function(s2)
      local is_playing = s2:memo(function(s3)
        return s3:d(game_state.mode) == "Playing"
      end)

      s2:phase(is_playing, function(s3)
        local is_assaulting = s3:memo(function(s4)
          return s4:d(self.wave).starts_in == 0
        end)
        local is_lull = s3:memo(function(s4)
          return not s4:d(is_assaulting)
        end)

        s3:phase(is_lull, function(s4)
          WaveCycle.lull(self, s4)
        end)
        s3:phase(is_assaulting, function(s4)
          WaveCycle.assault(self, s4)
        end)
      end)
    end))
  end,
})

return WaveDirector
