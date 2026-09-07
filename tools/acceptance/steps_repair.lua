-- tools/acceptance/steps_repair.lua — 维修步骤（repair.feature，GDD 06
-- R1–R7）：带血量的编排造建筑、血量读取（±0.05，feature 约定）。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, known_kind, find_building =
  S.headless, S.needs_session, S.known_kind, S.find_building

return { patterns = {
  { "^一座血量为([%d.]+)的(%w+)位于%((%-?[%d.]+),(%-?[%d.]+)%)$",
    needs_session(function(w, s, hp, kind, x, z)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      headless.gm(s, "spawn_building", kind, tonumber(x), tonumber(z), tonumber(hp))
      return true end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血量为([%d.]+)$",
    needs_session(function(w, s, x, z, kind, hp)
      local b, bad = find_building(s, kind, x, z)
      if not b then return nil, bad end
      return S.near_num(headless.building_hp(b), hp,
        string.format("位于(%s,%s)的%s血量", x, z, kind)) end) },
} }
