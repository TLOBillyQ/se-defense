-- src/server/game/entities.lua — 场上实体登记（规则真源 docs/gdd/00-world.md、
-- docs/gdd/README.md「已知的移植差异」）。
-- 持有一局里在场的全部实体（建筑 + 矿点）及其离场生命周期：建筑死亡后碎裂
-- 2 秒离场，矿点采空直接离场。纯 Lua、无宿主依赖，不知道对局阶段——
-- 是否推进碎裂由 match_flow 决定（R3 时间冻结）。
-- 后续系统（经济、放置、电网、火力）都从这里读写实体，不另建登记表。
local world = require("server.game.world")

local M = {}

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

-- 直接造好一座建筑（不扣费、不判合法落点）。
function Registry:add_building(kind, x, z)
  assert(world.specs[kind] and world.specs[kind].health, "未知建筑: " .. tostring(kind))
  return self:_append(function(id) return new_building(id, kind, x, z) end)
end

-- 令指定类型的第一座活建筑死亡（血量归零 → 碎裂 2 秒后离场）。
function Registry:kill(kind)
  for _, e in ipairs(self.list) do
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
