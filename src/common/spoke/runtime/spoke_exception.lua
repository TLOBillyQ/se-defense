local SpokeIntrospect = require("common.spoke.runtime.spoke_introspect")

local SpokeException = {}
SpokeException.__index = SpokeException

function SpokeException.new(message, cause, epoch, phase, stack_snapshot)
  stack_snapshot = stack_snapshot or {
    {
      epoch = epoch,
      type = phase,
      phase = phase,
    },
  }
  -- The eggy host sandbox does not guarantee the debug library; guard like
  -- spoke_error.lua does so fault wrapping never crashes on its own path.
  local traceback = type(debug) == "table" and debug.traceback("", 3) or nil
  return setmetatable({
    message = message,
    cause = cause,
    inner = cause,
    epoch = epoch,
    phase = phase,
    stack_snapshot = stack_snapshot,
    stack = stack_snapshot,
    traceback = traceback,
  }, SpokeException)
end

function SpokeException.is(value)
  return type(value) == "table" and getmetatable(value) == SpokeException
end

function SpokeException:__tostring()
  return SpokeIntrospect.tree_trace(self.stack_snapshot or {})
    .. "\n" .. tostring(self.cause)
end

return SpokeException
