-- src/server/game/match_flow.lua — 对局流程规则层（规则真源 docs/gdd/01-match-flow.md）。
-- 四态状态机（Pregame / Playing / Victory / GameOver），只有 Playing 推进 dt；
-- 最小波次状态（波号 / 倒计时 / 进攻期标志）、胜负判定与重开。
-- 场上实体与离场生命周期归 server.game.entities，本模块只问它「剩余矿点数」
-- 与「Core 是否在场」。纯 Lua、无宿主依赖；宿主固定步长由 server.adapter.host 驱动。
--
-- 玩家意图：start / restart / place（R8：Pregame 忽略放置）。
-- 编排接缝（无头 harness 与后续系统用）走 game.entities。
local world = require("server.game.world")
local entities = require("server.game.entities")

local M = {}

local Game = {}
Game.__index = Game

local function initial_wave()
  return { number = 1, countdown = world.first_wave_countdown, assault = false }
end

function M.new()
  return setmetatable({
    mode = "Pregame",
    money = 0, -- R2：进入 Playing 的瞬间置起始资金
    wave = initial_wave(),
    entities = entities.new(),
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
  self.mode = "Pregame"
  self.money = 0
  self.wave = initial_wave()
  self.entities = entities.new()
end

-- R8 + 最小放置：Pregame 忽略；Playing 中资金够则建造并扣费。
-- 合法落点判定归放置系统（docs/gdd/04-placement.md），本模块不实现。
function Game:place(kind, x, z)
  if self.mode ~= "Playing" then return end
  local spec = world.specs[kind]
  if not spec or not spec.price then return end
  if self.money < spec.price then return end
  self.money = self.money - spec.price
  self.entities:add_building(kind, x, z)
end

-- ── 节拍 ──────────────────────────────────────────────────────────────────

-- R3：只有 Playing 推进。R4/R5/R6：胜负只在 Playing 判定。
function Game:advance(dt)
  if self.mode ~= "Playing" then return end
  self.wave.countdown = math.max(0, self.wave.countdown - dt)
  self.entities:tick_crumble(dt)
  if self.entities:count_sites() == 0 then
    self.mode = "Victory"
  elseif not self.entities:present("Core") then
    self.mode = "GameOver"
  end
end

return M
