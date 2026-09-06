-- tests/properties/fire_prop.lua — server.game.fire + detection 的性质测试。
-- 覆盖维度：负需求（未揭示不掉血）、守恒（伤害以 0.5 为量子、血量不为负、
-- 死即血量归零）、宽输入范围（随机层级）。敌人航线指向 Core（评分选中
-- Core），双 Turret 保证任意层级都先于 Core 被炸毁前完成击杀。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local enemies = require("server.game.enemies")
local world = require("server.game.world")

prop.seed(23)

-- F-P1：未揭示的敌人毫发无损；揭示 + 射程 + 通电后按 0.5 量子掉血直至死亡。
prop.check("F-P1 揭示才掉血 / 伤害量子化", 100, function()
  local g = match_flow.new()
  g:start()
  g.wave.countdown = 9999 -- 冻结自动生成
  g.entities:add_building("Turret", 3, 0) -- Core 供电圈内，通电
  g.entities:add_building("Turret", -3, 0)
  local tier = prop.int(1, 3)
  local full = world.enemy_tiers[tier].health
  local e = enemies.spawn(g, { x = 6, z = 4, tier = tier, heading = { x = -0.8321, z = -0.5547 } })
  -- 阶段一：无 Radar，未揭示，推进后血量不动
  for _ = 1, 30 do g:advance(0.1) end
  if e.health ~= full then return nil, "未揭示却被打掉血: " .. e.health end
  if e.revealed then return nil, "无 Radar 却被揭示" end
  -- 阶段二：补上通电 Radar，敌人被揭示并被击毙
  g.entities:add_building("Radar", 0, 3)
  for i = 1, 300 do
    if not e.alive then break end
    g:advance(0.1)
    if e.health < 0 then return nil, "血量为负: " .. e.health end
    local lost = full - e.health
    if math.abs(lost / world.fire_damage - math.floor(lost / world.fire_damage + 0.5)) > 1e-6 then
      return nil, "伤害非 0.5 量子: " .. e.health
    end
    if e.alive ~= (e.health > 0) then
      return nil, string.format("生死与血量不一致: alive=%s health=%s",
        tostring(e.alive), e.health)
    end
    if i == 300 then return nil, "300 拍后敌人仍未被击毙" end
  end
  if e.alive or e.health ~= 0 then return nil, "死亡终态不一致" end
  return true
end)
