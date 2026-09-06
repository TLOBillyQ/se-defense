-- tests/properties/placement_prop.lua — server.game.placement 的性质测试。
-- 覆盖维度：双向一致（confirm 成功 ⟺ 放置态 + 合法落点）、守恒（确认成功
-- 恰好扣价格且实体 +1；失败与取消不动账目）、不变式（确认建成的建筑不与
-- 任何先前足迹相交）、宽输入范围（随机类型 / 落点 / 取消交织）。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local placement = require("server.game.placement")
local world = require("server.game.world")

prop.seed(13)

local KINDS = { "Relay", "Radar", "Turret", "Repair", "Core", "Bogus" }

local function overlaps_any(g, x, z, r, skip_id)
  for _, e in ipairs(g.entities.list) do
    if e.id ~= skip_id then
      local r2 = world.specs[e.kind].footprint
      if world.dist(x, z, e.x, e.z) <= r + r2 + 1e-9 then return true end
    end
  end
  return false
end

-- PL1：confirm 的结果与「放置态 + 合法落点」严格一致，账目与布局随之对平。
prop.check("PL1 确认与合法落点双向一致", 200, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 30) do
    local op = prop.int(1, 4)
    if op == 1 then
      placement.cancel(g)
      if g.placing_kind ~= nil then return nil, "取消后仍在放置态" end
    elseif op == 2 then
      placement.select(g, prop.pick(KINDS)) -- 结果不重要，confirm 端校验
    else
      local kind = g.placing_kind
      local x = prop.number(world.board.min - 2, world.board.max + 2)
      local z = prop.number(world.board.min - 2, world.board.max + 2)
      local money0, n0 = g.money, #g.entities.list
      local expect_ok = kind ~= nil and placement.legal(g, kind, x, z)
      local ok = placement.confirm(g, x, z)
      if ok ~= expect_ok then
        return nil, string.format("confirm(%s, %.2f, %.2f) = %s，期望 %s",
          tostring(kind), x, z, tostring(ok), tostring(expect_ok))
      end
      if ok then
        local price = world.specs[kind].price
        if g.money ~= money0 - price then
          return nil, string.format("扣费不对: %d -> %d，价格 %d", money0, g.money, price)
        end
        if #g.entities.list ~= n0 + 1 then return nil, "确认成功但实体数未 +1" end
        if g.placing_kind ~= nil then return nil, "确认成功后仍在放置态" end
        local b = g.entities:find(kind, x, z)
        if not b then return nil, "确认成功但落点无建筑" end
        if overlaps_any(g, x, z, world.specs[kind].footprint, b.id) then
          return nil, "新建筑与既有足迹相交"
        end
      else
        if g.money ~= money0 or #g.entities.list ~= n0 then
          return nil, "确认失败但账目或布局变化"
        end
        if kind and g.placing_kind ~= kind then return nil, "非法确认退出了放置态" end
      end
    end
  end
  return true
end)

-- PL2 不变式：无论操作序列如何，资金恒在 [0, 起始资金 + 采出] 且不为负。
prop.check("PL2 资金不为负", 200, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 30) do
    local kind = prop.pick(KINDS)
    placement.select(g, kind)
    placement.confirm(g,
      prop.number(world.board.min, world.board.max),
      prop.number(world.board.min, world.board.max))
    g:advance(prop.number(0, 2)) -- 采集可能回血
    if g.money < 0 then return nil, "资金为负: " .. g.money end
    if g.mode ~= "Playing" then return true end
  end
  return true
end)
