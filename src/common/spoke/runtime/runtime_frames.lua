-- The runtime's virtual call stack: the frames pushed around every Init, Tick,
-- Dock and Bootstrap window, and the handles that let a caller act when its own
-- frame pops.
--
-- Split out of spoke_runtime.lua. The frame state stays on the runtime table so
-- `SpokeRuntime.frames` remains the single observable stack; these functions
-- take that runtime as their first argument.
local RuntimeFrames = {}

local Handle = {}
Handle.__index = Handle

--- Pushes a frame and returns a handle to it.
function RuntimeFrames.push(runtime, frame)
  frame = frame or {}
  frame.type = frame.type or frame.kind or "None"
  frame.kind = frame.kind or frame.type
  local index = #runtime.frames + 1
  local version = runtime._clock
  runtime._clock = version + 1
  runtime.frames[index] = frame
  runtime._frame_aux[index] = {
    version = version,
    on_pop = nil,
  }
  return setmetatable({
    _runtime = runtime,
    _index = index,
    _version = version,
  }, Handle)
end

--- Pops the top frame and runs whatever was registered for its pop.
function RuntimeFrames.pop(runtime)
  local frames = runtime.frames
  local index = #frames
  if index == 0 then
    error("SpokeRuntime frame stack is empty", 3)
  end
  local aux = runtime._frame_aux[index]
  frames[index] = nil
  runtime._frame_aux[index] = nil
  local actions = aux.on_pop
  if actions then
    for _, action in ipairs(actions) do
      action()
    end
  end
end

--- A copy of the current stack, safe to keep past the frames' lifetimes.
function RuntimeFrames.snapshot(runtime)
  local snapshot = {}
  for index, frame in ipairs(runtime.frames) do
    snapshot[index] = {
      epoch = frame.epoch,
      type = frame.type,
      kind = frame.kind,
      phase = frame.phase,
    }
  end
  return snapshot
end

--- A handle to the top frame, or nil when the stack is empty.
function RuntimeFrames.current_handle(runtime)
  local index = #runtime.frames
  if index == 0 then
    return nil
  end
  local aux = runtime._frame_aux[index]
  return setmetatable({
    _runtime = runtime,
    _index = index,
    _version = aux.version,
  }, Handle)
end

-- A handle is alive while its slot still holds the very frame it was made for;
-- the version guards against a later frame reusing the slot.
function Handle:is_alive()
  local runtime = self._runtime
  local aux = runtime._frame_aux[self._index]
  return aux ~= nil
    and aux.version == self._version
    and runtime.frames[self._index] ~= nil
end

function Handle:is_top()
  return self:is_alive() and self._index == #self._runtime.frames
end

function Handle:frame()
  if self:is_alive() then
    return self._runtime.frames[self._index]
  end
  return nil
end

--- Runs `fn` when this frame pops, or immediately if it already has.
function Handle:on_pop_self(fn)
  if type(fn) ~= "function" then
    error("SpokeRuntime frame action must be a function", 2)
  end
  if not self:is_alive() then
    fn()
    return
  end
  local aux = self._runtime._frame_aux[self._index]
  aux.on_pop = aux.on_pop or {}
  aux.on_pop[#aux.on_pop + 1] = fn
end

RuntimeFrames.Handle = Handle

return RuntimeFrames
