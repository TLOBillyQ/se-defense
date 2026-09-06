-- tests/properties/waves_prop.lua — server.game.waves 的性质测试。
-- 覆盖维度：守恒（预算对平）、不变式（层级上限、生成点帖边界、方向公布
-- 阈值）、波次推进（全灭才进下一波）。随机取经对局的 match.rng01（默认
-- math.random，与本 harness 同一种子流）。只自动生成，不编排生成。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local waves = require("server.game.waves")
local enemies = require("server.game.enemies")
local world = require("server.game.world")

prop.seed(17)

local function tier_cap_of(n)
  return n >= world.wave.tier3_wave and 3 or n >= world.wave.tier2_wave and 2 or 1
end

local EDGE = world.board.max + world.wave.spawn_offboard

-- W-P1 不变式：波次推进中预算对平、生成层级不超波号上限、生成点帖边界外 6。
prop.check("W-P1 预算守恒 / 层级上限 / 生成位置", 50, function()
  local g = match_flow.new()
  g:start()
  local n = prop.int(1, 9)
  waves.set_wave(g, n)
  local budget = world.wave.budget_base + (n - 1)
  for _ = 1, 400 do
    if g.wave.spawn_done then break end
    waves.tick(g, 0.25) -- 只生成不移动：生成位置须恰好在边界
    if math.abs(g.wave.cost_sum + g.wave.budget_left - budget) > 1e-9 then
      return nil, string.format("预算对不平: %.3f + %.3f != %d",
        g.wave.cost_sum, g.wave.budget_left, budget)
    end
  end
  if not g.wave.spawn_done then return nil, "400 拍后预算仍未耗尽" end
  for _, e in ipairs(g.enemies.list) do
    if e.tier > tier_cap_of(n) then
      return nil, string.format("第 %d 波生成 %d 型敌人", n, e.tier)
    end
    local on_x = math.abs(math.abs(e.x) - EDGE) < 1e-9
    local on_z = math.abs(math.abs(e.z) - EDGE) < 1e-9
    if on_x == on_z then return nil, string.format("生成点不在边界: %.2f, %.2f", e.x, e.z) end
    local along = on_x and e.z or e.x
    if math.abs(along) > world.board.max + 1e-9 then
      return nil, "生成点另一轴出棋盘: " .. along
    end
  end
  if #g.enemies.list == 0 then return nil, "预算耗尽但未生成任何敌人" end
  return true
end)

-- W-P2 不变式：倒计时 > 5 秒方向未知，≤ 5 秒公布为四边之一。
prop.check("W-P2 方向公布阈值", 100, function()
  local g = match_flow.new()
  g:start()
  local valid = { ["东"] = true, ["南"] = true, ["西"] = true, ["北"] = true }
  while g.wave.countdown > 0 do
    g:advance(prop.number(0.05, 2))
    local d = waves.revealed_direction(g)
    if g.wave.countdown > world.wave.reveal_at then
      if d ~= nil then return nil, "倒计时 >5 秒方向已公布: " .. tostring(d) end
    elseif d == nil or not valid[d] then
      return nil, "倒计时 ≤5 秒方向未公布或非法: " .. tostring(d)
    end
  end
  return true
end)

-- W-P3 波次推进：生成完毕且全灭后才进下一波（波号 +1、倒计时重置、方向重抽）。
prop.check("W-P3 全灭才推进下一波", 50, function()
  local g = match_flow.new()
  g:start()
  local n = prop.int(1, 5)
  waves.set_wave(g, n)
  for _ = 1, 400 do
    if g.wave.spawn_done then break end
    g:advance(0.25)
  end
  if not g.wave.spawn_done then return nil, "预算未耗尽" end
  for _, e in ipairs(g.enemies.list) do enemies.kill(e) end
  g:advance(0.1)
  if g.wave.number ~= n + 1 then return nil, "波号未推进: " .. g.wave.number end
  -- 转换当拍倒计时继续走本拍 dt，窗口含它
  if g.wave.countdown > world.wave.calm or g.wave.countdown <= world.wave.calm - 0.1 - 1e-9 then
    return nil, "倒计时未重置: " .. g.wave.countdown
  end
  if #g.wave.spawn_log ~= 0 then return nil, "生成簿记未清空" end
  if g.wave.assault then return nil, "新一波仍在进攻期" end
  return true
end)
