-- src/server/game/power_grid.lua — 电网（规则真源 docs/gdd/03-power-grid.md）。
-- 以 Core 为根的供电树：每节点至多一个供电者（R5）；接入判定为收电圈与
-- 通电供电圈相交，圆心距 ≤ 半径和，相等也算（R2）；供电者只有自身通电
-- （已生效）才对外供电（R3/R10）；抢占只向更近且非下游的通电供电者切换
-- （R6）；供电者离场/失电/不再相交时下游整条分支断电（R7）；通电/断电
-- 变化持续 0.15 秒去抖才生效（R8）。
--
-- 只读 entities 登记表的实体清单，自身维护每个节点的供电者与通电状态。
-- 初始布局在创建时立即收敛（无启动去抖），之后的通断电变化都走去抖。
local world = require("server.game.world")

local M = {}

local Grid = {}
Grid.__index = Grid

local EPS = 1e-9

-- 实体间欧氏距离（world.dist 的实体形参包装）。
local function dist(a, b)
  return world.dist(a.x, a.z, b.x, b.z)
end

-- 供电圈大于零的才是供电者（R1：只有 Core 与 Relay 对外供电）。
local function is_provider(e)
  return (world.specs[e.kind].provide or 0) > 0
end

function M.new(registry)
  local g = setmetatable({ registry = registry, recs = {} }, Grid)
  g:_settle_initial()
  return g
end

function Grid:_rec(e)
  local r = self.recs[e.id]
  if not r then
    r = { entity = e, provider = nil, powered = false, pending_want = nil, pending_t = 0 }
    self.recs[e.id] = r
  end
  return r
end

-- 节点的收电圈与供电者的供电圈相交（圆心距 ≤ 半径和，相等也算）。
function Grid:_in_range(node, provider)
  local provide = world.specs[provider.kind].provide
  local receive = world.specs[node.kind].receive or 0
  return dist(node, provider) <= provide + receive + EPS
end

-- candidate 是否 node 的下游（沿 candidate 的供电链上溯会经过 node）。
function Grid:_downstream_of(candidate, node)
  local cur = candidate
  while cur do
    if cur == node then return true end
    local r = self.recs[cur.id]
    cur = r and r.provider or nil
  end
  return false
end

-- 当前已生效通电的供电者。
function Grid:_powered_providers()
  local out = {}
  for _, e in ipairs(self.registry.list) do
    if is_provider(e) and self:powered(e) then out[#out + 1] = e end
  end
  return out
end

-- 清理已离场实体的记录；alive 为 id → 实体。
function Grid:_prune_gone(alive)
  for id in pairs(self.recs) do
    if not alive[id] then self.recs[id] = nil end
  end
end

-- 供电者离场或不再相交时断开链路；下游断电由 _compute_want 沿链递推（R7）。
function Grid:_break_stale_links(alive)
  for _, e in ipairs(self.registry.list) do
    local rec = self:_rec(e)
    local p = rec.provider
    if p and (not alive[p.id] or not self:_in_range(e, p)) then
      rec.provider = nil
    end
  end
end

-- 候选供电者资格：未接入者皆可接入；已接入者只在更近且非下游时可抢占（R6）。
function Grid:_eligible(rec, e, p, d)
  if not rec.provider then return true end
  return d < dist(e, rec.provider) - EPS and not self:_downstream_of(p, e)
end

-- 接入与抢占：每个非 Core 节点取最近的合格通电供电者。
function Grid:_relink(providers)
  for _, e in ipairs(self.registry.list) do
    if e.kind ~= "Core" then
      local rec = self.recs[e.id]
      local best, best_d
      for _, p in ipairs(providers) do
        if p ~= e and self:_in_range(e, p) then
          local d = dist(e, p)
          if self:_eligible(rec, e, p, d) and (not best_d or d < best_d) then
            best, best_d = p, d
          end
        end
      end
      if best then rec.provider = best end
    end
  end
end

-- 链路维护：清离场、失效断开、接入与抢占（R6）。
function Grid:_reconcile_links()
  local alive = {}
  for _, e in ipairs(self.registry.list) do alive[e.id] = e end
  self:_prune_gone(alive)
  self:_break_stale_links(alive)
  self:_relink(self:_powered_providers())
end

-- 目标通电状态：Core 恒通电；其余节点 = 已接入且供电者目标通电（R4）。
-- 用目标态递推，断电信号因此沿分支同一拍传到全部下游。
function Grid:_compute_want()
  local want, visiting = {}, {}
  local function want_of(e)
    if want[e.id] ~= nil then return want[e.id] end
    if visiting[e.id] then return false end -- 链不应成环，防御
    visiting[e.id] = true
    local w
    if e.kind == "Core" then
      w = true
    else
      local rec = self.recs[e.id]
      w = rec ~= nil and rec.provider ~= nil and want_of(rec.provider)
    end
    visiting[e.id] = false
    want[e.id] = w
    return w
  end
  for _, e in ipairs(self.registry.list) do want_of(e) end
  return want
end

-- 去抖：目标与生效不一致需持续 0.15 秒才翻转。
function Grid:_apply_debounce(want, dt)
  for _, e in ipairs(self.registry.list) do
    local rec = self.recs[e.id]
    local w = want[e.id] == true
    if w == rec.powered then
      rec.pending_want = nil
    elseif rec.pending_want ~= w then
      rec.pending_want = w
      rec.pending_t = 0
    else
      rec.pending_t = rec.pending_t + dt
      if rec.pending_t >= world.power_debounce - EPS then
        rec.powered = w
        rec.pending_want = nil
      end
    end
  end
end

function Grid:tick(dt)
  self:_reconcile_links()
  self:_apply_debounce(self:_compute_want(), dt)
end

-- 初始布局立即收敛：重复「接链 + 直接生效」直到供电关系与通电状态都不动。
function Grid:_settle_initial()
  for _ = 1, 8 do
    local before = {}
    for _, e in ipairs(self.registry.list) do
      local rec = self:_rec(e)
      before[e.id] = { provider = rec.provider, powered = rec.powered }
    end
    self:_reconcile_links()
    local want = self:_compute_want()
    local changed = false
    for _, e in ipairs(self.registry.list) do
      local rec = self.recs[e.id]
      local b = before[e.id]
      rec.powered = want[e.id] == true
      rec.pending_want = nil
      if b.provider ~= rec.provider or b.powered ~= rec.powered then changed = true end
    end
    if not changed then break end
  end
end

-- ── 读取 ──────────────────────────────────────────────────────────────────

-- 实体当前是否通电（已生效）。
function Grid:powered(e)
  local rec = e and self.recs[e.id]
  return rec ~= nil and rec.powered == true
end

-- 实体当前的供电者（未接入为 nil）。
function Grid:provider(e)
  local rec = e and self.recs[e.id]
  return rec and rec.provider or nil
end

-- 通电供电者集合（放置系统用）。
function Grid:powered_providers()
  return self:_powered_providers()
end

return M
