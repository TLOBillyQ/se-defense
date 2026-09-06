-- tools/acceptance/steps_overlays.lua — 覆盖圈与链路步骤（overlays.feature，
-- GDD 13 O1–O6）：链路线/覆盖圈/供电圈/高亮环/预览圆的计数与读取。
-- 显示状态经 presenter → overlays.compute 读取（形状不进快照，双路由）。
local S = require("tools.acceptance.steps_support")
local needs_session = S.needs_session
local EPS = S.EPS

local function shapes_of(s)
  return require("server.present.overlays").compute(s.match, s.presenter)
end

local function needs_shapes(fn)
  return needs_session(function(w, s, ...) return fn(w, s, shapes_of(s), ...) end)
end

local function find_circle(list, x, z)
  for _, c in ipairs(list) do
    if math.abs(c.x - tonumber(x)) < EPS and math.abs(c.z - tonumber(z)) < EPS then return c end
  end
  return nil
end

local function expect_count(actual, expect, what)
  if actual == tonumber(expect) then return true end
  return nil, string.format("%s期望 %s，实际 %s", what, expect, actual)
end

return { patterns = {
  { "^链路线数量为(%d+)$", needs_shapes(function(w, s, sh, n)
      return expect_count(#sh.lines, n, "链路线数量") end) },
  { "^存在一条连接%((%-?[%d.]+),(%-?[%d.]+)%)与%((%-?[%d.]+),(%-?[%d.]+)%)的链路线$",
    needs_shapes(function(w, s, sh, ax, az, bx, bz)
      for _, l in ipairs(sh.lines) do
        if math.abs(l.ax - tonumber(ax)) < EPS and math.abs(l.az - tonumber(az)) < EPS
          and math.abs(l.bx - tonumber(bx)) < EPS and math.abs(l.bz - tonumber(bz)) < EPS then
          return true
        end
      end
      return nil, string.format("没有连接(%s,%s)与(%s,%s)的链路线", ax, az, bx, bz) end) },
  { "^覆盖圈数量为(%d+)$", needs_shapes(function(w, s, sh, n)
      return expect_count(#sh.circles, n, "覆盖圈数量") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的覆盖圈半径为([%d.]+)$",
    needs_shapes(function(w, s, sh, x, z, r)
      local c = find_circle(sh.circles, x, z)
      if not c then return nil, string.format("(%s,%s) 处没有覆盖圈", x, z) end
      if math.abs(c.r - tonumber(r)) <= EPS then return true end
      return nil, string.format("位于(%s,%s)的覆盖圈半径期望 %s，实际 %s", x, z, r, c.r) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的覆盖圈是否显示为(%S+)$",
    needs_shapes(function(w, s, sh, x, z, expect)
      local shown = find_circle(sh.circles, x, z) ~= nil
      local want, bad = S.expect_yes_no(expect)
      if bad then return nil, bad end
      if shown == want then return true end
      return nil, string.format("位于(%s,%s)的覆盖圈显示期望 %s，实际 %s",
        x, z, expect, shown and "是" or "否") end) },
  { "^供电圈数量为(%d+)$", needs_shapes(function(w, s, sh, n)
      return expect_count(#sh.supply, n, "供电圈数量") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的供电圈半径为([%d.]+)$",
    needs_shapes(function(w, s, sh, x, z, r)
      local c = find_circle(sh.supply, x, z)
      if not c then return nil, string.format("(%s,%s) 处没有供电圈", x, z) end
      if math.abs(c.r - tonumber(r)) <= EPS then return true end
      return nil, string.format("位于(%s,%s)的供电圈半径期望 %s，实际 %s", x, z, r, c.r) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的供电圈是否显示为(%S+)$",
    needs_shapes(function(w, s, sh, x, z, expect)
      local shown = find_circle(sh.supply, x, z) ~= nil
      local want, bad = S.expect_yes_no(expect)
      if bad then return nil, bad end
      if shown == want then return true end
      return nil, string.format("位于(%s,%s)的供电圈显示期望 %s，实际 %s",
        x, z, expect, shown and "是" or "否") end) },
  { "^高亮环圆心为%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_shapes(function(w, s, sh, x, z)
      if not sh.ring then return nil, "当前没有高亮环" end
      if math.abs(sh.ring.x - tonumber(x)) < EPS and math.abs(sh.ring.z - tonumber(z)) < EPS then
        return true
      end
      return nil, string.format("高亮环圆心期望 (%s,%s)，实际 (%s,%s)", x, z, sh.ring.x, sh.ring.z) end) },
  { "^高亮环半径为([%d.]+)$", needs_shapes(function(w, s, sh, r)
      if not sh.ring then return nil, "当前没有高亮环" end
      if math.abs(sh.ring.r - tonumber(r)) <= 0.01 then return true end
      return nil, string.format("高亮环半径期望 %s，实际 %s", r, sh.ring.r) end) },
  { "^高亮环是否显示为(%S+)$", needs_shapes(function(w, s, sh, expect)
      local want, bad = S.expect_yes_no(expect)
      if bad then return nil, bad end
      if (sh.ring ~= nil) == want then return true end
      return nil, string.format("高亮环显示期望 %s，实际 %s",
        expect, sh.ring ~= nil and "是" or "否") end) },
  { "^预览圆是否显示为(%S+)$", needs_shapes(function(w, s, sh, expect)
      local want, bad = S.expect_yes_no(expect)
      if bad then return nil, bad end
      if (sh.preview ~= nil) == want then return true end
      return nil, string.format("预览圆显示期望 %s，实际 %s",
        expect, sh.preview ~= nil and "是" or "否") end) },
  { "^预览圆圆心为%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_shapes(function(w, s, sh, x, z)
      if not sh.preview then return nil, "当前没有预览圆" end
      if math.abs(sh.preview.x - tonumber(x)) < EPS
        and math.abs(sh.preview.z - tonumber(z)) < EPS then
        return true
      end
      return nil, string.format("预览圆圆心期望 (%s,%s)，实际 (%s,%s)",
        x, z, sh.preview.x, sh.preview.z) end) },
  { "^预览圆半径为([%d.]+)$", needs_shapes(function(w, s, sh, r)
      if not sh.preview then return nil, "当前没有预览圆" end
      if math.abs(sh.preview.r - tonumber(r)) <= 0.01 then return true end
      return nil, string.format("预览圆半径期望 %s，实际 %s", r, sh.preview.r) end) },
  { "^预览圆颜色为(%S+)$", needs_shapes(function(w, s, sh, name)
      if not sh.preview then return nil, "当前没有预览圆" end
      local legal = sh.preview.legal
      local actual = legal and "绿" or "红" -- O3：合法绿 / 非法红
      if actual == name then return true end
      return nil, string.format("预览圆颜色期望 %s，实际 %s", name, actual) end) },
} }
