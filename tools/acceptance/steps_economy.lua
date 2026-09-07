-- tools/acceptance/steps_economy.lua — 经济步骤（economy.feature，GDD 02
-- R1–R8）：矿点剩余量读取/设定、采集速率、进攻期停采/恢复编排。
-- 「进入进攻期」「本波全灭」「剩余量设为 N」是编排动作，经 GM 面直达。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, find_site = S.headless, S.needs_session, S.find_site

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量为([%d.]+)$",
    needs_session(function(w, s, x, z, expect)
      local site, bad = find_site(s, x, z)
      if not site then return nil, bad end
      return S.eq_num(site.remaining:now(), expect,
        string.format("位于(%s,%s)的矿点剩余量", x, z)) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量设为([%d.]+)$",
    needs_session(function(w, s, x, z, n)
      local site, bad = find_site(s, x, z)
      if not site then return nil, bad end
      headless.gm(s, "set_site", tonumber(x), tonumber(z), tonumber(n))
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量与推进前相同$",
    needs_session(function(w, s, x, z)
      if not w.before then return nil, "尚未推进（缺「与推进前相同」的基准）" end
      local site, bad = find_site(s, x, z)
      if not site then return nil, bad end
      for _, b in ipairs(w.before.sites) do
        if math.abs(b.x - tonumber(x)) < S.EPS and math.abs(b.z - tonumber(z)) < S.EPS then
          if site.remaining:now() == b.remaining then return true end
          return nil, string.format("位于(%s,%s)的矿点剩余量期望与推进前 %s 相同，实际 %s",
            x, z, b.remaining, site.remaining:now())
        end
      end
      return nil, string.format("推进前 (%s,%s) 处没有矿点记录", x, z) end) },
  { "^采集速率为([%d.]+)$", needs_session(function(w, s, expect)
      return S.near_num(headless.collect_rate(s), expect, "采集速率") end) },
  { "^进入进攻期$", needs_session(function(w, s)
      headless.gm(s, "enter_assault")
      return true end) },
  { "^本波全灭$", needs_session(function(w, s)
      headless.gm(s, "wave_cleared")
      return true end) },
} }
