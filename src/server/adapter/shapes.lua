-- src/server/adapter/shapes.lua — 形状路由（双路由的服务端一腿，
-- CONTEXT.md「双路由」）。覆盖圈/链路/高亮环/预览圆不进快照，就地渲为
-- EffectUnit（随 Unit 复制到客户端可见）。对每拍算出的形状集合按内容做
-- 增量 reconcile：相同复用、新增创建、消失销毁。只依赖 World 服务接缝
-- （CreateUnit），无头与真宿主同路径运行。
local M = {}

local Router = {}
Router.__index = Router

function M.new(world_service)
  return setmetatable({ world = world_service, live = {} }, Router)
end

-- 展开形状集合为 keyed 形状表：键内带序号与内容键，内容一致即复用。
local function flatten(shapes)
  local out = {}
  local function put(key, props)
    out[key] = props
  end
  for i, l in ipairs(shapes.lines or {}) do
    put("line" .. i, { shape = "line", ax = l.ax, az = l.az, bx = l.bx, bz = l.bz })
  end
  for i, c in ipairs(shapes.circles or {}) do
    put("circle" .. i, { shape = "circle", x = c.x, z = c.z, r = c.r, kind = c.kind })
  end
  for i, c in ipairs(shapes.supply or {}) do
    put("supply" .. i, { shape = "supply", x = c.x, z = c.z, r = c.r, kind = c.kind })
  end
  if shapes.ring then
    put("ring", { shape = "ring", x = shapes.ring.x, z = shapes.ring.z, r = shapes.ring.r })
  end
  if shapes.preview then
    put("preview", { shape = "preview", x = shapes.preview.x, z = shapes.preview.z,
      r = shapes.preview.r, legal = shapes.preview.legal })
  end
  return out
end

local function props_equal(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- 渲一拍：与在场形状按键对账，内容一致复用，否则销毁重建。
function Router:render(shapes)
  local want = flatten(shapes or {})
  for key, unit in pairs(self.live) do
    if not want[key] or not props_equal(unit._props, want[key]) then
      unit:Destroy()
      self.live[key] = nil
    end
  end
  for key, props in pairs(want) do
    if not self.live[key] then
      local unit = self.world:CreateUnit("EffectUnit", props)
      unit._props = props
      self.live[key] = unit
    end
  end
end

return M
