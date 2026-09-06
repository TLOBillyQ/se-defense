-- tests/properties/power_grid_prop.lua — server.game.power_grid 的性质测试。
-- 覆盖维度：结构不变式（供电关系必相交、收敛后通电链必达 Core 且无环）、
-- 宽输入范围（随机建 Relay / 击杀 / 推进序列）。去抖是设计行为：通电
-- 判定只在「收敛」（继续推进超过去抖窗口）后断言。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local world = require("server.game.world")

prop.seed(7)

-- 收敛：以小步推进越过 0.15 秒去抖窗口。
local function settle(g)
  for _ = 1, 10 do g:advance(0.05) end
end

-- G1 不变式：收敛后每个通电的非 Core 实体，供电链上溯必达 Core 且无环。
prop.check("G1 通电链必达 Core 且无环", 150, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(0, 5) do
    local op = prop.int(1, 3)
    if op == 1 then
      g.entities:add_building("Relay",
        prop.number(world.board.min, world.board.max),
        prop.number(world.board.min, world.board.max))
    elseif op == 2 then
      g.entities:kill("Relay")
    end
    settle(g)
  end
  if g.mode ~= "Playing" then return true end -- Relay 之外的失败路径不在本性质范围
  for _, e in ipairs(g.entities.list) do
    if e.kind ~= "Core" and g.grid:powered(e) then
      local seen, cur, hops = {}, e, 0
      while cur and cur.kind ~= "Core" do
        if seen[cur.id] then return nil, "供电链成环于 " .. cur.kind .. "#" .. cur.id end
        seen[cur.id] = true
        hops = hops + 1
        if hops > #g.entities.list then return nil, "供电链超长（疑似环）" end
        cur = g.grid:provider(cur)
      end
      if not cur then
        return nil, "通电实体 " .. e.kind .. "#" .. e.id .. " 的供电链未达 Core"
      end
    end
  end
  return true
end)

-- G2 不变式：任何 tick 之后，每个供电关系都满足相交条件
-- （圆心距 ≤ 供电圈 + 收电圈，含去抖窗口内的过渡态）。
prop.check("G2 供电关系必相交", 150, function()
  local g = match_flow.new()
  g:start()
  for _ = 1, prop.int(1, 6) do
    local op = prop.int(1, 3)
    if op == 1 then
      g.entities:add_building("Relay",
        prop.number(world.board.min, world.board.max),
        prop.number(world.board.min, world.board.max))
    elseif op == 2 then
      g.entities:kill("Relay")
    else
      g:advance(prop.number(0, 1))
    end
    if g.mode ~= "Playing" then return true end
    for _, e in ipairs(g.entities.list) do
      local p = g.grid:provider(e)
      if p then
        local d = world.dist(e.x, e.z, p.x, p.z)
        local limit = world.specs[p.kind].provide + (world.specs[e.kind].receive or 0)
        if d > limit + 1e-9 then
          return nil, string.format("%s#%d 的供电者 %s#%d 不相交: %.3f > %.3f",
            e.kind, e.id, p.kind, p.id, d, limit)
        end
      end
    end
  end
  return true
end)
