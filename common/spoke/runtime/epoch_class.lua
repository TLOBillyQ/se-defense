-- Epoch class construction: how an epoch instance is initialized and how a
-- subclass table is defined. Shared by Epoch.extend and Ticker.extend so both
-- inherit exactly the same instance rules.
local EpochClass = {}

--- Builds an instance of `class`. A leading string argument names the epoch;
--- the rest are forwarded to the class constructor.
function EpochClass.new_instance(class, ...)
  local self = setmetatable({
    name = class._default_name or "Epoch",
    is_detached = false,
    fault = nil,
    _attachments = {},
    _attached = false,
    _tick_index = -1,
    _frame_depth = 0,
    _detach_requested = false,
    _is_ticker = class.is_ticker == true,
    _auto_arm_tick_after_init = class.auto_arm_tick_after_init ~= false,
  }, class)
  local args = { ... }
  if type(args[1]) == "string" then
    self.name = table.remove(args, 1)
  end
  if type(class.constructor) == "function" then
    class.constructor(self, table.unpack(args))
  end
  return self
end

--- Defines a subclass of `parent` carrying `definition`'s members.
function EpochClass.define(parent, name, definition, tostring_fn)
  local class = {
    _default_name = name,
    __tostring = tostring_fn,
  }
  class.__index = class
  setmetatable(class, { __index = parent })
  for key, value in pairs(definition or {}) do
    class[key] = value
  end
  function class.new(...)
    return EpochClass.new_instance(class, ...)
  end
  return class
end

return EpochClass
