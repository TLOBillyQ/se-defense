-- tools/acceptance/steps_overlays.lua — 覆盖圈与链路步骤（overlays.feature，
-- GDD 13 O1–O6）：链路线/覆盖圈/供电圈/高亮环/预览圆的计数与读取。
-- 形状统一从 host.eui.shapes() 读（ring 是快照状态、line 是就地渲染的单位）；
-- 链路线 = board/power_links（默认整树）与 board/hover_link（悬停链），
-- 覆盖圈 = board/hover_coverage 与 board/placement_coverage，
-- 供电圈 = board/placement_power，高亮环 = board/hover_ring，
-- 预览圆 = board/placement_footprint。
local S = require("tools.acceptance.steps_support")
local headless, needs_session = S.headless, S.needs_session

local function is_live(sh)
  return sh.visible == true
end

local function lines(s)
  local out = {}
  for _, sh in ipairs(headless.shapes(s)) do
    if sh.kind == "line" and is_live(sh)
      and (sh.path:find("^board/power_links") or sh.path:find("^board/hover_link")) then
      out[#out + 1] = sh
    end
  end
  return out
end

local function circles(s, prefixes)
  local out = {}
  for _, sh in ipairs(headless.shapes(s)) do
    if sh.kind == "ring" and is_live(sh) then
      for _, prefix in ipairs(prefixes) do
        if sh.path:find("^" .. prefix) then
          out[#out + 1] = sh
          break
        end
      end
    end
  end
  return out
end

local function coverage_circles(s)
  return circles(s, { "board/hover_coverage", "board/placement_coverage" })
end

local function supply_circles(s)
  return circles(s, { "board/placement_power" })
end

local function find_circle(list, x, z)
  for _, c in ipairs(list) do
    local center = c.center
    if center and math.abs(center.x - tonumber(x)) < S.EPS
      and math.abs(center.z - tonumber(z)) < S.EPS then
      return c
    end
  end
  return nil
end

local function expect_count(actual, expect, label)
  if actual == tonumber(expect) then return true end
  return nil, string.format("%s期望 %s，实际 %s", label, expect, actual)
end

-- 预览圆节点（形状唯一，路径固定）。
local function preview_shape(s)
  for _, sh in ipairs(headless.shapes(s, "board/placement_footprint")) do
    if sh.kind == "ring" and is_live(sh) then return sh end
  end
  return nil
end

local function ring_shape(s)
  for _, sh in ipairs(headless.shapes(s, "board/hover_ring")) do
    if sh.kind == "ring" and is_live(sh) then return sh end
  end
  return nil
end

return { patterns = {
  { "^链路线数量为(%d+)$", needs_session(function(w, s, n)
      return expect_count(#lines(s), n, "链路线数量") end) },
  { "^存在一条连接%((%-?[%d.]+),(%-?[%d.]+)%)与%((%-?[%d.]+),(%-?[%d.]+)%)的链路线$",
    needs_session(function(w, s, ax, az, bx, bz)
      for _, l in ipairs(lines(s)) do
        if l.from and l.to
          and math.abs(l.from.x - tonumber(ax)) < S.EPS and math.abs(l.from.z - tonumber(az)) < S.EPS
          and math.abs(l.to.x - tonumber(bx)) < S.EPS and math.abs(l.to.z - tonumber(bz)) < S.EPS then
          return true
        end
      end
      return nil, string.format("没有连接(%s,%s)与(%s,%s)的链路线", ax, az, bx, bz) end) },
  { "^覆盖圈数量为(%d+)$", needs_session(function(w, s, n)
      return expect_count(#coverage_circles(s), n, "覆盖圈数量") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的覆盖圈半径为([%d.]+)$",
    needs_session(function(w, s, x, z, r)
      local c = find_circle(coverage_circles(s), x, z)
      if not c then return nil, string.format("(%s,%s) 处没有覆盖圈", x, z) end
      return S.eq_num(c.radius, r, string.format("位于(%s,%s)的覆盖圈半径", x, z)) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的覆盖圈是否显示为(%S+)$",
    needs_session(function(w, s, x, z, expect)
      return S.expect_visible(find_circle(coverage_circles(s), x, z) ~= nil,
        expect, string.format("位于(%s,%s)的覆盖圈显示", x, z)) end) },
  { "^供电圈数量为(%d+)$", needs_session(function(w, s, n)
      return expect_count(#supply_circles(s), n, "供电圈数量") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的供电圈半径为([%d.]+)$",
    needs_session(function(w, s, x, z, r)
      local c = find_circle(supply_circles(s), x, z)
      if not c then return nil, string.format("(%s,%s) 处没有供电圈", x, z) end
      return S.eq_num(c.radius, r, string.format("位于(%s,%s)的供电圈半径", x, z)) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的供电圈是否显示为(%S+)$",
    needs_session(function(w, s, x, z, expect)
      return S.expect_visible(find_circle(supply_circles(s), x, z) ~= nil,
        expect, string.format("位于(%s,%s)的供电圈显示", x, z)) end) },
  { "^高亮环圆心为%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      local ring = ring_shape(s)
      if not ring then return nil, "当前没有高亮环" end
      if math.abs(ring.center.x - tonumber(x)) < S.EPS
        and math.abs(ring.center.z - tonumber(z)) < S.EPS then
        return true
      end
      return nil, string.format("高亮环圆心期望 (%s,%s)，实际 (%s,%s)",
        x, z, ring.center.x, ring.center.z) end) },
  { "^高亮环半径为([%d.]+)$", needs_session(function(w, s, r)
      local ring = ring_shape(s)
      if not ring then return nil, "当前没有高亮环" end
      if math.abs(ring.radius - tonumber(r)) <= S.COLOR_TOL then return true end
      return nil, string.format("高亮环半径期望 %s，实际 %s", r, ring.radius) end) },
  { "^高亮环是否显示为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(ring_shape(s) ~= nil, expect, "高亮环显示") end) },
  { "^预览圆是否显示为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(preview_shape(s) ~= nil, expect, "预览圆显示") end) },
  { "^预览圆圆心为%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, x, z)
      local p = preview_shape(s)
      if not p then return nil, "当前没有预览圆" end
      if math.abs(p.center.x - tonumber(x)) < S.EPS
        and math.abs(p.center.z - tonumber(z)) < S.EPS then
        return true
      end
      return nil, string.format("预览圆圆心期望 (%s,%s)，实际 (%s,%s)",
        x, z, p.center.x, p.center.z) end) },
  { "^预览圆半径为([%d.]+)$", needs_session(function(w, s, r)
      local p = preview_shape(s)
      if not p then return nil, "当前没有预览圆" end
      if math.abs(p.radius - tonumber(r)) <= S.COLOR_TOL then return true end
      return nil, string.format("预览圆半径期望 %s，实际 %s", r, p.radius) end) },
} }
