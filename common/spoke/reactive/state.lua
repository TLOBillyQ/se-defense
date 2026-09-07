local Trigger = require("common.spoke.reactive.trigger")

local State = {}
State.__index = State

local function default_equals(a, b)
  return a == b
end

function State.new(...)
  local arg_count = select("#", ...)
  local args = { ... }
  local name = nil
  local initial = nil
  local equals = nil

  if arg_count == 0 then
    -- State.new()
    initial = nil
  elseif arg_count == 1 then
    -- State.new(initial) where a single string is the initial value, not a name
    initial = args[1]
  elseif arg_count >= 2 then
    if type(args[1]) == "string" then
      -- State.new(name, initial [, equals])
      name = args[1]
      initial = args[2]
      equals = args[3]
    else
      -- State.new(initial, equals)
      initial = args[1]
      equals = args[2]
    end
  end

  local self = setmetatable({
    name = name,
    _value = initial,
    _trigger = Trigger.new(),
    _equals = equals or default_equals,
  }, State)
  return self
end

function State:now()
  return self._value
end

function State:set(value)
  if self._equals(self._value, value) then
    return
  end
  self._value = value
  self._trigger:invoke(value)
end

function State:update(fn)
  if fn == nil then
    return
  end
  self:set(fn(self._value))
end

function State:subscribe(fn)
  return self._trigger:subscribe(fn)
end

function State:unsubscribe(fn)
  self._trigger:unsubscribe(fn)
end

return State
