-- Unit tests for the shape leg of the dual routing (CONTEXT.md「双路由」):
-- set_ring/set_line 形状不进快照，由服务端就地渲为 EffectUnit。适配器按
-- 内容对形状集合做增量 reconcile（创建/销毁/复用），只依赖 World 服务接缝。
local lu = require("luaunit")
local shapes = require("server.adapter.shapes")

local function fake_world()
  return { units = {},
    CreateUnit = function(self, kind, props)
      local u = { kind = kind, props = props, destroyed = false,
        Destroy = function(self) self.destroyed = true end }
      self.units[#self.units + 1] = u
      return u
    end }
end

local function alive(world)
  local n = 0
  for _, u in ipairs(world.units) do if not u.destroyed then n = n + 1 end end
  return n
end

TestShapesRouter = {}

-- 相同形状集合不重造；新增创建、消失销毁。
function TestShapesRouter.test_reconcile_create_reuse_destroy()
  local world = fake_world()
  local r = shapes.new(world)
  local one = { lines = { { ax = 0, az = 3, bx = 0, bz = 0 } }, circles = {} }
  r:render(one)
  lu.assertEquals(alive(world), 1)
  local first = world.units[1]
  r:render(one) -- 同内容复用
  lu.assertEquals(alive(world), 1)
  lu.assertFalse(first.destroyed)
  r:render({ lines = { { ax = 0, az = 3, bx = 0, bz = 0 },
    { ax = 0, az = 5, bx = 0, bz = 3 } }, circles = {} })
  lu.assertEquals(alive(world), 2)
  r:render({ lines = {}, circles = {} }) -- 全部消失
  lu.assertEquals(alive(world), 0)
end

-- 圆/环/预览圆都渲为 EffectUnit，坐标与半径进 props。
function TestShapesRouter.test_all_shape_kinds_become_effect_units()
  local world = fake_world()
  local r = shapes.new(world)
  r:render({
    lines = { { ax = 0, az = 3, bx = 0, bz = 0 } },
    circles = { { x = 2, z = 0, r = 5 } },
    supply = { { x = 0, z = 0, r = 4 } },
    ring = { x = 0, z = 5.5, r = 0.6 },
    preview = { x = 0, z = 2, r = 0.4, legal = true },
  })
  lu.assertEquals(alive(world), 5)
  for _, u in ipairs(world.units) do lu.assertEquals(u.kind, "EffectUnit") end
end
