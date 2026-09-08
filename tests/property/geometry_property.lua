-- 对局几何/碰撞领域的性质测试。
--
-- 覆盖 server.kernel.world_data 的欧氏距离，server.kernel.collision_body 的圆重叠与排序，
-- 以及 server.kernel.collision 碰撞世界发布的重叠集合必须等于暴力法算出的有序集合
-- （空间哈希正确性 / 确定性排序 / 幂等发布的强不变量）。纯 Lua，无宿主依赖。
local property = require("tests.spoke.property.support.property")
local World = require("server.kernel.world_data")
local CollisionBody = require("server.kernel.collision_body")
local CollisionWorld = require("server.kernel.collision")

local gen = property.gen

-- 随机平面点：整数坐标 + 小量浮点，令距离不落回整数，覆盖连续输入范围。
local function point(rng)
  return {
    x = rng:int(-40, 40) + rng:float(),
    z = rng:int(-40, 40) + rng:float(),
  }
end
local function circle(rng)
  local c = point(rng)
  return {
    center = { x = c.x, y = rng:float(), z = c.z },
    radius = 0.2 + rng:float() * 3.8, -- 覆盖小圆到大圆
  }
end

-- 距离不变量：非负、对称、自距为 0。
property.forall("dist_nonneg_symmetric_zero", { point, point }, function(a, b)
  local dab = World.dist(a.x, a.z, b.x, b.z)
  if dab < 0 then
    return "distance is negative"
  end
  if World.dist(a.x, a.z, b.x, b.z) ~= World.dist(b.x, b.z, a.x, a.z) then
    return "distance not symmetric"
  end
  if World.dist(a.x, a.z, a.x, a.z) ~= 0 then
    return "self distance is not zero"
  end
  return true
end)

-- 三角不等式（浮点 sqrt 允许 1e-9 容差）。
property.forall("dist_triangle_inequality", { point, point, point }, function(a, b, c)
  local ab = World.dist(a.x, a.z, b.x, b.z)
  local bc = World.dist(b.x, b.z, c.x, c.z)
  local ac = World.dist(a.x, a.z, c.x, c.z)
  if ac > ab + bc + 1e-9 then
    return "triangle inequality violated: " .. ac .. " > " .. ab + bc
  end
  return true
end)

-- 圆重叠不变量：对称；任一圆与自己恒重叠（GDD 04 R4 相切算相交）。
property.forall("circles_overlap_symmetric_and_self", { circle, circle }, function(a, b)
  if CollisionBody.circles_overlap(a, b) ~= CollisionBody.circles_overlap(b, a) then
    return "overlap not symmetric"
  end
  if not CollisionBody.circles_overlap(a, a) then
    return "a circle does not overlap itself"
  end
  return true
end)

-- 单调性：两个圆若重叠，把其中一个沿两心连线向另一个靠近（t∈[0,1)）仍重叠。
property.forall("circles_closer_never_breaks_overlap", { circle, circle, gen.float(0, 1) }, function(a, b, t)
  if not CollisionBody.circles_overlap(a, b) then
    return true -- 前提不成立，性质空真
  end
  local closer = {
    center = {
      x = a.center.x + t * (b.center.x - a.center.x),
      y = a.center.y + t * (b.center.y - a.center.y),
      z = a.center.z + t * (b.center.z - a.center.z),
    },
    radius = b.radius,
  }
  if not CollisionBody.circles_overlap(a, closer) then
    return "moving a circle closer broke an existing overlap"
  end
  return true
end)

-- 排序不变量：sort_by_distance 给出确定性全序 —— 输出是输入的重新排列，
-- dist2 非降，并列按 _serial 升序（上游 List.Sort 不稳定，本端口固定次序）。
local function sorted_entries_gen(rng)
  local n = rng:int(1, 8)
  local out = {}
  for i = 1, n do
    out[#out + 1] = {
      body = { _serial = i }, -- 唯一序列号，保证置换/丢失断言可靠
      dist2 = rng:int(0, 10000) + rng:float(),
    }
  end
  return out
end

property.forall("sort_by_distance_is_deterministic_total_order",
  { sorted_entries_gen }, function(entries)
    local before = {}
    for i, e in ipairs(entries) do
      before[e.body._serial] = true
    end
    CollisionBody.sort_by_distance(entries)
    local seen = {}
    for i = 1, #entries do
      local e = entries[i]
      if not before[e.body._serial] then
        return "sorted output contains a foreign body"
      end
      seen[e.body._serial] = true
      if i > 1 then
        local prev = entries[i - 1]
        if e.dist2 < prev.dist2 then
          return "dist2 not non-decreasing"
        end
        if e.dist2 == prev.dist2 and not (prev.body._serial < e.body._serial) then
          return "tie not broken by ascending _serial"
        end
      end
    end
    if next(seen) == nil and #entries > 0 then
      return "sorted output is empty"
    end
    for serial in pairs(before) do
      if not seen[serial] then
        return "sorted output lost a body (serial " .. serial .. ")"
      end
    end
    return true
  end)

-- 碰撞世界强不变量：tick 后每个 body 发布的重叠列表必须等于暴力法算出的、
-- 与其实际重叠且按（dist2, serial）排序的 body 列表（空间哈希 + 增量重算正确性）。
local function circles_gen(rng)
  local n = rng:int(1, 6)
  local out = {}
  for i = 1, n do
    out[i] = circle(rng)
  end
  return out
end

property.forall("collision_world_publishes_exact_sorted_overlaps", { circles_gen }, function(circles)
  local world = CollisionWorld.new()
  local bodies = {}
  for i, c in ipairs(circles) do
    local fixed = {
      center = { x = c.center.x, y = 0, z = c.center.z },
      radius = c.radius,
    }
    bodies[i] = world:add_collider(fixed, function()
      return {
        center = { x = fixed.center.x, y = 0, z = fixed.center.z },
        radius = fixed.radius,
      }
    end)
  end
  world:tick()

  for i, b in ipairs(bodies) do
    local expected_raw = {}
    for j, ob in ipairs(bodies) do
      if j ~= i and CollisionBody.circles_overlap(b.circle, ob.circle) then
        local dx = b.circle.center.x - ob.circle.center.x
        local dz = b.circle.center.z - ob.circle.center.z
        expected_raw[#expected_raw + 1] = {
          body = ob,
          dist2 = dx * dx + dz * dz,
        }
      end
    end
    CollisionBody.sort_by_distance(expected_raw)
    local expected = {}
    for k, item in ipairs(expected_raw) do
      expected[k] = item.body
    end
    local got = b.overlaps:now()
    if #got ~= #expected then
      return string.format("body %d published %d overlaps, expected %d", i, #got, #expected)
    end
    for k = 1, #expected do
      if got[k] ~= expected[k] then
        return string.format("body %d overlap %d is wrong body", i, k)
      end
    end
  end
  return true
end)
