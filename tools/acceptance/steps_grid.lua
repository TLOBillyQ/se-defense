-- tools/acceptance/steps_grid.lua — 电网步骤（power-grid.feature，GDD 03
-- R1–R10）：通电读取、供电者读取、摧毁（编排动作：直接离场，不经碎裂）、
-- 炸弹伤害（死亡走 2 秒碎裂）。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, expect_yes_no, find_building =
  S.headless, S.needs_session, S.expect_yes_no, S.find_building

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)是否通电为(%S+)$",
    needs_session(function(w, s, x, z, kind, expect)
      local b, bad_e = find_building(s, kind, x, z)
      if not b then return nil, bad_e end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if headless.building_power(b) == want then return true end
      return nil, string.format("位于(%s,%s)的%s通电期望 %s，实际 %s",
        x, z, kind, expect, headless.building_power(b) and "是" or "否") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)被摧毁$",
    needs_session(function(w, s, x, z, kind)
      local b, bad = find_building(s, kind, x, z)
      if not b then return nil, bad end
      headless.gm(s, "destroy_at", kind, tonumber(x), tonumber(z))
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)的供电者位于%((%-?[%d.]+),(%-?[%d.]+)%)$",
    needs_session(function(w, s, x, z, kind, px, pz)
      local b, bad = find_building(s, kind, x, z)
      if not b then return nil, bad end
      local p = headless.provider_pos(b)
      if not p then return nil, string.format("位于(%s,%s)的%s没有供电者", x, z, kind) end
      if math.abs(p.x - tonumber(px)) < S.EPS and math.abs(p.z - tonumber(pz)) < S.EPS then
        return true
      end
      return nil, string.format("位于(%s,%s)的%s的供电者期望位于(%s,%s)，实际位于(%s,%s)",
        x, z, kind, px, pz, p.x, p.z) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)受到炸弹伤害([%d.]+)$",
    needs_session(function(w, s, x, z, kind, dmg)
      local b, bad = find_building(s, kind, x, z)
      if not b then return nil, bad end
      headless.gm(s, "bomb_damage", kind, tonumber(x), tonumber(z), tonumber(dmg))
      return true end) },
} }
