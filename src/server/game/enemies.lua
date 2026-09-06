-- src/server/game/enemies.lua — 敌人（规则真源 docs/gdd/07-enemies-waves.md
-- E1–E7）。持有一局里生成过的全部敌人（死亡不出表，保证「第 N 个敌人」
-- 序号稳定）与飞行中的炸弹。每拍：按评分重选目标（E3）→ 直飞至 1.2 停
-- （E1/E4）→ 停稳后每 1 秒在目标位置投弹 → 引信 0.3 秒后结算半径伤害
-- （E5，矿点免伤）。波次节奏（何时生成）归 server.game.waves。
-- 纯 Lua、无宿主依赖；是否推进由 match_flow 决定（01 R3）。
local world = require("server.game.world")

local M = {}

local EPS = 1e-9

function M.new()
  return { list = {}, bombs = {} }
end

-- E3：目标评分 = 偏离航线（过出生点沿航线方向的直线）的垂直距离
-- + 0.5 × 到建筑的直线距离，取最小；只评有血量的存活建筑。
local function score(e, b)
  local dx, dz = b.x - e.x, b.z - e.z
  local dev = math.abs(e.route.x * dz - e.route.z * dx) -- 单位法向投影
  return dev + 0.5 * math.sqrt(dx * dx + dz * dz)
end

local function pick_target(match, e)
  local best, best_s
  for _, b in ipairs(match.entities.list) do
    if b.health and b.state == "alive" then
      local s = score(e, b)
      if not best_s or s < best_s then best, best_s = b, s end
    end
  end
  return best
end

-- 生成一个敌人并计入本波（波次自动生成与编排生成同一序列）。
-- spec = { x, z, tier, heading = {x, z}（单位向量） }。
function M.spawn(match, spec)
  local stats = world.enemy_tiers[spec.tier]
  local e = {
    id = #match.enemies.list + 1,
    tier = spec.tier,
    x = spec.x,
    z = spec.z,
    health = stats.health,
    footprint = stats.footprint,
    route = { x = spec.heading.x, z = spec.heading.z }, -- E2 出生航线（固定）
    target = nil,
    stopped = false,
    bomb_left = world.bomb_interval, -- 停稳后 1 秒首弹
    alive = true,
    revealed = false,
  }
  match.enemies.list[#match.enemies.list + 1] = e
  match.wave.spawn_log[#match.wave.spawn_log + 1] = spec.tier
  e.target = pick_target(match, e)
  return e
end

-- 编排/规则共用的致死：死亡无奖励（E7），立即不可被选为目标。
function M.kill(e)
  if not e or not e.alive then return end
  e.health = 0
  e.alive = false
end

-- E1/E4：直飞目标至距离 1.2 停下；越过停点当拍收敛到恰好 1.2 处。
local function move(e, dt)
  if not e.target then return end
  local d = world.dist(e.x, e.z, e.target.x, e.target.z)
  if d <= world.enemy_stop_distance + EPS then
    e.stopped = true
    return
  end
  local step = math.min(world.enemy_speed * dt, d - world.enemy_stop_distance)
  e.x = e.x + (e.target.x - e.x) / d * step
  e.z = e.z + (e.target.z - e.z) / d * step
  if step < world.enemy_speed * dt - EPS then e.stopped = true end
end

-- E4：停稳后每 1 秒在目标位置投一枚炸弹。
local function drop_bombs(match, e, dt)
  if not e.stopped or not e.target then return end
  e.bomb_left = e.bomb_left - dt
  if e.bomb_left <= EPS then
    match.enemies.bombs[#match.enemies.bombs + 1] =
      { x = e.target.x, z = e.target.z, fuse = world.bomb_fuse }
    e.bomb_left = e.bomb_left + world.bomb_interval
  end
end

-- E5：引信 0.3 秒后对半径 1.2 内所有有血量的建筑造成 0.5 伤害（矿点免伤）。
local function settle_bombs(match, dt)
  local bombs = match.enemies.bombs
  local left = {}
  for _, b in ipairs(bombs) do
    b.fuse = b.fuse - dt
    if b.fuse <= EPS then
      for _, t in ipairs(match.entities.list) do
        if t.health and world.dist(b.x, b.z, t.x, t.z) <= world.bomb_radius + EPS then
          match.entities:hurt(t, world.bomb_damage)
        end
      end
    else
      left[#left + 1] = b
    end
  end
  match.enemies.bombs = left
end

function M.tick(match, dt)
  for _, e in ipairs(match.enemies.list) do
    if e.alive then
      local target = pick_target(match, e)
      if target ~= e.target then -- E3：目标离场或评分易主即重选
        e.target = target
        e.stopped = false
        e.bomb_left = world.bomb_interval
      end
      if e.stopped then drop_bombs(match, e, dt) else move(e, dt) end
    end
  end
  settle_bombs(match, dt)
end

return M
