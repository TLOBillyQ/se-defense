-- tests/properties/match_flow_prop.lua — server.game.match_flow 的性质测试。
-- 覆盖维度：不变式（倒计时下界、实体计数一致）、守恒（资金）、
-- 冻结/幂等（非 Playing 与终态吸收）、宽输入范围（任意 dt 与随机操作序列）。
-- 性质直接驱动纯规则层模块；宿主固定步长只是 dt 的取值之一。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local world = require("server.game.world")

prop.seed(42)

local BUILDABLE = { "Relay", "Radar", "Turret", "Repair" }
local KINDS = { "Relay", "Radar", "Turret", "Repair", "Core", "Bogus" }

local function random_xy()
  return prop.number(world.board.min, world.board.max),
         prop.number(world.board.min, world.board.max)
end

-- P1 不变式：Playing 中任意 dt 序列下，波次倒计时单调不增且不为负。
prop.check("P1 倒计时单调不增且不为负", 200, function()
  local g = match_flow.new()
  g:start()
  local prev = g.wave.countdown
  for _ = 1, prop.int(1, 50) do
    g:advance(prop.number(0, 10))
    local c = g.wave.countdown
    if c < 0 then return nil, "倒计时为负: " .. c end
    if c > prev + 1e-9 then return nil, string.format("倒计时回升: %s -> %s", prev, c) end
    prev = c
  end
  return true
end)

-- P2 冻结：Pregame 中任意推进/放置操作序列不改变阶段、资金、倒计时与布局。
prop.check("P2 Pregame 时间冻结", 200, function()
  local g = match_flow.new()
  local n0 = #g.entities.list
  for _ = 1, prop.int(1, 30) do
    local op = prop.int(1, 3)
    if op == 1 then
      g:advance(prop.number(0, 120))
    elseif op == 2 then
      local x, z = random_xy()
      g:place(prop.pick(KINDS), x, z)
    else
      g:restart()
    end
    if g.mode ~= "Pregame" then return nil, "阶段漂移: " .. g.mode end
    if g.money ~= 0 then return nil, "资金漂移: " .. g.money end
    if g.wave.countdown ~= world.first_wave_countdown then
      return nil, "倒计时漂移: " .. g.wave.countdown
    end
    if #g.entities.list ~= n0 then return nil, "实体数漂移: " .. #g.entities.list end
  end
  return true
end)

-- P3 守恒：Playing 中资金只被成功放置按价扣减，永不为负，账目可对平。
prop.check("P3 资金守恒", 200, function()
  local g = match_flow.new()
  g:start()
  local expected = world.starting_money
  local placed = 0
  for _ = 1, prop.int(1, 60) do
    local kind = prop.pick(KINDS)
    local spec = world.specs[kind]
    local price = spec and spec.price
    local x, z = random_xy()
    local affordable = price and expected >= price
    g:place(kind, x, z)
    if affordable then
      expected = expected - price
      placed = placed + 1
    end
    if g.money ~= expected then
      return nil, string.format("资金对不平: 期望 %s 实际 %s", expected, g.money)
    end
    if g.money < 0 then return nil, "资金为负: " .. g.money end
  end
  if g.entities:count_buildings() ~= 1 + placed then
    return nil, string.format("建筑数对不平: 期望 %d 实际 %d", 1 + placed, g.entities:count_buildings())
  end
  return true
end)

-- P4 不变式：任意编排/推进操作序列后，建筑数 + 矿点数 == 实体总数。
prop.check("P4 实体计数一致", 200, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 40) do
    local op = prop.int(1, 4)
    if op == 1 then
      g.entities:kill(prop.pick(KINDS))
    elseif op == 2 then
      g.entities:deplete_sites(prop.int(0, 6))
    elseif op == 3 then
      local x, z = random_xy()
      g.entities:add_building(prop.pick(BUILDABLE), x, z)
    else
      g:advance(prop.number(0, 10))
    end
    if g.entities:count_sites() + g.entities:count_buildings() ~= #g.entities.list then
      return nil, string.format("计数不一致: %d + %d != %d",
        g.entities:count_sites(), g.entities:count_buildings(), #g.entities.list)
    end
  end
  return true
end)

-- P5 幂等：终态（Victory/GameOver）吸收后续推进与玩家意图，阶段不变。
prop.check("P5 终态吸收", 200, function()
  local g = match_flow.new()
  g:start()
  if prop.int(1, 2) == 1 then
    g.entities:deplete_sites(g.entities:count_sites())
    g:advance(1)
    if g.mode ~= "Victory" then return nil, "未到 Victory: " .. g.mode end
  else
    g.entities:kill("Core")
    g:advance(world.crumble_seconds + 1)
    if g.mode ~= "GameOver" then return nil, "未到 GameOver: " .. g.mode end
  end
  local final = g.mode
  for _ = 1, prop.int(1, 20) do
    local op = prop.int(1, 3)
    if op == 1 then
      g:advance(prop.number(0, 120))
    elseif op == 2 then
      local x, z = random_xy()
      g:place(prop.pick(KINDS), x, z)
    else
      g:start()
    end
    if g.mode ~= final then
      return nil, string.format("终态漂移: %s -> %s", final, g.mode)
    end
  end
  return true
end)
