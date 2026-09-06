-- src/server/game/detection.lua — 侦测（规则真源 docs/gdd/05-detection-fire.md
-- R1/R6）。每拍重算每个存活敌人的揭示状态：足迹圆与任一通电 Radar 的
-- 探测圈（8）相交 ⇒ 已揭示；离开所有探测圈即不再揭示。无状态。
local world = require("server.game.world")

local M = {}

local EPS = 1e-9

function M.tick(match)
  local radars = {}
  for _, r in ipairs(match.entities:alive_of_kind("Radar")) do
    if match.grid:powered(r) then radars[#radars + 1] = r end
  end
  for _, enemy in ipairs(match.enemies.list) do
    if enemy.alive then
      local revealed = false
      for _, r in ipairs(radars) do
        local range = world.specs.Radar.range + enemy.footprint
        if world.dist(r.x, r.z, enemy.x, enemy.z) <= range + EPS then
          revealed = true
          break
        end
      end
      enemy.revealed = revealed
    end
  end
end

return M
