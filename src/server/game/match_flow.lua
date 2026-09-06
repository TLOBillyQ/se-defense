-- src/server/game/match_flow.lua — 对局流程规则层（规则真源 docs/gdd/01-match-flow.md）。
-- 四态状态机（Pregame / Playing / Victory / GameOver），只有 Playing 推进 dt；
-- 最小波次状态（波号 / 倒计时 / 进攻期标志）、建筑血量与 2 秒碎裂离场、
-- 矿点采空直接离场、胜负判定与重开。纯 Lua、无宿主依赖；宿主固定步长由
-- server.adapter.host 驱动。
--
-- 对局对象方法分两组：
--   玩家意图：start / restart / place（R8：Pregame 忽略放置）
--   编排接缝（无头 harness 与后续系统用）：kill / deplete_sites / add_building
local world = require("server.game.world")

local M = {}

local Game = {}
Game.__index = Game

local function new_building(id, kind, x, z)
  return {
    id = id,
    kind = kind,
    x = x,
    z = z,
    health = world.specs[kind].health,
    state = "alive", -- alive | crumbling（碎裂中，仍在场）
    crumble_left = 0,
  }
end

local function new_site(id, pos)
  return {
    id = id,
    kind = "Site",
    x = pos.x,
    z = pos.z,
    remaining = pos.remaining or world.site_remaining,
  }
end

-- 初始布局：Core + 27 矿点（R7 重开也走这里）。
local function build_initial_entities()
  local entities, next_id = {}, 0
  next_id = next_id + 1
  entities[#entities + 1] = new_building(next_id, "Core", world.core.x, world.core.z)
  for _, pos in ipairs(world.sites) do
    next_id = next_id + 1
    entities[#entities + 1] = new_site(next_id, pos)
  end
  return entities, next_id
end

function M.new()
  local entities, next_id = build_initial_entities()
  return setmetatable({
    mode = "Pregame",
    money = 0, -- R2：进入 Playing 的瞬间置起始资金
    wave = { number = 1, countdown = world.first_wave_countdown, assault = false },
    entities = entities,
    _next_id = next_id,
  }, Game)
end

-- ── 玩家意图 ──────────────────────────────────────────────────────────────

-- R1/R2：只对 Pregame 有效；进入 Playing 置起始资金。
function Game:start()
  if self.mode ~= "Pregame" then return end
  self.mode = "Playing"
  self.money = world.starting_money
end

-- R7：Victory/GameOver 中重开 → Pregame + 初始布局。
function Game:restart()
  if self.mode ~= "Victory" and self.mode ~= "GameOver" then return end
  local entities, next_id = build_initial_entities()
  self.mode = "Pregame"
  self.money = 0
  self.wave = { number = 1, countdown = world.first_wave_countdown, assault = false }
  self.entities = entities
  self._next_id = next_id
end

-- R8 + 最小放置：Pregame 忽略；Playing 中资金够则建造并扣费。
-- 合法落点判定归放置系统（docs/gdd/04-placement.md），本模块不实现。
function Game:place(kind, x, z)
  if self.mode ~= "Playing" then return end
  local spec = world.specs[kind]
  if not spec or not spec.price then return end
  if self.money < spec.price then return end
  self.money = self.money - spec.price
  self:add_building(kind, x, z)
end

-- ── 节拍 ──────────────────────────────────────────────────────────────────

-- R3：只有 Playing 推进。R4/R5/R6：胜负只在 Playing 判定。
function Game:advance(dt)
  if self.mode ~= "Playing" then return end
  self.wave.countdown = math.max(0, self.wave.countdown - dt)
  self:_tick_crumble(dt)
  if self:count_sites() == 0 then
    self.mode = "Victory"
  elseif not self:present("Core") then
    self.mode = "GameOver"
  end
end

function Game:_tick_crumble(dt)
  local gone = {}
  for _, e in ipairs(self.entities) do
    if e.state == "crumbling" then
      e.crumble_left = e.crumble_left - dt
      if e.crumble_left <= 0 then gone[#gone + 1] = e end
    end
  end
  for _, e in ipairs(gone) do self:_remove(e) end
end

function Game:_remove(entity)
  for i, e in ipairs(self.entities) do
    if e == entity then
      table.remove(self.entities, i)
      return
    end
  end
end

-- ── 编排接缝（无头 harness 动作，不走玩家路径与扣费）──────────────────────

-- 直接造好一座建筑。
function Game:add_building(kind, x, z)
  assert(world.specs[kind] and world.specs[kind].health, "未知建筑: " .. tostring(kind))
  self._next_id = self._next_id + 1
  local b = new_building(self._next_id, kind, x, z)
  self.entities[#self.entities + 1] = b
  return b
end

-- 令指定类型的第一座在场建筑死亡（血量归零 → 碎裂 2 秒后离场）。
function Game:kill(kind)
  for _, e in ipairs(self.entities) do
    if e.kind == kind and e.state == "alive" then
      e.health = 0
      e.state = "crumbling"
      e.crumble_left = world.crumble_seconds
      return e
    end
  end
  return nil
end

-- 采空前 n 个在场矿点（剩余量归零 → 直接离场）。
function Game:deplete_sites(n)
  local left = n
  local gone = {}
  for _, e in ipairs(self.entities) do
    if left == 0 then break end
    if e.kind == "Site" then
      e.remaining = 0
      gone[#gone + 1] = e
      left = left - 1
    end
  end
  for _, e in ipairs(gone) do self:_remove(e) end
end

-- ── 读取 ──────────────────────────────────────────────────────────────────

-- 在场 = 实体仍在场上（含碎裂中）。
function Game:present(kind)
  for _, e in ipairs(self.entities) do
    if e.kind == kind then return true end
  end
  return false
end

-- 场上建筑数（不含矿点，含碎裂中）。
function Game:count_buildings()
  local n = 0
  for _, e in ipairs(self.entities) do
    if e.kind ~= "Site" then n = n + 1 end
  end
  return n
end

-- 剩余矿点数。
function Game:count_sites()
  local n = 0
  for _, e in ipairs(self.entities) do
    if e.kind == "Site" then n = n + 1 end
  end
  return n
end

return M
