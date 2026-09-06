-- tools/acceptance/steps_repair.lua — 维修编排步骤（repair.feature，GDD 06）：
-- 直接造好一座血量置为 N 的建筑。维修读取走「位于(x,z)的X血量为N」
-- （steps_waves.lua），通电读取在 steps_grid.lua。
local S = require("tools.acceptance.steps_support")
local needs_match, known_kind = S.needs_match, S.known_kind

return { patterns = {
  { "^一座血量为([%d.]+)的(%w+)位于%((%-?[%d.]+),(%-?[%d.]+)%)$",
    needs_match(function(w, m, health, kind, x, z)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      local e = m.entities:add_building(kind, tonumber(x), tonumber(z))
      e.health = tonumber(health)
      return true end) },
} }
