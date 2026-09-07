-- 05_BaseDefence 碰撞体（CollisionWorld 的 Body 部分）。
--
-- 忠实移植上游 Spatial/CollisionWorld.cs 的 Body 与 Circle.cs 的值类型语义：
--   - 每个 body 持有 circle 快照（上游 Circle 是值类型 struct，getCircle 每次
--     返回新值；Lua 侧调用方常原地改同一个 table，因此 body 必须持有拷贝，
--     比较与分桶都基于快照）；
--   - Poll 按值比较 circle，未变则跳过重插；
--   - overlaps 按 XZ 距离近→远排序，内容不变不发布；排序并列时按插入次序
--     决胜，保证确定性（上游 List.Sort 不稳定，本端口固定次序便于断言）。
--
-- CollisionWorld（server.game.collision）只保留空间哈希部分。

local State = require("common.spoke.reactive.state")

local CollisionBody = {}

local Body = {}
Body.__index = Body

--- 判断两个圆在 XZ 平面是否重叠（恰相切不算）。
function CollisionBody.circles_overlap(a, b)
  local reach = a.radius + b.radius
  local dx = a.center.x - b.center.x
  local dz = a.center.z - b.center.z
  return dx * dx + dz * dz < reach * reach
end

--- 按值比较两个 circle（上游 Circle.Equals：Center + Radius 全等）。
function CollisionBody.circles_equal(a, b)
  return a.center.x == b.center.x
    and a.center.y == b.center.y
    and a.center.z == b.center.z
    and a.radius == b.radius
end

--- 按 XZ 距离近→远排序 overlaps 候选（{body=, dist2=} 条目数组，原地排序），
--- 并列时按插入序号决胜（确定性次序，见文件头注释）。
function CollisionBody.sort_by_distance(sorted)
  table.sort(sorted, function(lhs, rhs)
    if lhs.dist2 ~= rhs.dist2 then
      return lhs.dist2 < rhs.dist2
    end
    return lhs.body._serial < rhs.body._serial
  end)
end

--- 拷贝 circle 为自有快照。
function CollisionBody.copy_circle(c)
  return {
    center = { x = c.center.x, y = c.center.y, z = c.center.z },
    radius = c.radius,
  }
end

function CollisionBody.new_body(world, owner, get_circle, detectable, filter)
  world._next_serial = world._next_serial + 1
  local body = setmetatable({
    owner = owner,
    get_circle = get_circle,
    filter = filter,
    detectable = detectable,
    circle = CollisionBody.copy_circle(get_circle()),
    overlaps = State.new({}),
    _serial = world._next_serial,
    _world = world,
    _published = {}, -- 最近一次发布的 overlaps 内容（body 数组）
  }, Body)
  world._bodies[body] = true
  world:_insert(body)
  return body
end

--- 重采样 circle；值未变则跳过（上游 next == circle 短路）。
function Body:_poll()
  local next_circle = self.get_circle()
  if CollisionBody.circles_equal(next_circle, self.circle) then
    return
  end
  self._world:_remove(self)
  self.circle = CollisionBody.copy_circle(next_circle)
  self._world:_insert(self)
end

--- 重算本 body 的 overlaps；内容不变不发布。
function Body:_recompute()
  local area = self.circle
  local found = {}
  self._world:_broadphase(area, found)

  local sorted = {}
  for body in pairs(found) do
    if body.detectable and body ~= self then
      local pass_filter = self.filter == nil or self.filter(body.owner)
      if pass_filter and CollisionBody.circles_overlap(area, body.circle) then
        local dx = area.center.x - body.circle.center.x
        local dz = area.center.z - body.circle.center.z
        sorted[#sorted + 1] = {
          body = body,
          dist2 = dx * dx + dz * dz,
        }
      end
    end
  end

  CollisionBody.sort_by_distance(sorted)

  local current = self._published
  local same = #current == #sorted
  if same then
    for i, item in ipairs(sorted) do
      if current[i] ~= item.body then
        same = false
        break
      end
    end
  end
  if same then
    return
  end

  local next_overlaps = {}
  for i, item in ipairs(sorted) do
    next_overlaps[i] = item.body
  end
  self._published = next_overlaps
  self.overlaps:set(next_overlaps)
end

--- 将本 body 从世界移除并发布空 overlaps；幂等。
function Body:dispose()
  local world = self._world
  if not world then
    return
  end
  self._world = nil

  world._bodies[self] = nil
  world:_remove(self)

  self._published = {}
  self.overlaps:set({})
end

return CollisionBody
