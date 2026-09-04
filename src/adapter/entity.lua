-- host.entity 域真实现（服务端）：业务实体 → SE WorldUnit。
--
-- 依据 #9 D1 表现映射表：
--   - 实体全部 WorldUnit；建筑/资源 Static，敌人 Kinematic + 每 tick Position；
--   - 近原语三件套：立方体 mesh/59268（包围盒半长 1）、圆柱 mesh/59273（半长 3）；
--   - Scale 变形定尺寸；ModelColor1 染色（#10 探针：写 Color 对象）；
--   - 显隐 = ModelVisible；销毁 = unit:Destroy()。
-- 依据 #18 决策 4：WorldUnit.Name = 业务实体 id（tostring），客户端血条按名寻单位。
--
-- 业务合约（与 e1dadeee host_mock 对齐，grep 自 38 个业务文件）：
--   spawn(prefab, pos) → entity 对象（id/prefab + set_position/get_position/
--   set_active/is_active/set_color/get_color/set_rotation/get_rotation/destroy）
--   destroy(e) / by_id / all() / distance* / find_in_circle(center, radius)
--
-- 逻辑位置与视觉位置分离：业务世界地面 y=0（#8 D2），适配层把单位抬到
-- 网格半高（落地）；业务读写的是逻辑位置（含 y=0），距离/碰撞查询不受影响。

local World = game:GetService("World")

-- ── 视觉配置表（prefab 键 → 原语配方；#9 D1）─────────────────────────
-- mesh_half: 网格包围盒半长（立方体 1 / 圆柱 3），落地偏移 = mesh_half × scale.y。
-- color: {r,g,b} 0..1，spawn 时染底色（业务受击/断电再覆写）。
local VISUALS = {
  Core =     { mesh = "official://mesh/59268", scale = { 2, 2, 2 },        half = 1, color = { 1, 0.84, 0 } },
  enemy =    { mesh = "official://mesh/59268", scale = { 0.8, 0.8, 0.8 },  half = 1, color = { 0.9, 0.15, 0.15 }, kinematic = true },
  Resource = { mesh = "official://mesh/59273", scale = { 0.6, 0.8, 0.6 },  half = 3, color = { 0.2, 0.9, 0.4 } },
  relay =    { mesh = "official://mesh/59273", scale = { 0.5, 0.5, 0.5 },  half = 3, color = { 0.4, 0.7, 1 } },
  radar =    { mesh = "official://mesh/59268", scale = { 0.8, 0.6, 0.8 },  half = 1, color = { 0.6, 0.6, 0.9 } },
  -- 雷达天线（#23）：业务每 tick 绕 Y 轴累加旋转；竖杆绕 Y 转肉眼看不出，
  -- 改为架在底座顶（radar 高 1.2）上的横杆，lift 指定中心离地高度。
  RadarDish = { mesh = "official://mesh/59268", scale = { 1.6, 0.12, 0.12 }, half = 1, color = { 0.95, 0.95, 1 }, lift = 1.45 },
  turret =   { mesh = "official://mesh/59268", scale = { 1, 1, 1 },        half = 1, color = { 0.9, 0.5, 0.1 } },
  repair =   { mesh = "official://mesh/59268", scale = { 1, 1, 1 },        half = 1, color = { 0.5, 0.9, 0.7 } },
}
-- 未知 prefab 的兜底：单位立方体（不报错，保业务零改动；视觉区分度留给后续票）。
local FALLBACK = { mesh = "official://mesh/59268", scale = { 1, 1, 1 }, half = 1, color = { 0.8, 0.8, 0.8 } }

local entity = {
  next_id = 1,
  by_id = {},
}

local function copy_vec3(v)
  if type(v) == "table" then
    return { x = v.x or v[1] or 0, y = v.y or v[2] or 0, z = v.z or v[3] or 0 }
  end
  return { x = 0, y = 0, z = 0 }
end

local function copy_color(c)
  if type(c) == "table" then
    return { r = c.r or c[1] or 1, g = c.g or c[2] or 1, b = c.b or c[3] or 1, a = c.a or c[4] or 1 }
  end
  return { r = 1, g = 1, b = 1, a = 1 }
end

