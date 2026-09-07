-- 05_BaseDefence 波次导演器（WaveDirector，规则真源 docs/gdd/07-enemies-waves.md）。
--
-- 职责：在 game_state.mode == "Playing" 时按宿主固定步长推进波次状态：
-- 平静期倒计时（≤5 秒公布来袭方向）→ 归零进入进攻期并按预算生成敌人 →
-- 预算耗尽停 → 本波全灭后进入下一波。数值（预算 2+(N−1)、层级解锁 4/8、
-- 间隔 max(0.25, 1−0.1(N−1))、边界外 6 生成、航线指向中心 ±10）见
-- server/game/world.lua 的 wave/enemy_tiers 表；每拍逻辑在 wave_cycle.lua。
--
-- wave 状态表字段：
--   number        波号（1 起）
--   countdown     平静期剩余秒（浮点；进攻期为 0）
--   starts_in     ceil(countdown)，兼容旧显示消费方（status_ui/announcer）
--   assault       进攻期标志（首只敌人生成 → true；本波全灭编排可清）
--   direction     来袭方向索引（world.directions；平静期开始即选定）
--   front         公布后的方向英文名（announcer 边缘警示路径用），未公布 "None"
--   spawn_log     本波生成层级序列（含编排生成）
--   cost_sum      本波自动生成成本总和（编排生成不计）
--   budget_left / spawned / since_spawn / spawn_done  生成簿记
--
-- 注入：
--   config.spawn_enemy(spec) 必须返回 handle，handle.health.is_alive 可读；
--   spec = { x, z, tier, heading={x,z} }。
--   config.rng01() 随机源（默认 math.random；编排可固定，如固定最大值取上界）。
--
-- 编排接缝（无头 harness 用，server/main.lua GM 面转发）：
--   set_wave(n)        波号置 n、倒计时 30、方向未知（重抽）、预算 fresh
--   reroll_direction() 平静期未推进时按当前随机源重抽方向
--   spawn(spec)        编排生成（计入 spawn_log，不扣预算/成本）
--   set_assault(b)     直接切换进攻期标志
--   kill_all()         杀死本波全部存活敌人

local Epoch = require("common.spoke.runtime.epoch")
local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")
local Effect = require("common.spoke.reactive.effect")

local World = require("server.game.world")
local WaveCycle = require("server.game.wave_cycle")

local WaveDirector = Epoch.extend("WaveDirector", {
  constructor = function(self, config)
    config = config or {}
    self._config = config
    self._handles = {} -- 本波全部生成（含编排），用于全灭判定
    self.rng01 = config.rng01 or math.random
    self.wave = State.new("wave", WaveCycle.fresh_wave(self, 1))
    self.wave_started = Trigger.new("wave_started")
    self.wave_defeated = Trigger.new("wave_defeated")
  end,

  init = function(self, s)
    local config = self._config
    local game_state = config.game_state

    s:call(Effect.new("WaveDirector.root", function(s2)
      local is_playing = s2:memo(function(s3)
        return s3:d(game_state.mode) == "Playing"
      end)

      -- 只有 Playing 推进（GDD 01 R3）；卸载时停止监听。
      s2:phase(is_playing, function(s3)
        local unlisten = config.game_tick:listen(function(dt)
          WaveCycle.tick(self, dt)
        end)
        s3:on_cleanup(unlisten)
      end)
    end))
  end,
})

-- 全灭判定：本波没有任何存活敌人。
function WaveDirector:any_alive()
  local alive = {}
  local found = false
  for _, h in ipairs(self._handles) do
    if h.health and h.health.is_alive:now() then
      alive[#alive + 1] = h
      found = true
    end
  end
  self._handles = alive
  return found
end

-- 登记一次生成（auto 与编排共用）；返回 handle。
function WaveDirector:_register(spec, handle)
  self._handles[#self._handles + 1] = handle
  local w = self.wave:now()
  local log = { table.unpack(w.spawn_log) }
  log[#log + 1] = spec.tier
  self.wave:set(World.wave_merge(w, { spawn_log = log }))
  return handle
end

-- 编排生成：计入本波层级序列，不扣预算、不计成本、不影响进攻期标志。
function WaveDirector:spawn(spec)
  local handle = self._config.spawn_enemy(spec)
  return self:_register(spec, handle)
end

-- 编排：波号置 n（倒计时 30、方向未知、预算 fresh）。
function WaveDirector:set_wave(number)
  self._handles = {}
  self.wave:set(WaveCycle.fresh_wave(self, number))
end

-- 编排：平静期未推进（倒计时满、未生成、非进攻期）时按当前随机源重抽方向。
function WaveDirector:reroll_direction()
  local w = self.wave:now()
  if w.countdown < World.wave.calm or w.assault or w.spawned > 0 then return end
  self.wave:set(World.wave_merge(w, { direction = WaveCycle.randi(self, 1, #World.directions) }))
end

-- 编排：直接切换进攻期标志。
function WaveDirector:set_assault(flag)
  local w = self.wave:now()
  self.wave:set(World.wave_merge(w, { assault = flag and true or false }))
end

-- 编排：杀死本波全部存活敌人。
function WaveDirector:kill_all()
  for _, h in ipairs(self._handles) do
    if h.health and h.health.is_alive:now() then
      h.health:damage(99999)
    end
  end
end

-- 来袭方向（中文名）：倒计时 ≤ reveal_at 才公布，否则 nil。
function WaveDirector:revealed_direction()
  local w = self.wave:now()
  if w.countdown > World.wave.reveal_at then return nil end
  return World.directions[w.direction].name
end

return WaveDirector
