-- tools/acceptance/steps_fire.lua — 侦测与火力编排步骤（detection-fire.feature，
-- GDD 05）：设定 Turret 枪口初始朝向（设定后保持到首次接敌，见
-- TurretBehaviour.idle 的 muzzle_pinned）。揭示/血量/存活等敌人读取在
-- steps_waves.lua，通电读取在 steps_grid.lua。
local S = require("tools.acceptance.steps_support")
local headless, needs_session = S.headless, S.needs_session

return { patterns = {
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)枪口朝(%S+)$",
    needs_session(function(w, s, x, z, kind, dir_name)
      if kind ~= "Turret" then return nil, "枪口朝向只适用于 Turret，实际 " .. tostring(kind) end
      if not require("server.kernel.world_data").direction(dir_name) then
        return nil, "未知方向: " .. dir_name
      end
      headless.gm(s, "aim_turret", tonumber(x), tonumber(z), dir_name)
      return true end) },
} }