local function xz_sq(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return dx * dx + dz * dz
end

function entity.spawn(prefab, pos)
  local vis = VISUALS[prefab] or FALLBACK
  local p = copy_vec3(pos)
  local ground_y = vis.lift or (vis.half * vis.scale[2])

  local unit = World:CreateUnit("WorldUnit", {
    Name = tostring(entity.next_id), -- #18 决策 4：Name = 业务实体 id
    RenderMeshId = vis.mesh,
    BodyType = vis.kinematic and Enums.BodyType.Kinematic or Enums.BodyType.Static,
    CanCollide = false, -- 碰撞在业务 collision.lua（Lua 圆碰撞）
    Scale = Vector3.New(vis.scale[1], vis.scale[2], vis.scale[3]),
    Position = Vector3.New(p.x, ground_y + p.y, p.z),
  })

  local id = entity.next_id
  entity.next_id = entity.next_id + 1

  -- 上游 set_color 语义是「tint」（默认白 = 不变色，受击红闪、断电压暗），
  -- 与 prefab 底色是乘法关系：实际染色 = 底色 × tint。否则业务写回白色
  -- 会把底色冲掉（building.lua 的 current_tint 机制）。
  local base_color = copy_color(vis.color)

  local e = {
    id = id,
    prefab = prefab,
    position = p,
    active = true,
    color = { r = 1, g = 1, b = 1, a = 1 }, -- 业务 tint，默认白
    rotation = 0,
    _unit = unit,
    _ground_y = ground_y,
    _base = base_color,
  }

  local function apply_color(self)
    if not self._unit then return end
    local t, b = self.color, self._base
    self._unit.ModelColor1 = Color.New(
      math.floor(t.r * b.r * 255 + 0.5),
      math.floor(t.g * b.g * 255 + 0.5),
      math.floor(t.b * b.b * 255 + 0.5),
      math.floor((t.a or 1) * 255 + 0.5))
  end

  function e:set_position(np)
    self.position = copy_vec3(np)
    if self._unit then
      self._unit.Position = Vector3.New(
        self.position.x, self._ground_y + self.position.y, self.position.z)
    end
  end

  function e:get_position()
    return self.position
  end

  function e:set_active(v)
    self.active = v and true or false
    if self._unit then
      self._unit.ModelVisible = self.active
    end
  end

  function e:is_active()
    return self.active
  end

  function e:set_color(c)
    self.color = copy_color(c)
    apply_color(self)
  end

  function e:get_color()
    return self.color
  end

  -- XZ 平面朝向角（弧度）→ 世界单位朝向：绕 Y 轴、弧度→度。业务侧雷达天线
  -- 是无界累加（radar.lua），写引擎前归一到 [0,360) 防浮点漂移；业务读回的
  -- 仍是原始累加值（get_rotation 语义不变）。轴向语义待真机目视（#23 HITL）。
  function e:set_rotation(r)
    self.rotation = r
    if self._unit then
      local deg = math.deg(r) % 360
      pcall(function()
        self._unit.Rotation = Vector3.New(0, deg, 0)
      end)
    end
  end

  function e:get_rotation()
    return self.rotation
  end

  function e:destroy()
    entity.destroy(self)
  end

  entity.by_id[id] = e
  apply_color(e) -- 底色（tint=白 → 显示 prefab 底色）
  return e
end

function entity.destroy(e)
  if e and e.id and entity.by_id[e.id] then
    entity.by_id[e.id] = nil
    if e._unit then
      pcall(function() e._unit:Destroy() end)
      e._unit = nil
    end
  end
end

function entity.all()
  local list = {}
  for _, e in pairs(entity.by_id) do
    list[#list + 1] = e
  end
  return list
end

function entity.distance_sq(a, b)
  local dx = a.position.x - b.position.x
  local dy = a.position.y - b.position.y
  local dz = a.position.z - b.position.z
  return dx * dx + dy * dy + dz * dz
end

function entity.distance(a, b)
  return math.sqrt(entity.distance_sq(a, b))
end

function entity.distance_xz_sq(a, b)
  return xz_sq(a.position, b.position)
end

function entity.distance_xz(a, b)
  return math.sqrt(entity.distance_xz_sq(a, b))
end

-- 返回与 center 在 XZ 平面重叠 radius 圆的活跃实体，按距离近→远排序。
function entity.find_in_circle(center, radius)
  local c = copy_vec3(center)
  local r2 = radius * radius
  local hits = {}
  for _, e in pairs(entity.by_id) do
    if e.active then
      local d2 = xz_sq(c, e.position)
      if d2 < r2 then
        hits[#hits + 1] = { entity = e, dist_sq = d2 }
      end
    end
  end
  table.sort(hits, function(a, b) return a.dist_sq < b.dist_sq end)
  local result = {}
  for _, h in ipairs(hits) do
    result[#result + 1] = h.entity
  end
  return result
end

-- reset_scene 用：销毁全部已 spawn 单位并清零注册表。
function entity.reset()
  for _, e in pairs(entity.by_id) do
    if e._unit then
      pcall(function() e._unit:Destroy() end)
      e._unit = nil
    end
  end
  entity.by_id = {}
  entity.next_id = 1
end

return entity
