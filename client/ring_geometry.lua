-- 覆盖圈几何：逻辑半径 → 官方圆环白模的 Scale。
--
-- 纯函数、零依赖（不 require 任何模块、不碰 SE 全局），所以单元测试能直接跑它。
-- 这很重要：真机跑不了 headless，host-mock 只记逻辑半径，尺寸正确性在整条链路上
-- 只有这里能被自动验证（Gitea #42 缝三）。
--
-- 标定出处（真机实测，2026-09-08，编辑器实例 BaseDefence）：
--   对 official://mesh/59269（ugc_圆环）用 PhysicsService:Raycast 垂直下扫求内外缘，
--   Scale = 1 / 2 / 4 三档测得 (1.25, 1.58) / (2.50, 3.17) / (5.00, 6.35)，完全线性。
--   2026-09-08 复测 Scale = 0.267 / 2.667 / 3.333 / 5.333，外缘 0.42 / 4.24 / 5.28 / 8.48。
--   Raycast 量到的是碰撞体，它比渲染网格**按比例**大约 6%（不是固定余量：外缘 ÷ Scale
--   恒为 1.585，各档都是 1.5 的 1.057 倍）。扣掉这一层后 Scale = 1 时外缘半径 = 1.5，
--   与资源表 Size.x 的一半吻合。
--   注意 Size 是直径不是半长：资源表给 59269 标 (3,1,3)，实测外缘直径就是 3.0；
--   按字面读成半径会得到 2 倍误差。
--
-- 已证伪：白模族（59268/59269/59273/59291）不吃 ModelColor1/2/3/4，FileMesh 的
-- VertexColor 也无效，所以本模块只谈几何，不谈颜色。

local ring_geometry = {}

ring_geometry.RING_MESH = "official://mesh/59269"

-- Scale = 1 时圆环的外缘半径。
ring_geometry.TORUS_OUTER_RADIUS = 1.5

-- 环在垂直方向的缩放：定值，让环无论多大都平贴地面，不长成一根管子。
ring_geometry.RING_FLATTEN = 0.2

-- 环的离地高度，避免与地面 z-fighting。
ring_geometry.RING_Y = 0.05

--- 逻辑半径 → 水平缩放；半径非正时返回 nil（调用方据此不建单位）。
function ring_geometry.scale_for_radius(radius)
  if type(radius) ~= "number" or radius <= 0 then
    return nil
  end
  return radius / ring_geometry.TORUS_OUTER_RADIUS
end

return ring_geometry
