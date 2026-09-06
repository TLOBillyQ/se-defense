-- tests/properties/enemies_prop.lua — server.game.enemies 的性质测试。
-- 覆盖维度：收敛（直飞至停机距离 1.2）、负需求（炸弹不伤矿点、死亡无
-- 奖励）、宽输入范围（随机出生点 / 层级）。冻结波次倒计时与进攻期，
-- 排除自动生成与采集对断言的干扰。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local enemies = require("server.game.enemies")
local world = require("server.game.world")

prop.seed(19)

local function freeze_waves(g)
  g.wave.countdown = 9999
  g.wave.assault = true -- 进攻期停采：资金账目不受采集干扰
end

-- E-P1 收敛：任意出生点直飞目标，最终停在恰好 1.2 处且保持。
prop.check("E-P1 停机距离收敛", 100, function()
  local g = match_flow.new()
  g:start()
  freeze_waves(g)
  local angle = prop.number(0, 2 * math.pi)
  local r = prop.number(10, 18)
  local x, z = r * math.cos(angle), r * math.sin(angle)
  local e = enemies.spawn(g, { x = x, z = z, tier = 1,
    heading = { x = -math.cos(angle), z = -math.sin(angle) } })
  for _ = 1, 200 do
    if e.stopped then break end
    g:advance(0.2)
  end
  if not e.stopped then return nil, "200 拍后仍未停稳" end
  local d = world.dist(e.x, e.z, e.target.x, e.target.z)
  if math.abs(d - world.enemy_stop_distance) > 1e-6 then
    return nil, string.format("停机距离 %.6f != %.1f", d, world.enemy_stop_distance)
  end
  g:advance(3)
  d = world.dist(e.x, e.z, e.target.x, e.target.z)
  if not e.stopped or math.abs(d - world.enemy_stop_distance) > 1e-6 then
    return nil, "停稳后位置漂移: " .. d
  end
  return true
end)

-- E-P2 负需求：炸弹半径内的矿点毫发无损；敌人死亡不给钱。
prop.check("E-P2 矿点免伤 + 死亡无奖励", 100, function()
  local g = match_flow.new()
  g:start()
  freeze_waves(g)
  -- 目标建筑紧贴矿点（1.71, 0.06）：炸弹半径 1.2 必然罩住矿点。
  local relay = g.entities:add_building("Relay", 2.5, 0.1)
  local e = enemies.spawn(g, { x = 7, z = 0.1, tier = 1, heading = { x = -1, z = 0 } })
  local health0 = relay.health
  for _ = 1, 80 do g:advance(0.2) end -- 飞抵 + 多轮投弹
  if relay.health >= health0 then return nil, "目标建筑未被炸（场景未生效）" end
  if g.entities:count_sites() ~= 27 then return nil, "矿点被炸离场" end
  for _, s in ipairs(g.entities.list) do
    if s.kind == "Site" and s.remaining ~= world.site_remaining then
      return nil, "矿点剩余量被炸: " .. s.remaining
    end
  end
  if g.money ~= world.starting_money then return nil, "资金变化: " .. g.money end
  enemies.kill(e)
  g:advance(1)
  if g.money ~= world.starting_money then return nil, "敌人死亡给了钱" end
  return true
end)
