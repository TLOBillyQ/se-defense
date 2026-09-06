-- src/server/game/match_flow.lua — 对局流程规则层（规则真源 docs/gdd/01-match-flow.md）。
-- 四态状态机（Pregame / Playing / Victory / GameOver），只有 Playing 推进 dt；
-- 最小波次状态（波号 / 倒计时 / 进攻期标志）、胜负判定与重开。
-- 场上实体与离场生命周期归 server.game.entities，电网归 server.game.power_grid，
-- 采集归 server.game.economy，放置归 server.game.placement；本模块持四态状态机、
-- 资金账目、波次状态与胜负判定。纯 Lua、无宿主依赖；宿主固定步长由
-- server.adapter.host 驱动。
--
-- 玩家意图：start / restart / select / confirm / cancel / place（复合放置）。
-- 编排接缝（无头 harness 与后续系统用）走 game.entities / game.grid / game.economy。
local world = require("server.game.world")
local entities = require("server.game.entities")
local power_grid = require("server.game.power_grid")
local economy = require("server.game.economy")
local placement = require("server.game.placement")
local waves = require("server.game.waves")
local enemies = require("server.game.enemies")
local detection = require("server.game.detection")
local fire = require("server.game.fire")
local repair = require("server.game.repair")

local M = {}

local Game = {}
Game.__index = Game

function M.new()
  local g = setmetatable({
    mode = "Pregame",
    money = 0, -- R2：进入 Playing 的瞬间置起始资金
    entities = entities.new(),
    placing_kind = nil, -- 放置态：当前待建类型（04 R3）
    rng01 = math.random, -- 随机源（编排可固定，如固定为最大值）
  }, Game)
  g.wave = waves.initial(g)
  g.enemies = enemies.new()
  g.grid = power_grid.new(g.entities)
  g.economy = economy.new(g)
  g.fire = fire.new(g)
  g.repair = repair.new(g)
  return g
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
  self.wave = waves.initial(self)
  self.enemies = enemies.new()
  self.entities = entities.new()
  self.placing_kind = nil
  self.grid = power_grid.new(self.entities)
  self.economy = economy.new(self)
  self.fire = fire.new(self)
  self.repair = repair.new(self)
end

-- 放置（04）：Pregame 忽略放置意图（01 R8）；规则判定全归 placement。
function Game:selectable(kind) return placement.selectable(self, kind) end
function Game:placing() return self.placing_kind ~= nil end

function Game:select(kind)
  if self.mode ~= "Playing" then return false end
  return placement.select(self, kind)
end

function Game:confirm(x, z)
  if self.mode ~= "Playing" then return false end
  return placement.confirm(self, x, z)
end

function Game:cancel()
  placement.cancel(self)
end

-- 复合放置 = 选择待建后在落点确认（feature 约定）。一步完成：失败时不留放置态，
-- 后续 select 别的类型不会被 R3 挡住。
function Game:place(kind, x, z)
  if self.mode ~= "Playing" then return end
  if not placement.select(self, kind) then return end
  if not placement.confirm(self, x, z) then placement.cancel(self) end
end

-- ── 节拍 ──────────────────────────────────────────────────────────────────

-- R3：只有 Playing 推进。R4/R5/R6：胜负只在 Playing 判定。
function Game:advance(dt)
  if self.mode ~= "Playing" then return end
  waves.tick(self, dt)
  self.grid:tick(dt)
  enemies.tick(self, dt)
  detection.tick(self)
  self.fire:tick(dt)
  self.repair:tick(dt)
  self.economy:tick(dt)
  self.entities:tick_crumble(dt)
  if self.entities:count_sites() == 0 then
    self.mode = "Victory"
  elseif not self.entities:present("Core") then
    self.mode = "GameOver"
  end
end

return M
