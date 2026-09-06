-- tests/properties/economy_prop.lua — server.game.economy 的性质测试。
-- 覆盖维度：守恒（资金增量 == 采集单位数）、不变式（在场矿点剩余量界）、
-- 冻结（进攻期停采且恢复后账目继续对上）、宽输入范围（任意 dt 序列）。
-- 只推进与切换进攻期，不放置，资金账目因此只含采集侧。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local world = require("server.game.world")

prop.seed(11)

local SITE_N = 27

-- 采出总量 = 在场矿点已采 + 离场矿点各 300。
local function harvested(g)
  local total = (SITE_N - g.entities:count_sites()) * world.site_remaining
  for _, e in ipairs(g.entities.list) do
    if e.kind == "Site" then total = total + (world.site_remaining - e.remaining) end
  end
  return total
end

-- E1 守恒：资金增量恒等于采出单位数（1 单位 = $1）。
prop.check("E1 资金增量 == 采出单位数", 150, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 40) do
    g.wave.assault = prop.int(1, 4) == 1 -- 间歇切换进攻期
    g:advance(prop.number(0.01, 3))
    if g.mode ~= "Playing" then return true end -- 全部采空转胜利即停
    if g.money - world.starting_money ~= harvested(g) then
      return nil, string.format("账不平: 资金增量 %d，采出 %d",
        g.money - world.starting_money, harvested(g))
    end
  end
  return true
end)

-- E2 不变式：在场矿点剩余量恒为 [1, 初始量] 的整数（采空即离场，不为负）。
prop.check("E2 矿点剩余量界", 150, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 40) do
    g:advance(prop.number(0.01, 3))
    for _, e in ipairs(g.entities.list) do
      if e.kind == "Site" then
        if e.remaining < 1 or e.remaining > world.site_remaining
          or e.remaining ~= math.floor(e.remaining) then
          return nil, "剩余量越界: " .. tostring(e.remaining)
        end
      end
    end
    if g.mode ~= "Playing" then return true end
  end
  return true
end)

-- E3 冻结：进攻期推进任意时长，资金与矿点剩余量不变；恢复后账目继续成立。
prop.check("E3 进攻期停采冻结", 150, function()
  local g = match_flow.new()
  g:start()
  g:advance(prop.number(0.01, 2)) -- 先采一段，让计时器有余量
  local money0 = g.money
  local snap = {}
  for _, e in ipairs(g.entities.list) do
    if e.kind == "Site" then snap[e.id] = e.remaining end
  end
  g.wave.assault = true
  g:advance(prop.number(0.01, 10))
  if g.money ~= money0 then return nil, "进攻期资金变化: " .. g.money end
  for _, e in ipairs(g.entities.list) do
    if e.kind == "Site" and e.remaining ~= snap[e.id] then
      return nil, "进攻期矿点被采: " .. e.id
    end
  end
  g.wave.assault = false
  g:advance(prop.number(0.01, 3))
  if g.mode == "Playing" and g.money - world.starting_money ~= harvested(g) then
    return nil, "恢复后账不平"
  end
  return true
end)
