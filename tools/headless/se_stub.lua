-- SE 运行时 API 最小桩（无头验证用，#19 一次性版本的可复用化，#21）。
-- 只覆盖 server/main.lua + 适配层用到的面：game:GetService / World:CreateUnit /
-- RunService.Heartbeat / RemoteEvent / Vector3 / Vector2 / Color / Enums。
-- 桩不模拟渲染，只记录属性写入，供断言读取（units 表按 Name 索引）。

local stub = { units = {}, sent = {}, heartbeat = {}, server_handlers = {} }

local function vec3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
_G.Vector3 = { New = vec3 }
_G.Vector2 = { New = function(x, y) return { X = x, Y = y, x = x, y = y } end }
_G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
_G.Enums = {
  BodyType = { Static = "Static", Kinematic = "Kinematic" },
  UserInputType = { MouseButton2 = "MB2", Keyboard = "KB" },
  KeyCode = { Escape = "Esc" },
  CameraMode = { NONE = "NONE" },
}

local Unit = {}
Unit.__index = Unit
function Unit:Destroy() self._destroyed = true; stub.units[self] = nil end
function Unit:StartposAttach() end
function Unit:EndposAttach() end

local World = {}
function World:CreateUnit(kind, props)
  local u = setmetatable({ _kind = kind }, Unit)
  for k, v in pairs(props or {}) do u[k] = v end
  stub.units[u] = true
  return u
end
function World:FindFirstChild(name)
  for u in pairs(stub.units) do if u.Name == name then return u end end
  return nil
end

local signal = function(list)
  return { Connect = function(_, fn) list[#list + 1] = fn; return { Disconnect = function() end } end }
end
local RunService = { Heartbeat = signal(stub.heartbeat) }

_G.game = { GetService = function(_, name)
  if name == "World" then return World end
  if name == "RunService" then return RunService end
  return {}
end }

_G.RemoteEvent = { New = function(name)
  return {
    FireAllClients = function(_, msg) stub.sent[#stub.sent + 1] = msg end,
    OnServerEvent = signal(stub.server_handlers),
  }
end }

-- 驱动：推进一帧 Heartbeat
function stub.step(dt)
  for _, fn in ipairs(stub.heartbeat) do fn(dt or 1 / 30) end
end
function stub.steps(n, dt) for _ = 1, n do stub.step(dt) end end
-- 客户端上行
function stub.client_send(args)
  for _, fn in ipairs(stub.server_handlers) do fn({ name = "p1" }, args) end
end
function stub.units_of(kind_pred)
  local out = {}
  for u in pairs(stub.units) do if kind_pred(u) then out[#out + 1] = u end end
  return out
end

return stub
