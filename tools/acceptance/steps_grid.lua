-- tools/acceptance/steps_grid.lua — 电网步骤（power-grid.feature，03 R1–R10）：
-- 通电读取、供电者读取、摧毁（直接离场）、炸弹伤害。
local S = require("tools.acceptance.steps_support")
local needs_match, expect_yes_no, find_at, EPS = S.needs_match, S.expect_yes_no, S.find_at, S.EPS

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)是否通电为(%S+)$", needs_match(function(w, m, x, z, kind, expect)
      local e, bad_e = find_at(m, kind, x, z)
      if not e then return nil, bad_e end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m.grid:powered(e) == want then return true end
      return nil, string.format("位于(%s,%s)的%s通电期望 %s，实际 %s",
        x, z, kind, expect, m.grid:powered(e) and "是" or "否") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)被摧毁$", needs_match(function(w, m, x, z, kind)
      local e, bad = find_at(m, kind, x, z)
      if not e then return nil, bad end
      m.entities:remove(e) -- 编排动作：摧毁即离场，不经碎裂
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)的供电者位于%((%-?[%d.]+),(%-?[%d.]+)%)$",
    needs_match(function(w, m, x, z, kind, px, pz)
      local e, bad = find_at(m, kind, x, z)
      if not e then return nil, bad end
      local p = m.grid:provider(e)
      if not p then return nil, string.format("位于(%s,%s)的%s没有供电者", x, z, kind) end
      if math.abs(p.x - tonumber(px)) < EPS and math.abs(p.z - tonumber(pz)) < EPS then
        return true
      end
      return nil, string.format("位于(%s,%s)的%s的供电者期望位于(%s,%s)，实际位于(%s,%s)",
        x, z, kind, px, pz, p.x, p.z) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)受到炸弹伤害([%d.]+)$", needs_match(function(w, m, x, z, kind, dmg)
      local e, bad = find_at(m, kind, x, z)
      if not e then return nil, bad end
      m.entities:hurt(e, tonumber(dmg))
      return true end) },
} }
