-- tools/acceptance/steps_fire.lua — 侦测与火力编排步骤（detection-fire.feature，
-- GDD 05）：设定 Turret 枪口初始朝向。读取类步骤（揭示/血量/存活）在
-- steps_waves.lua，通电读取在 steps_grid.lua。
local S = require("tools.acceptance.steps_support")
local needs_match, find_at = S.needs_match, S.find_at

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)枪口朝(%S+)$",
    needs_match(function(w, m, x, z, kind, dir_name)
      local e, bad = find_at(m, kind, x, z)
      if not e then return nil, bad end
      local heading = require("server.game.world").direction(dir_name)
      if not heading then return nil, "未知方向: " .. dir_name end
      require("server.game.fire").set_muzzle(e, heading)
      return true end) },
} }
