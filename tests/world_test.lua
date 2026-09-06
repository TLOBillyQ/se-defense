-- Unit tests for src/server/game/world.lua: the centralized world data table
-- (docs/gdd/00-world.md). Board 40×40, Core + 27 site coordinates, entity
-- spec table (health/footprint/provide/receive/range/price).
local lu = require("luaunit")
local world = require("server.game.world")

TestWorld = {}

function TestWorld.test_board_is_40x40_centered_at_origin()
  lu.assertEquals(world.board.min, -20)
  lu.assertEquals(world.board.max, 20)
end

function TestWorld.test_starting_money_and_wave_lull()
  lu.assertEquals(world.starting_money, 100)
  lu.assertEquals(world.first_wave_countdown, 30)
end

function TestWorld.test_building_specs_match_gdd_table()
  lu.assertEquals(world.specs.Core.health, 10)
  lu.assertEquals(world.specs.Core.footprint, 0.5)
  lu.assertEquals(world.specs.Core.provide, 4)
  lu.assertNil(world.specs.Core.price)
  lu.assertEquals(world.specs.Relay.health, 2)
  lu.assertEquals(world.specs.Relay.price, 10)
  lu.assertEquals(world.specs.Relay.provide, 3)
  lu.assertEquals(world.specs.Radar.range, 8)
  lu.assertEquals(world.specs.Radar.price, 50)
  lu.assertEquals(world.specs.Turret.health, 5)
  lu.assertEquals(world.specs.Turret.range, 5)
  lu.assertEquals(world.specs.Repair.range, 5)
  lu.assertEquals(world.specs.Repair.price, 100)
  lu.assertEquals(world.specs.Site.footprint, 0.5)
  lu.assertEquals(world.specs.Site.receive, 0.5)
  lu.assertNil(world.specs.Site.health)
end

function TestWorld.test_initial_layout_has_core_at_origin_and_27_sites()
  lu.assertEquals(world.core.x, 0)
  lu.assertEquals(world.core.z, 0)
  lu.assertEquals(#world.sites, 27)
  lu.assertEquals(world.site_remaining, 300)
  for _, s in ipairs(world.sites) do
    lu.assertTrue(math.abs(s.x) <= 20 and math.abs(s.z) <= 20,
      "矿点超出棋盘: " .. s.x .. "," .. s.z)
  end
end

function TestWorld.test_gdd_site_coordinates_present()
  local want = { { 1.71, 0.06 }, { -1.30, -1.26 }, { -1.99, -0.10 } }
  for _, w in ipairs(want) do
    local found = false
    for _, s in ipairs(world.sites) do
      if s.x == w[1] and s.z == w[2] then found = true end
    end
    lu.assertTrue(found, "缺矿点坐标 " .. w[1] .. "," .. w[2])
  end
end

-- 方向名查找：四个名字各有向量，未知名为 nil。
function TestWorld.test_direction_lookup_by_name()
  lu.assertEquals(world.direction("北"), { name = "北", x = 0, z = 1 })
  lu.assertEquals(world.direction("西").x, -1)
  lu.assertNil(world.direction("上"))
end
