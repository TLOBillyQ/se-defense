-- server/match/roster.lua — 场上名册查询（组合根之上的只读领域问题）。
--
-- 回答「谁在场」这一类问题：按坐标找矿点、按类型/坐标找建筑、某类型是否
-- 在场、场上建筑数、是否有碎裂中的建筑、存活敌人。GM 面（server/gm.lua）、
-- 无头 harness（tools/acceptance/headless.lua）与真机集成脚本都从这里取答案，
-- 不各自翻 pool / game_state 重做。
--
-- 约定：
--   - Core 住在 game_state.core（Core 组件，.building 为 Building 组件），
--     其余建筑住在 pool live 记录（rec.epoch.building）。
--   - 「在场」= 未离场；死亡后碎裂期内仍在场（GDD 15 F3）。
--   - 坐标匹配用 EPS 容差（编排坐标与实体坐标同源，不做近似查找）。

local M = {}

M.EPS = 1e-6

local function pos_eq(p, x, z)
  return p ~= nil and math.abs(p.x - x) < M.EPS and math.abs(p.z - z) < M.EPS
end

local function pool_of(root)
  return root and root.pool
end

-- 类型名规范化：feature / GM 传 "Turret"，spec.key 为小写。
function M.key_of(kind)
  return string.lower(tostring(kind))
end

-- 按坐标取矿点（Resource 组件）；没有返回 nil。
function M.site_at(root, x, z)
  for _, r in ipairs(root.resources or {}) do
    if pos_eq(r.entity.position, x, z) then return r end
  end
  return nil
end

-- Core 组件（无论存活）；未建返回 nil。
function M.core(root)
  return root.game_state and root.game_state.core or nil
end

-- 遍历 pool 内 live 建筑：fn(building, rec)，返回真值即中止并返回该对。
function M.each_building(root, fn)
  local pool = pool_of(root)
  if not pool then return nil end
  local hit_b
  local hit = pool:each_live(function(rec)
    local b = rec.epoch and rec.epoch.building
    if b and fn(b, rec) then
      hit_b = b
      return true
    end
    return false
  end)
  if hit then return hit_b, hit end
  return nil
end

-- 按类型 + 坐标找建筑。Core 返回 (Core 组件, nil)，其余返回 (Building, rec)。
-- alive_only 为真时要求存活（Core 走 health.is_alive）。
function M.building_at(root, kind, x, z, alive_only)
  if kind == "Core" then
    local core = M.core(root)
    if core and pos_eq(core.entity.position, x, z)
      and (not alive_only or core.health.is_alive:now()) then
      return core, nil
    end
    return nil
  end
  local key = M.key_of(kind)
  return M.each_building(root, function(b, rec)
    return rec.spec and rec.spec.key == key and pos_eq(rec.entity.position, x, z)
      and (not alive_only or b.health.is_alive:now())
  end)
end

-- 某类型第一个存活建筑（非 Core）；用于「X 死亡」编排。
function M.first_alive(root, kind)
  local key = M.key_of(kind)
  return M.each_building(root, function(b, rec)
    return rec.spec and rec.spec.key == key and b.health.is_alive:now()
  end)
end

-- 某类型是否在场（碎裂中算在场）。
function M.building_present(root, kind)
  if kind == "Core" then
    local core = M.core(root)
    return core ~= nil and core.building ~= nil and not core.building.departed:now()
  end
  local key = M.key_of(kind)
  return M.each_building(root, function(_, rec)
    return rec.spec and rec.spec.key == key
  end) ~= nil
end

-- 场上建筑数 = Core（在场时）+ pool live 建筑数。
function M.building_count(root)
  local n = M.building_present(root, "Core") and 1 or 0
  local pool = pool_of(root)
  return n + (pool and pool:live_count() or 0)
end

-- 某类型是否有「已死亡但未离场」的建筑（碎裂中，GDD 15 F3）。
function M.crumbling(root, kind)
  local function is_crumbling(b)
    return b ~= nil and not b.health.is_alive:now() and not b.departed:now()
  end
  if kind == "Core" then
    local core = M.core(root)
    return is_crumbling(core and core.building)
  end
  local key = M.key_of(kind)
  return M.each_building(root, function(b, rec)
    return rec.spec and rec.spec.key == key and is_crumbling(b)
  end) ~= nil
end

-- 存活敌人列表（按 root.enemies 序）。
function M.alive_enemies(root)
  local out = {}
  for _, en in ipairs(root.enemies or {}) do
    if en.health and en.health.is_alive:now() then out[#out + 1] = en end
  end
  return out
end

return M
