-- src/server/game/repair.lua — 维修（规则真源 docs/gdd/06-repair.md R1–R7）。
-- 每座通电 Repair 在维修圈（5）内选一个血量比例最低且 < 1 的存活建筑
-- （排除自身，矿点无血量不参与），以 0.5 血/秒修至满血；目标修满、离开
-- 维修圈或离场后重选。目标选择归本模块按实体 id 登记。
local world = require("server.game.world")

local M = {}

local EPS = 1e-9

local Repair = {}
Repair.__index = Repair

function M.new(match)
  return setmetatable({ match = match, targets = {} }, Repair)
end

-- R7：维修圈与目标足迹圆相交（圆心距 ≤ 半径和）。
local function in_circle(repair, b)
  return world.dist(repair.x, repair.z, b.x, b.z)
    <= world.specs.Repair.range + world.specs[b.kind].footprint + EPS
end

local function damaged(b)
  return b.health and b.state == "alive" and b.health < world.specs[b.kind].health - EPS
end

-- R1/R2/R5：圈内血量比例最低的伤员（排除自己）。
function Repair:_acquire(repair)
  local best, best_ratio
  for _, b in ipairs(self.match.entities.list) do
    if b ~= repair and damaged(b) and in_circle(repair, b) then
      local ratio = b.health / world.specs[b.kind].health
      if not best_ratio or ratio < best_ratio then best, best_ratio = b, ratio end
    end
  end
  return best
end

-- R4：目标修满、离开维修圈或离场后重选。
local function valid(repair, target)
  return target and damaged(target) and in_circle(repair, target)
end

function Repair:tick(dt)
  for _, e in ipairs(self.match.entities.list) do
    if e.kind == "Repair" and e.state == "alive" and self.match.grid:powered(e) then -- R6
      local target = self.targets[e.id]
      if not valid(e, target) then
        target = self:_acquire(e)
        self.targets[e.id] = target
      end
      if target then -- R3：0.5 血/秒，不超过上限
        local cap = world.specs[target.kind].health
        target.health = math.min(cap, target.health + world.repair_rate * dt)
      end
    end
  end
end

return M
