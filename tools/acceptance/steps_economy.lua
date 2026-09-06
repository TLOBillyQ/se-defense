-- tools/acceptance/steps_economy.lua — 经济与矿点步骤（economy.feature，02 R1–R8）：
-- 矿点剩余量读写、进攻期开始/全灭、采集速率。
local S = require("tools.acceptance.steps_support")
local needs_match, find_at, EPS = S.needs_match, S.find_at, S.EPS

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量为(%d+)$", needs_match(function(w, m, x, z, expect)
      local e, bad = find_at(m, "Site", x, z)
      if not e then return nil, bad end
      if e.remaining == tonumber(expect) then return true end
      return nil, string.format("位于(%s,%s)的矿点剩余量期望 %s，实际 %s",
        x, z, expect, e.remaining) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量设为(%d+)$", needs_match(function(w, m, x, z, n)
      local e, bad = find_at(m, "Site", x, z)
      if not e then return nil, bad end
      e.remaining = tonumber(n)
      if e.remaining <= 0 then m.entities:remove(e) end -- 设为 0 即离场
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的矿点剩余量与推进前相同$", needs_match(function(w, m, x, z)
      if not w.before or not w.before.sites then
        return nil, "尚未推进（缺「与推进前相同」的基准）"
      end
      local e, bad = find_at(m, "Site", x, z)
      if not e then return nil, bad end
      for _, b in ipairs(w.before.sites) do
        if math.abs(b.x - e.x) < EPS and math.abs(b.z - e.z) < EPS then
          if e.remaining == b.remaining then return true end
          return nil, string.format("位于(%s,%s)的矿点剩余量期望与推进前 %s 相同，实际 %s",
            x, z, b.remaining, e.remaining)
        end
      end
      return nil, string.format("推进前 (%s,%s) 处没有矿点记录", x, z) end) },
  { "^进入进攻期$", needs_match(function(w, m)
      m.wave.assault = true
      return true end) },
  { "^本波全灭$", needs_match(function(w, m)
      require("server.game.enemies").kill_all(m)
      m.wave.assault = false
      return true end) },
  { "^采集速率为([%d.]+)$", needs_match(function(w, m, expect)
      local actual = m.economy:rate()
      if math.abs(actual - tonumber(expect)) <= EPS then return true end
      return nil, string.format("采集速率期望 %s，实际 %s", expect, actual) end) },
} }
