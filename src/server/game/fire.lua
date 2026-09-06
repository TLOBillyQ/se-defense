-- src/server/game/fire.lua — 火力（规则真源 docs/gdd/05-detection-fire.md
-- R2–R8）。每座通电 Turret：射程圈（5）与敌人足迹圆相交且已揭示者中选
-- 最近目标（R2/R3，目标失去揭示/离开射程/死亡后重选）；枪口以 180°/s
-- 转向目标，夹角 ≤ 2° 才开火（R4）；满足条件即开第一枪，光束 0.05 秒后
-- 结算 0.5 伤害，之后每 0.5 秒一枪（R5）；未通电不开火（R6）；
-- 敌人血量 ≤ 0 即死亡（R7）。枪口朝向存在建筑实体上（muzzle），
-- 冷却与在途光束归本模块按实体 id 登记。
local world = require("server.game.world")
local enemies = require("server.game.enemies")

local M = {}

local EPS = 1e-9

local Fire = {}
Fire.__index = Fire

function M.new(match)
  return setmetatable({ match = match, recs = {} }, Fire)
end

function Fire:_rec(turret)
  local r = self.recs[turret.id]
  if not r then
    r = { target = nil, cooldown = 0, beams = {} }
    self.recs[turret.id] = r
  end
  return r
end

-- 枪口初始朝北（feature 约定：未设定时不做假设之外的默认）。
local function muzzle_of(turret)
  if not turret.muzzle then turret.muzzle = { x = 0, z = 1 } end
  return turret.muzzle
end

local function angle_of(v)
  return math.atan(v.z, v.x)
end

-- 折到 (−π, π] 的最短弧。
local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

-- R2/R3：射程内已揭示存活敌人中最近者。
function Fire:_acquire(turret)
  local best, best_d
  local range = world.specs.Turret.range
  for _, e in ipairs(self.match.enemies.list) do
    if e.alive and e.revealed then
      local d = world.dist(turret.x, turret.z, e.x, e.z)
      if d <= range + e.footprint + EPS and (not best_d or d < best_d) then
        best, best_d = e, d
      end
    end
  end
  return best
end

-- R4：枪口以 180°/s 转向目标；返回是否已对准（夹角 ≤ 2°）。
function Fire:_aim(turret, target, dt)
  local muzzle = muzzle_of(turret)
  local want = math.atan(target.z - turret.z, target.x - turret.x)
  local diff = wrap(want - angle_of(muzzle))
  local step = math.max(-world.turret_turn_rate * dt,
    math.min(world.turret_turn_rate * dt, diff))
  local a = angle_of(muzzle) + step
  muzzle.x, muzzle.z = math.cos(a), math.sin(a)
  return math.abs(wrap(want - a)) <= world.turret_fire_angle
end

-- R5：光束 0.05 秒后结算伤害；目标已死则落空。
local function settle_beams(rec, dt)
  local left = {}
  for _, beam in ipairs(rec.beams) do
    beam.t = beam.t - dt
    if beam.t <= EPS then
      if beam.target.alive then
        beam.target.health = math.max(0, beam.target.health - world.fire_damage)
        if beam.target.health <= 0 then enemies.kill(beam.target) end
      end
    else
      left[#left + 1] = beam
    end
  end
  rec.beams = left
end

function Fire:_tick_turret(turret, dt)
  local rec = self:_rec(turret)
  settle_beams(rec, dt)
  rec.cooldown = rec.cooldown - dt
  -- R3：当前目标失效（死亡/失去揭示/离开射程）后重选。
  local range = world.specs.Turret.range
  local cur = rec.target
  if cur and not (cur.alive and cur.revealed
      and world.dist(turret.x, turret.z, cur.x, cur.z) <= range + cur.footprint + EPS) then
    cur = nil
  end
  rec.target = cur or self:_acquire(turret)
  local target = rec.target
  if not target then return end -- R8：无目标待机
  -- R4：转向目标，夹角 ≤ 2° 才开火。
  if not self:_aim(turret, target, dt) then return end
  -- R5：满足条件即开第一枪，之后每 0.5 秒一枪。
  if rec.cooldown > EPS then return end
  rec.beams[#rec.beams + 1] = { target = target, t = world.fire_beam }
  rec.cooldown = world.fire_interval
end

function Fire:tick(dt)
  for _, e in ipairs(self.match.entities:alive_of_kind("Turret")) do
    local rec = self:_rec(e)
    if self.match.grid:powered(e) then -- R6
      self:_tick_turret(e, dt)
    else
      settle_beams(rec, dt) -- 已出膛的光束照常结算
      rec.target = nil
      rec.cooldown = 0
    end
  end
end

return M
