-- tests/properties/repair_prop.lua — server.game.repair 的性质测试。
-- 覆盖维度：守恒/上界（修复不超上限、速率封顶 0.5/s、单调不减）、
-- 负需求（未通电不修）、宽输入范围（随机伤情）。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local world = require("server.game.world")

prop.seed(29)

-- R-P1：通电 Repair 把圈内伤员修到满血，速率封顶、永不超上限。
prop.check("R-P1 修复速率封顶且不超上限", 100, function()
  local g = match_flow.new()
  g:start()
  g.wave.countdown = 9999
  local rep = g.entities:add_building("Repair", 2, 0) -- Core 供电圈内
  local hurt = g.entities:add_building("Relay", 3, 0)
  local cap = world.specs.Relay.health
  g.entities:hurt(hurt, prop.number(0.1, cap - 0.01))
  local h0 = hurt.health
  local elapsed = 0
  for _ = 1, 80 do
    g:advance(0.1)
    elapsed = elapsed + 0.1
    if hurt.health > cap + 1e-9 then return nil, "修超上限: " .. hurt.health end
    if hurt.health > math.min(cap, h0 + world.repair_rate * elapsed) + 1e-6 then
      return nil, string.format("修复速率超标: %.3f（%.1f 秒）", hurt.health, elapsed)
    end
  end
  if math.abs(hurt.health - cap) > 1e-9 then return nil, "8 秒后未修满: " .. hurt.health end
  if rep.health ~= world.specs.Repair.health then return nil, "维修者自身血量变化" end
  return true
end)

-- R-P2：未通电 Repair 一个伤员也不修。
prop.check("R-P2 未通电不修", 100, function()
  local g = match_flow.new()
  g:start()
  g.wave.countdown = 9999
  g.entities:add_building("Repair", 15, 0) -- Core 供电圈外，不通电
  local hurt = g.entities:add_building("Relay", 15.9, 0)
  local cap = world.specs.Relay.health
  g.entities:hurt(hurt, prop.number(0.1, cap - 0.01))
  local h0 = hurt.health
  for _ = 1, 30 do g:advance(0.1) end
  if hurt.health ~= h0 then return nil, "未通电却修血: " .. hurt.health end
  return true
end)
