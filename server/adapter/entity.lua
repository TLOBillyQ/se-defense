-- host.entity 域真实现（服务端）：业务实体 → SE WorldUnit。
--
-- 依据 #9 D1 表现映射表：
--   - 实体全部 WorldUnit；建筑/资源 Static，敌人 Kinematic + 每 tick Position；
--   - 近原语三件套：立方体 mesh/59268（包围盒半长 1）、圆柱 mesh/59273（半长 3）；
--   - Scale 变形定尺寸；ModelColor1 染色（#10 探针：写 Color 对象）；
--   - 显隐 = ModelVisible；销毁 = unit:Destroy()。
-- 依据 #18 决策 4：WorldUnit.Name = 业务实体 id（tostring），客户端血条按名寻单位。
--   #28 补充：Restart 后 id 从 1 重分配，而旧单位的 Destroy 与新单位的创建经复制到达
--   客户端的先后无文档承诺；为免血条锚到将死的旧单位，重开后的单位名带代数后缀
--   "<id>g<gen>"（首局仍是裸 id）。客户端从快照 gen 复刻同一约定（eui_render.lua）。
--
-- 业务合约（与 e1dadeee host_mock 对齐，grep 自 38 个业务文件）：
--   spawn(prefab, pos) → entity 对象（id/prefab + set_position/get_position/
--   set_active/is_active/set_color/get_color/set_rotation/get_rotation/destroy）
--   destroy(e) / by_id / all()
--
-- 逻辑位置与视觉位置分离：业务世界地面 y=0（#8 D2），适配层把单位抬到
-- 网格半高（落地）；业务读写的是逻辑位置（含 y=0），碰撞查询由业务
-- server/game/collision.lua 负责。

local World = game:GetService("World")
local convert = require("server.adapter.convert")

-- ── 视觉配置表（prefab 键 → 模型配方；#29 主题化升级）─────────────────────
-- half: 网格包围盒半长（Y 向）。pivot: 模型中心相对原点的 Y 偏移。
-- 落地偏移 = (half - pivot) × scale.y，使模型底面贴地（对称模型 pivot=0，等价旧公式 half×scale.y）。
-- color: 业务 tint 的底色（乘法）：白 = 显示模型本底色；受击红闪/断电压暗经 tint 覆写。
local VISUALS = {
  -- Core：城堡塔（俯视带细节的方形基座，主题化替代原样金色立方体）。
  Core =           { mesh = "official://mesh/100120", scale = { 0.42, 0.42, 0.42 }, half = 10, pivot = 5, color = { 1, 1, 1 } },
  -- 敌人三档：卡通小恶魔（恶魔冰淇淋球），同模型按体积/色相拉开，俯视一眼可辨。
  enemy =          { mesh = "official://mesh/58189", scale = { 0.11, 0.11, 0.11 }, half = 6, pivot = 3, color = { 1, 0.42, 0.42 }, kinematic = true },
  enemy_heavy =    { mesh = "official://mesh/58189", scale = { 0.15, 0.15, 0.15 }, half = 6, pivot = 3, color = { 1, 0.4, 0.85 }, kinematic = true },
  enemy_boss =     { mesh = "official://mesh/58189", scale = { 0.22, 0.22, 0.22 }, half = 6, pivot = 3, color = { 0.72, 0.42, 1 }, kinematic = true },
  -- 资源：四棱锥晶石。
  Resource =       { mesh = "official://mesh/59291", scale = { 0.45, 0.45, 0.45 }, half = 3, pivot = 1.5, color = { 0.3, 0.95, 0.45 } },
  -- 建筑：主题化。
  relay =          { mesh = "official://mesh/55913", scale = { 1.2, 1.2, 1.2 }, half = 1.5, pivot = 0.75, color = { 1, 1, 1 } },
  radar =          { mesh = "official://mesh/7000122", scale = { 0.35, 0.35, 0.35 }, half = 3, pivot = 1.49, color = { 1, 1, 1 } },
  -- 雷达天线（#23）：业务每 tick 绕 Y 轴累加旋转；横杆架在底座顶（radar 高≈2.1）。
  RadarDish =      { mesh = "official://mesh/59268", scale = { 1.6, 0.12, 0.12 }, half = 1, color = { 0.95, 0.95, 1 }, lift = 2.4 },
  turret =         { mesh = "official://mesh/400889", scale = { 0.7, 0.7, 0.7 }, half = 1.18, pivot = 0.38, color = { 1, 1, 1 } },
  repair =         { mesh = "official://mesh/57703", scale = { 0.18, 0.18, 0.18 }, half = 6, pivot = 3.02, color = { 1, 1, 1 } },
}
-- 未知 prefab 的兜底：单位立方体（不报错，保业务零改动）。
local FALLBACK = { mesh = "official://mesh/59268", scale = { 1, 1, 1 }, half = 1, color = { 0.8, 0.8, 0.8 } }

local entity = {
  next_id = 1,
  by_id = {},
  generation = 0, -- reset 次数；与 eui.generation 同步递增（reset_scene 同时调两者）
}

-- 单位名约定（#18 决策 4 + #28 代数后缀）
function entity.unit_name(id, gen)
  gen = gen or entity.generation
  if gen == 0 then return tostring(id) end
  return tostring(id) .. "g" .. tostring(gen)
end

function entity.spawn(prefab, pos)
  local vis = VISUALS[prefab] or FALLBACK
  local p = convert.copy_vec3(pos)
  local ground_y = vis.lift or ((vis.half - (vis.pivot or 0)) * vis.scale[2])

  local unit = World:CreateUnit("WorldUnit", {
    Name = entity.unit_name(entity.next_id), -- #18 决策 4：Name = 业务实体 id（重开后带代数后缀）
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
  local base_color = convert.copy_color(vis.color)

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
    self._unit.ModelColor1 = convert.rgb01(t.r * b.r, t.g * b.g, t.b * b.b, t.a)
  end

  function e:set_position(np)
    self.position = convert.copy_vec3(np)
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
    self.color = convert.copy_color(c)
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

-- reset_scene 用：销毁全部已 spawn 单位并清零注册表，代数 +1（新局单位名换后缀）。
function entity.reset()
  for _, e in pairs(entity.by_id) do
    if e._unit then
      pcall(function() e._unit:Destroy() end)
      e._unit = nil
    end
  end
  entity.by_id = {}
  entity.next_id = 1
  entity.generation = entity.generation + 1
end

return entity
