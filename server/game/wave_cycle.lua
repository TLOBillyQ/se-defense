-- 05_BaseDefence 波次每拍逻辑（规则真源 docs/gdd/07-enemies-waves.md W1–W10）。
--
-- WaveDirector（server/game/wave_director）持有状态与编排接缝；本文件实现
-- 每拍推进与生成决策：
--   W2 平静期倒计时（浮点递减，≤ reveal_at 公布方向；归零当拍即生成首只）
--   W3 预算 = 2 + (N−1)；W6/W8 生成扣预算，剩余 > 0 就继续，最后一只可超支
--   W4 生成间隔 = max(0.25, 1 − 0.1(N−1))
--   W5 层级上限按波号（4 波解锁 2 型、8 波解锁 3 型），再按剩余预算降档
--   W7 从所选边界外 6 单位生成，航线指向「棋盘中心 ± 10」区域内一随机点
--   W9 生成完毕且全灭 → 波号 +1、方向未知、倒计时重置
--
-- 随机抽取都经 director.rng01（编排可固定：固定最大值时层级取上限、
-- 另一轴取棋盘边、方向取表尾即北）。

local World = require("server.game.world_data")

local WaveCycle = {}

local EPS = 1e-9

-- 随机整数 lo..hi（含两端），经 rng01；固定最大值时取 hi。
function WaveCycle.randi(director, lo, hi)
  local r = director.rng01()
  return math.min(hi, lo + math.floor(r * (hi - lo + 1)))
end

-- 随机实数 lo..hi；固定最大值时取 hi。
local function randf(director, lo, hi)
  return lo + director.rng01() * (hi - lo)
end

-- W3：预算 = 2 + (N − 1)。
local function budget_for(number)
  return World.wave.budget_base + (number - 1)
end

-- W4：生成间隔 = max(0.25, 1 − 0.1(N−1))。
local function interval_for(number)
  local w = World.wave
  return math.max(w.interval_min, w.interval_base - w.interval_step * (number - 1))
end

-- W5：层级上限（按波号），再按剩余预算降档。
local function tier_cap(number, budget_left)
  local w = World.wave
  local cap = number >= w.tier3_wave and 3 or number >= w.tier2_wave and 2 or 1
  if budget_left < w.tier3_budget then cap = math.min(cap, 2) end
  if budget_left < w.tier2_budget then cap = math.min(cap, 1) end
  return cap
end

-- 新一波的初始状态（W1/W2/W9：波号 N、倒计时 30、方向未知、预算 fresh）。
-- 方向在平静期开始即选定（countdown ≤ 5 才公布）。
function WaveCycle.fresh_wave(director, number)
  return {
    number = number,
    countdown = World.wave.calm,
    starts_in = math.ceil(World.wave.calm),
    assault = false,
    direction = WaveCycle.randi(director, 1, #World.directions),
    front = "None",
    budget_left = budget_for(number),
    spawned = 0,
    since_spawn = 0,
    spawn_done = false,
    spawn_log = {},
    cost_sum = 0,
  }
end

-- W7 + E2：生成点与航线。从所选边界外 6 单位生成，另一轴在棋盘范围内随机；
-- 航线指向「棋盘中心 ± 10」区域内一随机点。
local function spawn_spec(director)
  local w = director.wave:now()
  local dir = World.directions[w.direction]
  local edge = World.board.max + World.wave.spawn_offboard
  local along = randf(director, World.board.min, World.board.max)
  local x, z
  if dir.x ~= 0 then
    x, z = dir.x * edge, along
  else
    x, z = along, dir.z * edge
  end
  local spread = World.wave.route_spread
  local tx, tz = randf(director, -spread, spread), randf(director, -spread, spread)
  local d = World.dist(x, z, tx, tz)
  return {
    x = x, z = z,
    tier = WaveCycle.randi(director, 1, tier_cap(w.number, w.budget_left)),
    heading = { x = (tx - x) / d, z = (tz - z) / d },
  }
end

-- W6/W8：生成一个敌人，扣预算，预算耗尽即停；首只起进入进攻期。
-- 层级计入 spawn_log（与编排生成同一序列），成本计入 cost_sum（编排生成不计）。
-- 注意：先算好全部增量再一次性 set，不能先 _register 再按旧 w 覆盖（会把
-- spawn_log 写回旧值）。
local function spawn_one(director)
  local w = director.wave:now()
  local spec = spawn_spec(director)
  local cost = World.enemy_tiers[spec.tier].cost
  local budget_left = w.budget_left - cost
  local log = { table.unpack(w.spawn_log) }
  log[#log + 1] = spec.tier
  local handle = director._config.spawn_enemy(spec)
  director._handles[#director._handles + 1] = handle
  director.wave:set(World.wave_merge(w, {
    spawned = w.spawned + 1,
    spawn_log = log,
    cost_sum = w.cost_sum + cost,
    budget_left = budget_left,
    since_spawn = 0,
    spawn_done = budget_left <= 0,
    assault = true,
  }))
end

-- 每拍：先判全灭推进（W9），再走倒计时（W2）与生成（W4/W6）。
function WaveCycle.tick(director, dt)
  local w = director.wave:now()

  -- W9：生成完毕且全灭 → 下一波（残敌不清则不推进）。转换拍不落.return：
  -- 新一波的倒计时从同一拍开始走（feature：全灭后推进 1 秒 → 倒计时 29）。
  if w.countdown <= 0 and w.spawn_done and not director:any_alive() then
    local defeated = w
    director._handles = {}
    w = WaveCycle.fresh_wave(director, w.number + 1)
    director.wave:set(w)
    director.wave_defeated:invoke(defeated)
  end

  -- W2：平静期倒计时；≤5 秒公布来袭方向（front 兼容旧显示消费方）。
  if w.countdown > 0 then
    local countdown = math.max(0, w.countdown - dt)
    local front = w.front
    if countdown <= World.wave.reveal_at then
      front = World.directions[w.direction].eng
    end
    director.wave:set(World.wave_merge(w, {
      countdown = countdown,
      starts_in = math.ceil(countdown),
      front = front,
    }))
    w = director.wave:now()
  end
  if w.countdown > 0 or w.spawn_done then return end

  -- 首只立即生成（归零当拍）；之后按间隔。
  if w.spawned == 0 then
    if not w.assault then
      director.wave_started:invoke(w)
    end
    spawn_one(director)
    return
  end
  w = director.wave:now()
  local since = w.since_spawn + dt
  director.wave:set(World.wave_merge(w, { since_spawn = since }))
  -- 宿主固定步长 1/30 远小于最小间隔 0.25，每拍至多生成一只。
  if since >= interval_for(w.number) - EPS then
    spawn_one(director)
  end
end

return WaveCycle
