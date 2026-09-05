-- 05_BaseDefence 波次循环（WaveDirector 的“平静→来袭→清场”机制部分）。
--
-- WaveDirector 组件（src.game.wave_director）只保留状态机壳
-- （wave 状态与 root effect）；本文件实现每个 phase 内的行为：lull 倒计时并
-- 提前 reveal front，assault 按 spawn_interval 生成敌人、用 tracker effect
-- 追踪存活数并在清场时发布 wave_defeated。
--
-- 与上游的偏差：上游每波 Random.Range(1,5) 随机进攻方向；本实现默认按波次
-- 做确定性伪随机（未注入 pick_front 时），保证同一局可复现且不会永远从南面
-- 进攻。lull 结束发布的 front 对齐上游 wave.Now.Front 语义（lull 短于
-- front_reveal_time 时保持 "None"）。

local State = require("vendor.spoke.reactive.state")
local Effect = require("vendor.spoke.reactive.effect")

local WaveCycle = {}

local FRONTS = { "West", "East", "South", "North" }

local function default_pick_front(wave_number)
  -- 确定性伪随机：以波次为种子（上游每波 Random.Range(1,5)）。
  local seed = (wave_number * 2654435761) % 2147483648
  seed = (seed * 1103515245 + 12345) % 2147483648
  return FRONTS[1 + (seed % #FRONTS)]
end

function WaveCycle.is_valid_front(front)
  for _, f in ipairs(FRONTS) do
    if f == front then
      return true
    end
  end
  return false
end

-- 某个 front 的波次出生点：沿棋盘对应边、outro bounds spawn_margin。
function WaveCycle.edge_point(director, front)
  local bounds = director._config.game_state:level_bounds()
  local margin = director._config.spawn_margin
  local min_x, max_x = bounds.min.x, bounds.max.x
  local min_z, max_z = bounds.min.z, bounds.max.z
  local x = min_x + math.random() * (max_x - min_x)
  local z = min_z + math.random() * (max_z - min_z)

  if front == "West" then
    return { x = min_x - margin, y = 0, z = z }
  elseif front == "East" then
    return { x = max_x + margin, y = 0, z = z }
  elseif front == "South" then
    return { x = x, y = 0, z = min_z - margin }
  else
    return { x = x, y = 0, z = max_z + margin }
  end
end

-- 平静期：倒计时 starts_in，剩余 <= front_reveal_time 时 reveal chosen front。
function WaveCycle.lull(director, s)
  local config = director._config
  local chosen = config.pick_front
      and config.pick_front()
    or default_pick_front(director.wave:now().number)
  if not WaveCycle.is_valid_front(chosen) then
    chosen = "South"
  end

  s:coroutine(config.game_tick, function(yield)
    local remaining = config.lull_duration
    local last_time = config.game_tick:time()
    while remaining > 0 do
      local front = remaining <= config.front_reveal_time and chosen or "None"
      director.wave:set({
        number = director.wave:now().number,
        front = front,
        starts_in = math.ceil(remaining),
      })
      yield()
      local now = config.game_tick:time()
      remaining = remaining - (now - last_time)
      last_time = now
    end
    -- 对齐上游 wave.Now.Front：lull 短于 front_reveal_time 时保持 "None"。
    director.wave:set({
      number = director.wave:now().number,
      front = director.wave:now().front,
      starts_in = 0,
    })
    director.wave_started:invoke(director.wave:now())
  end)
end

-- 来袭期：按当前波次配置在 chosen front 外生成敌人，每个敌人挂一个 tracker
-- effect，全部死亡时发布 wave_defeated 并进入下一波。
function WaveCycle.assault(director, s)
  local config = director._config
  local wave_cfg = director:wave_enemy_config()
  local enemy_count = wave_cfg.enemy_count or 1
  local spawn_interval = wave_cfg.spawn_interval or 1
  local enemy_cfg = wave_cfg

  local done_spawning = State.new(false)
  local remaining = State.new(0)
  local dock = s:dock()
  local spawn_serial = 0

  s:coroutine(config.game_tick, function(yield, wait_seconds)
    yield()
    for _ = 1, enemy_count do
      local front = director.wave:now().front
      local position = WaveCycle.edge_point(director, front)
      local handle = config.spawn_enemy(front, position, enemy_cfg)
      remaining:update(function(x) return x + 1 end)

      spawn_serial = spawn_serial + 1
      local key = "enemy_tracker_" .. spawn_serial
      local counted = false
      dock:call(key, Effect.new("EnemyTracker", function(s2)
        if s2:d(handle.health.is_alive) then
          return
        end
        if not counted then
          counted = true
          remaining:update(function(x) return x - 1 end)
          dock:drop(key)
        end
      end))

      wait_seconds(spawn_interval)
    end
    done_spawning:set(true)
  end)

  s:effect(function(s2)
    if s2:d(done_spawning) and s2:d(remaining) == 0 then
      local defeated = director.wave:now()
      director.wave:set({
        number = defeated.number + 1,
        front = "None",
        starts_in = math.ceil(config.lull_duration),
      })
      director.wave_defeated:invoke(defeated)
    end
  end)
end

return WaveCycle
