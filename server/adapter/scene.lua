-- host.scene 域真实现（服务端）：运行时静态场景装饰。
--
-- 职责：只做视觉，不做玩法。铺设地面、外围装饰等静态单位。这些单位**不进入**
-- entity.by_id，restart 走 host:reset_scene() 清除的是业务实体，场景装饰随地图加载
-- 重建即可，无需 reset。
--
-- 依据（#29 实测）：
--   - 运行时 World:CreateUnit 对"基础原语"大幅缩放会**不渲染**；而 asset preset
--     （基础草地）LoadUnitAsset 后设 root.Scale 可正常放大（#29 探针：单块 scale≈2.2
--     已覆盖相机大部分；scale 再大可能溢出边界，故取 2.5 留有安全余量）。
--   - ModelColor1 对部分网格是乘法、对带烘焙色网格可能被忽略；场景配色依赖原生资产色。
--
-- 主题：能量防线(草原)。绿色草原地面 + 外围晶石。

local World = game:GetService("World")
local AssetService = game:GetService("AssetService")

local scene = {}

local GRASS = "official://preset/1510240"      -- 基础草地
local CRYSTAL = "official://mesh/59291"        -- 四棱锥（native half=(3,3,3), center_y=1.5）

local function tint(u, c)
  if u and c then
    u.ModelColor1 = Color.New(
      math.floor(c[1] * 255 + 0.5),
      math.floor(c[2] * 255 + 0.5),
      math.floor(c[3] * 255 + 0.5), 255)
  end
  return u
end

-- 加载一块草地并放大铺满相机视野；顶面接近 y=0。
local function build_ground(scale)
  local units = AssetService:LoadUnitAsset(GRASS)
  local root = units and units[1]
  if root then
    root.Scale = Vector3.New(scale, 1, scale)
    root.Position = Vector3.New(0, -0.7, 0)
    root.Parent = World
  end
  return root
end

-- 晶石：native half=(3,3,3)、center_y=1.5，底面贴地。
local function crystal(idx, x, z, s, c)
  local u = World:CreateUnit("WorldUnit", {
    Name = "bd_crystal_" .. idx,
    RenderMeshId = CRYSTAL,
    BodyType = Enums.BodyType.Static,
    CanCollide = false,
    Scale = Vector3.New(s, s, s),
    Position = Vector3.New(x, 1.5 * s, z),
  })
  return tint(u, c)
end

function scene.build()
  build_ground(2.5)

  -- 外围晶石：沿棋盘边缘与四角点缀（native 偏粉白，作为晶石成立）。
  local CRY = { 0.5, 0.9, 0.8 }
  local CRY2 = { 0.62, 0.9, 0.86 }
  local ring = {
    { -20, -20, CRY }, { 20, -20, CRY2 }, { -20, 20, CRY2 }, { 20, 20, CRY },
    { -28, -12, CRY2 }, { 28, -12, CRY }, { -28, 12, CRY }, { 28, 12, CRY2 },
    { -12, 24, CRY2 }, { 12, 24, CRY }, { 0, 26, CRY2 },
  }
  for i, r in ipairs(ring) do
    crystal(i, r[1], r[2], (i % 2 == 0) and 0.6 or 0.45, r[3])
  end

  return scene
end

return scene