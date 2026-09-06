-- src/server/game/waves.lua — 波次节奏（规则真源 docs/gdd/07-enemies-waves.md
-- W1–W10）。持有波次状态（波号 / 倒计时 / 进攻期 / 方向 / 预算 / 生成簿记），
-- 驱动：平静期倒计时 → 归零生成（首个立即，之后按间隔）→ 预算耗尽停 →
-- 全灭后进入下一波。状态表就是 match.wave（经济与步骤层都直接读它）。
-- 敌人生成归 server.game.enemies，本模块只决定何时生成、生成什么层级、
-- 从哪条边界生成；随机抽取都经 match.rng01（编排可固定）。
local world = require("server.game.world")
local enemies = require("server.game.enemies")

local M = {}

local EPS = 1e-9

-- 随机整数 lo..hi（含两端），经 match.rng01；固定最大值时取 hi。
local function randi(match, lo, hi)
  local r = match.rng01()
  return math.min(hi, lo + math.floor(r * (hi - lo + 1)))
end

-- 随机实数 lo..hi；固定最大值时取 hi。
local function randf(match, lo, hi)
  return lo + match.rng01() * (hi - lo)
end

-- W3：预算 = 2 + (N − 1)。
local function budget_for(number)
  return world.wave.budget_base + (number - 1)
end

-- W4：生成间隔 = max(0.25, 1 − 0.1(N−1))。
local function interval_for(number)
  local w = world.wave
  return math.max(w.interval_min, w.interval_base - w.interval_step * (number - 1))
end

-- W5：层级上限（按波号），再按剩余预算降档。
local function tier_cap(number, budget_left)
  local w = world.wave
  local cap = number >= w.tier3_wave and 3 or number >= w.tier2_wave and 2 or 1
  if budget_left < w.tier3_budget then cap = math.min(cap, 2) end
  if budget_left < w.tier2_budget then cap = math.min(cap, 1) end
  return cap
end

-- 新一波的初始状态（W1/W2/W9：波号 N、倒计时 30、方向未知、预算 fresh）。
local function fresh_wave(match, number)
  return {
    number = number,
    countdown = world.wave.calm,
    assault = false,
    direction = randi(match, 1, #world.directions), -- 平静期开始即选定，≤5 秒才公布
    budget_left = budget_for(number),
    spawned = 0,        -- 本波自动生成数
    since_spawn = 0,    -- 距上次自动生成
    spawn_done = false, -- 预算耗尽
    spawn_log = {},     -- 本波全部生成（含编排）的层级序列
    cost_sum = 0,       -- 本波自动生成成本总和
  }
end

function M.initial(match)
  return fresh_wave(match, 1)
end

-- 编排接缝：波号置 N、倒计时 30、方向未知（feature 约定）。
function M.set_wave(match, number)
  match.wave = fresh_wave(match, number)
end

-- 编排接缝：平静期尚未推进（倒计时满、未生成、非进攻期）时按当前随机源
-- 重抽来袭方向，供「随机源固定为最大值」之类的编排在新对局开局生效。
function M.reroll_direction(match)
  local w = match.wave
  if w.countdown < world.wave.calm or w.assault or w.spawned > 0 then return end
  w.direction = randi(match, 1, #world.directions)
end

-- W2：倒计时 ≤ 5 公布方向，否则未知。
function M.revealed_direction(match)
  local w = match.wave
  if w.countdown > world.wave.reveal_at then return nil end
  return world.directions[w.direction].name
end

-- W7 + E2：从所选边界外 6 单位生成，另一轴在棋盘范围内随机；
-- 航线指向「棋盘中心 ± 10」区域内一随机点。
local function spawn_spec(match)
  local w = match.wave
  local dir = world.directions[w.direction]
  local edge = world.board.max + world.wave.spawn_offboard
  local along = randf(match, world.board.min, world.board.max)
  local x, z
  if dir.x ~= 0 then
    x, z = dir.x * edge, along
  else
    x, z = along, dir.z * edge
  end
  local spread = world.wave.route_spread
  local tx, tz = randf(match, -spread, spread), randf(match, -spread, spread)
  local d = world.dist(x, z, tx, tz)
  return {
    x = x, z = z, tier = randi(match, 1, tier_cap(w.number, w.budget_left)),
    heading = { x = (tx - x) / d, z = (tz - z) / d },
  }
end

-- W6/W8：生成一个敌人，扣预算，预算耗尽即停；首生起进入进攻期。
local function spawn_one(match)
  local w = match.wave
  local spec = spawn_spec(match)
  enemies.spawn(match, spec)
  w.spawned = w.spawned + 1
  w.cost_sum = w.cost_sum + world.enemy_tiers[spec.tier].cost
  w.budget_left = w.budget_left - world.enemy_tiers[spec.tier].cost
  w.since_spawn = 0
  if w.budget_left <= 0 then w.spawn_done = true end
  w.assault = true
end

-- 每拍：先判全灭推进（W9），再走倒计时（W2）与生成（W4/W6）。
function M.tick(match, dt)
  local w = match.wave
  -- W9：生成完毕且全灭 → 波号 +1、方向未知、倒计时重置（残敌不清则不推进）。
  if w.countdown <= 0 and w.spawn_done and not enemies.any_alive(match) then
    match.wave = fresh_wave(match, w.number + 1)
    w = match.wave
  end
  -- W2/W10：平静期倒计时（归零当拍即生成第一个）。
  if w.countdown > 0 then
    w.countdown = math.max(0, w.countdown - dt)
  end
  if w.countdown > 0 or w.spawn_done then return end
  if w.spawned == 0 then
    spawn_one(match)
    return
  end
  w.since_spawn = w.since_spawn + dt
  -- 宿主固定步长 1/30 远小于最小间隔 0.25，每拍至多生成一个。
  if w.since_spawn >= interval_for(w.number) - EPS and not w.spawn_done then
    spawn_one(match)
  end
end

return M
