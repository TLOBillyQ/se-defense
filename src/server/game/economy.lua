-- src/server/game/economy.lua — 经济与矿点（规则真源 docs/gdd/02-economy.md）。
-- 采集条件：矿点自身通电（电网判定）且当前不在进攻期（R2）；满足时每
-- 0.8 秒剩余量 −1、资金 +1（R3）；进攻期开始即全图停采，全灭后恢复（R4，
-- 计时器在停采期间冻结不清零）；剩余量到 0 矿点直接离场（R5）；
-- 采集速率 = 正在采集的矿点数 × 1.25/s（R6）。资金账目在 match_flow
-- （R7：只增于采集、只减于放置），本模块只做采集侧。
local world = require("server.game.world")

local M = {}

local Economy = {}
Economy.__index = Economy

local EPS = 1e-9

-- 绑定一局对局：读 match.entities / match.grid / match.wave，写 match.money。
function M.new(match)
  return setmetatable({ match = match, timers = {} }, Economy)
end

-- 正在采集的矿点：通电且非进攻期（R2）。
function Economy:_harvesting()
  local out = {}
  if self.match.wave.assault then return out end
  for _, e in ipairs(self.match.entities.list) do
    if e.kind == "Site" and self.match.grid:powered(e) then out[#out + 1] = e end
  end
  return out
end

function Economy:tick(dt)
  if self.match.wave.assault then return end -- R4：停采，计时器冻结
  local gone = {}
  for _, site in ipairs(self:_harvesting()) do
    local t = (self.timers[site.id] or 0) + dt
    while t >= world.harvest_interval - EPS do
      site.remaining = site.remaining - 1
      self.match.money = self.match.money + 1
      t = t - world.harvest_interval
      if site.remaining <= 0 then -- R5：采空直接离场
        gone[#gone + 1] = site
        t = 0
        break
      end
    end
    self.timers[site.id] = t
  end
  for _, site in ipairs(gone) do
    self.timers[site.id] = nil
    self.match.entities:remove(site)
  end
end

-- 采集速率 = 当前正在采集的矿点数 × 1.25/s（R6）。
function Economy:rate()
  return #self:_harvesting() * world.harvest_rate
end

return M
