-- 05_BaseDefence 覆盖圈显示（CoverageDisplay 的宿主等价物）。
--
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/CoverageDisplay.cs：
--   - draw_zone：给 CollisionWorld 挂 sensor，把 sensor 看到的所有 collider
--     圆渲染为 EUI ring 节点；
--   - draw_circle：把单个（可移动/可变半径）圆信号渲染为一个 ring 节点。
--
-- 上游用合并轮廓 mesh 渲染所有圆的并集边界；本端口按 #18 Q8 裁剪为
-- “每圆一个 EUI ring”，host-mock 下只保留可断言状态，真机把 ring 节点
-- 换成对应 EUI 线框即可。sensor 内成员不变时不会重发，因此移动中的单个
-- footprint 请使用 draw_circle（读信号），静态建筑覆盖用 draw_zone。

local render_util = require("src.game.render_util")

local CoverageDisplay = {}

-- 把 circles 渲染成 path_prefix_<serial> 的一批 ring 节点。
-- circles: { {center=..., radius=...}, ... }，本轮结束统一清理。
local function render_circles(s, host, path_prefix, circles, colour_now)
  local created = {}
  for index, item in ipairs(circles) do
    local serial = item.serial or item.index or index
    local node_path = path_prefix .. "_" .. serial
    local node = host.eui.nodes[node_path] or host.eui.node(node_path)
    node:set_visible(true)
    node:set_ring(item.center, item.radius)
    node:set_color(colour_now)
    created[node_path] = true
  end

  render_util.destroy_created(s, host, created)
end

--- 渲染一个 CollisionWorld zone 中的 collider 覆盖圈。
-- opts.zone / opts.host / opts.path 必填；opts.area 返回 sensor 圆；
-- opts.filter 传给 sensor；opts.colour 可为颜色表或颜色信号。
function CoverageDisplay.draw_zone(s, opts)
  local host = opts.host or error("CoverageDisplay.draw_zone requires host", 2)
  local zone = opts.zone or error("CoverageDisplay.draw_zone requires zone", 2)
  local path = opts.path or error("CoverageDisplay.draw_zone requires path", 2)
  local area = opts.area or error("CoverageDisplay.draw_zone requires area", 2)

  local sensor = s:use(zone:add_sensor(area, opts.filter))

  s:effect("CoverageDisplay.Zone:" .. path, function(sb)
    local circles = {}
    for _, body in ipairs(sb:d(sensor.overlaps)) do
      circles[#circles + 1] = {
        serial = body._serial,
        center = body.circle.center,
        radius = body.circle.radius,
      }
    end
    render_circles(sb, host, path, circles, render_util.colour_value(sb, opts.colour))
  end)
end

--- 渲染单个圆。opts.circle 可以是 circle 信号，也可以是固定 circle 表。
function CoverageDisplay.draw_circle(s, opts)
  local host = opts.host or error("CoverageDisplay.draw_circle requires host", 2)
  local path = opts.path or error("CoverageDisplay.draw_circle requires path", 2)
  local circle = opts.circle or error("CoverageDisplay.draw_circle requires circle", 2)

  local node = host.eui.nodes[path] or host.eui.node(path)
  node:set_visible(false)

  s:effect("CoverageDisplay.Circle:" .. path, function(sb)
    local value
    if type(circle) == "table" and type(circle.now) == "function" then
      value = sb:d(circle)
    else
      value = circle
    end

    if not value or value.radius <= 0 then
      node:set_visible(false)
      return
    end

    node:set_visible(true)
    node:set_ring(value.center, value.radius)
    node:set_color(render_util.colour_value(sb, opts.colour))
  end)

  s:on_cleanup(function()
    host.eui.destroy(node)
  end)
end

return CoverageDisplay
