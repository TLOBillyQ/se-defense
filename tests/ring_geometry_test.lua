-- Unit tests for client/ring_geometry.lua: 逻辑半径 → 圆环白模 Scale 的换算。
-- 唯一能自动验证「圈画多大」的缝：真机跑不了 headless，host-mock 只记逻辑半径，
-- 所以尺寸正确性只能在这个纯函数上钉死（Gitea #42 缝三）。
local lu = require("luaunit")
local ring_geometry = require("client.ring_geometry")

-- GDD 00 实体总表里实际用到的半径：足迹 0.4/0.5/0.6，供电 4，射程/维修 5，雷达 8。
local RADII = { 0.4, 0.5, 0.6, 4, 5, 8 }

TestRingGeometry = {}

-- 换算的定义即「缩放后的外缘半径等于逻辑半径」，容差 1%。
function TestRingGeometry:testOuterRadiusMatchesLogicalRadius()
  for _, r in ipairs(RADII) do
    local scale = ring_geometry.scale_for_radius(r)
    lu.assertAlmostEquals(scale * ring_geometry.TORUS_OUTER_RADIUS, r, r * 0.01)
  end
end

-- 高亮环是足迹半径的 1.5 倍，恰好落在 Scale = 足迹半径 上；顺带钉死线性。
function TestRingGeometry:testScaleIsLinearInRadius()
  lu.assertAlmostEquals(ring_geometry.scale_for_radius(3), 2 * ring_geometry.scale_for_radius(1.5), 1e-9)
end

-- 半径 0 / 负数不该产生单位（调用方据此跳过），而不是画出一个反向的环。
function TestRingGeometry:testNonPositiveRadiusHasNoScale()
  lu.assertNil(ring_geometry.scale_for_radius(0))
  lu.assertNil(ring_geometry.scale_for_radius(-1))
end

-- 白模族不吃颜色（#42 实测），所以模块只暴露网格与几何，不暴露颜色。
function TestRingGeometry:testExposesMeshId()
  lu.assertEquals(ring_geometry.RING_MESH, "official://mesh/59269")
end
