-- 05_BaseDefence 碰撞世界（2D 圆形空间哈希）。
--
-- 忠实移植上游 Spatial/CollisionWorld.cs + Circle.cs：
--   - 格子分桶：每个 body 按 circle 覆盖的格子登记，cellSize 默认 4
--     （上游建议取典型查询半径附近）；
--   - dirty 增量：body 插入/移除/移动把经过的格子标脏，tick 只重算
--     脏格子里的 body；
--   - tick 整体包在 SpokeRuntime.batch 里（上游 Tick() => SpokeRuntime.Batch(step)），
--     保证一帧内所有 overlaps 发布合并为一次 flush；
--   - Overlaps 按 XZ 距离近→远排序，内容不变不发布；排序并列时按插入次序
--     决胜，保证确定性（上游 List.Sort 不稳定，本端口固定次序便于断言）。
--
-- 公开契约（与朴素实现时期一致）：
--   - Collider：可被检测的圆，绑定一个 owner，每 tick 重采样位置；
--   - Sensor：只"看别人"、不被别人看到的探测圆；
--   - Overlaps：按 XZ 距离近→远排序的 collider 列表，只在内容变化时发布；
--   - Query：一次性立即查询与给定圆重叠的 collider（本端口保持近→远排序；
--     上游 Query 不排序，该差异记录在 docs/spec.md §7 偏离表）。
--
-- Body（每圆的快照/Poll/overlaps 发布）与 circle 值类型语义在
-- server.kernel.collision_body。

local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")

local CollisionBody = require("server.kernel.collision_body")
local circles_overlap = CollisionBody.circles_overlap
local new_body = CollisionBody.new_body

local CollisionWorld = {}
CollisionWorld.__index = CollisionWorld

local function cell_key(x, z)
  return x .. "," .. z
end

--- 创建一个新的碰撞世界。cell_size 是格子边长，默认 4。
function CollisionWorld.new(cell_size)
  return setmetatable({
    cell_size = cell_size or 4,
    _cells = {}, -- cell_key -> body 数组
    _dirty = {}, -- cell_key -> true
    _bodies = {}, -- body -> true（所有存活 body）
    _next_serial = 0, -- 插入序号，排序决胜用
  }, CollisionWorld)
end

--- 添加一个可被检测的 collider。
-- @param owner 本 collider 代表的宿主对象
-- @param get_circle 每 tick 调用以重新采样当前 circle 的函数
-- @param filter 可选：fn(other_owner)->bool，只接受返回为真的 collider
-- @return body 包含 circle、overlaps（State）、owner、dispose
function CollisionWorld:add_collider(owner, get_circle, filter)
  return new_body(self, owner, get_circle, true, filter)
end

--- 添加一个只检测别人、不被检测的 sensor。
-- @param get_circle 每 tick 调用以重新采样当前 circle 的函数
-- @param filter 可选：fn(other_owner)->bool，只接受返回为真的 collider
-- @return body 包含 circle、overlaps（State）、dispose；无 owner
function CollisionWorld:add_sensor(get_circle, filter)
  return new_body(self, nil, get_circle, false, filter)
end

--- 遍历 circle 覆盖的所有格子，回调 fn(x, z, key)。
function CollisionWorld:_each_cell(circle, fn)
  local r = circle.radius
  local cs = self.cell_size
  local min_x = math.floor((circle.center.x - r) / cs)
  local max_x = math.floor((circle.center.x + r) / cs)
  local min_z = math.floor((circle.center.z - r) / cs)
  local max_z = math.floor((circle.center.z + r) / cs)
  for x = min_x, max_x do
    for z = min_z, max_z do
      fn(x, z, cell_key(x, z))
    end
  end
end

--- 遍历 circle 覆盖的所有格子：先调 fn(key)，再把该格标脏（重插/移除共用）。
function CollisionWorld:_each_dirty_cell(circle, fn)
  self:_each_cell(circle, function(_, _, key)
    fn(key)
    self._dirty[key] = true
  end)
end

function CollisionWorld:_insert(body)
  self:_each_dirty_cell(body.circle, function(key)
    local list = self._cells[key]
    if not list then
      list = {}
      self._cells[key] = list
    end
    list[#list + 1] = body
  end)
end

function CollisionWorld:_remove(body)
  self:_each_dirty_cell(body.circle, function(key)
    local list = self._cells[key]
    if list then
      for i, b in ipairs(list) do
        if b == body then
          table.remove(list, i)
          break
        end
      end
    end
  end)
end

--- 把 circle 覆盖格子里的所有 body 收进 out set（body -> true）。
function CollisionWorld:_broadphase(circle, out)
  self:_each_cell(circle, function(_, _, key)
    local list = self._cells[key]
    if list then
      for _, b in ipairs(list) do
        out[b] = true
      end
    end
  end)
end

--- 重采样位置、增量重算并发布变化的 overlaps；整体包在一个 batch 里。
function CollisionWorld:tick()
  SpokeRuntime.batch(function()
    self:_step()
  end)
end

function CollisionWorld:_step()
  -- 先全部重采样：移动的 body 重插并把新旧格子都标脏。
  for body in pairs(self._bodies) do
    body:_poll()
  end

  -- 脏格子里的 body 才需要重算 overlaps。
  local dirty_bodies = {}
  for key in pairs(self._dirty) do
    local list = self._cells[key]
    if list then
      for _, b in ipairs(list) do
        dirty_bodies[b] = true
      end
    end
  end
  self._dirty = {}

  for body in pairs(dirty_bodies) do
    body:_recompute()
  end
end

--- 一次性立即查询与给定 circle 重叠的 collider body（近→远）。
-- 使用最近一次 tick（或 add 时）采样的 circle，不触发 overlaps 发布。
function CollisionWorld:query(area)
  local found = {}
  self:_broadphase(area, found)

  local sorted = {}
  for body in pairs(found) do
    if body.detectable and circles_overlap(area, body.circle) then
      local dx = area.center.x - body.circle.center.x
      local dz = area.center.z - body.circle.center.z
      sorted[#sorted + 1] = {
        body = body,
        dist2 = dx * dx + dz * dz,
      }
    end
  end

  CollisionBody.sort_by_distance(sorted)

  local result = {}
  for i, item in ipairs(sorted) do
    result[i] = item.body
  end
  return result
end

return CollisionWorld
