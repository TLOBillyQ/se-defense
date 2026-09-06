-- src/server/game/entities.lua — 场上实体登记（规则真源 docs/gdd/00-world.md、
-- docs/gdd/README.md「已知的移植差异」）。
-- 持有一局里在场的全部实体（建筑 + 矿点）及其离场生命周期：建筑死亡后碎裂
-- 2 秒离场，矿点采空直接离场。纯 Lua、无宿主依赖，不知道对局阶段——
-- 是否推进碎裂由 match_flow 决定（R3 时间冻结）。
-- 后续系统（经济、放置、电网、火力）都从这里读写实体，不另建登记表。
local world = require("server.game.world")

local M = {}

local EPS = 1e-9

local Registry = {}
Registry.__index = Registry

local function new_building(id, kind, x, z)
  return {
    id = id,
    kind = kind,
    x = x,
    z = z,
    health = world.specs[kind].health,
    state = "alive", -- alive | crumbling（碎裂中，仍在场）
    crumble_left = 0,
    hits = 0,        -- 累计受击次数（只增；表现层据差分做受击红闪）
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

-- 初始布局：Core + 27 矿点。
function M.new()
  local r = setmetatable({ list = {}, _next_id = 0 }, Registry)
  r:_append(function(id) return new_building(id, "Core", world.core.x, world.core.z) end)
  for _, pos in ipairs(world.sites) do
    r:_append(function(id) return new_site(id, pos) end)
  end
  return r
end

function Registry:_append(make)
  self._next_id = self._next_id + 1
  local e = make(self._next_id)
  self.list[#self.list + 1] = e
  return e
end

function Registry:_remove(entity)
  for i, e in ipairs(self.list) do
    if e == entity then
      table.remove(self.list, i)
      return
    end
  end
end

-- ── 变更 ──────────────────────────────────────────────────────────────────

-- 编排：令实体直接离场（摧毁 / 矿点采空），不经碎裂。
function Registry:remove(entity)
  if entity then self:_remove(entity) end
end

-- 按类型与坐标找在场实体（含碎裂中），坐标近似匹配。
-- 实体是否仍在场（引用比较；采空/拆除/碎裂完毕即不在）。
function Registry:has(entity)
  for _, e in ipairs(self.list) do
    if e == entity then return true end
  end
  return false
end

-- 落点命中：足迹圆包含 (x,z) 的实体中取最近者（14 V1 悬停；半径 0 落点）。
function Registry:pick(x, z)
  local best, best_d
  for _, e in ipairs(self.list) do
    local d = world.dist(x, z, e.x, e.z)
    if d <= world.specs[e.kind].footprint + EPS and (not best_d or d < best_d) then
      best, best_d = e, d
    end
  end
  return best
end

-- 某类建筑是否有正在碎裂的（碎裂 2 秒仍占位）。
function Registry:crumbling(kind)
  for _, e in ipairs(self.list) do
    if e.kind == kind and e.state == "crumbling" then return true end
  end
  return false
end

function Registry:find(kind, x, z)
  for _, e in ipairs(self.list) do
    if e.kind == kind and math.abs(e.x - x) < 1e-9 and math.abs(e.z - z) < 1e-9 then
      return e
    end
  end
  return nil
end

-- 炸弹伤害：血量归零后碎裂（矿点无血量，不受伤害）。每次受击 hits +1
-- （15 F2 受击红闪按计数差分检测——伤害可能落在两拍之间，靠血量差分
-- 检测不到被维修抵消的受击；计数只增，表现层不必回写规则层）。
function Registry:hurt(entity, amount)
  if not entity or not entity.health or entity.state ~= "alive" then return end
  entity.health = entity.health - amount
  entity.hits = entity.hits + 1
  if entity.health <= 0 then
    entity.health = 0
    entity.state = "crumbling"
    entity.crumble_left = world.crumble_seconds
  end
end

-- 直接造好一座建筑（不扣费、不判合法落点）。
function Registry:add_building(kind, x, z)
  assert(world.specs[kind] and world.specs[kind].health, "未知建筑: " .. tostring(kind))
  return self:_append(function(id) return new_building(id, kind, x, z) end)
end

-- 令指定类型的第一座活建筑死亡（血量归零 → 碎裂 2 秒后离场）。
function Registry:kill(kind)
  for _, e in ipairs(self.list) do
    if e.kind == kind and e.state == "alive" then
      self:hurt(e, e.health)
      return e
    end
  end
  return nil
end

-- 采空前 n 个在场矿点（剩余量归零 → 直接离场）。
function Registry:deplete_sites(n)
  local left = n
  local gone = {}
  for _, e in ipairs(self.list) do
    if left == 0 then break end
    if e.kind == "Site" then
      e.remaining = 0
      gone[#gone + 1] = e
      left = left - 1
    end
  end
  for _, e in ipairs(gone) do self:_remove(e) end
end

-- 推进碎裂计时 dt 秒，碎裂完成的建筑离场。
function Registry:tick_crumble(dt)
  local gone = {}
  for _, e in ipairs(self.list) do
    if e.state == "crumbling" then
      e.crumble_left = e.crumble_left - dt
      if e.crumble_left <= 0 then gone[#gone + 1] = e end
    end
  end
  for _, e in ipairs(gone) do self:_remove(e) end
end

-- ── 读取 ──────────────────────────────────────────────────────────────────

-- 某类型的全部在场存活实体（不含碎裂中；通电判定归电网）。
function Registry:alive_of_kind(kind)
  local out = {}
  for _, e in ipairs(self.list) do
    if e.kind == kind and e.state == "alive" then out[#out + 1] = e end
  end
  return out
end

-- 在场 = 实体仍在场上（含碎裂中）。
function Registry:present(kind)
  for _, e in ipairs(self.list) do
    if e.kind == kind then return true end
  end
  return false
end

-- 场上建筑数（不含矿点，含碎裂中）。
function Registry:count_buildings()
  return #self.list - self:count_sites()
end

-- 剩余矿点数。
function Registry:count_sites()
  local n = 0
  for _, e in ipairs(self.list) do
    if e.kind == "Site" then n = n + 1 end
  end
  return n
end

return M
