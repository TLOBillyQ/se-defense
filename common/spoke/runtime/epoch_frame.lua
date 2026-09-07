-- Frame scaffolding shared by an epoch's Init and Tick windows: push a runtime
-- frame, run the body with a fresh builder, and turn a thrown value into the
-- epoch's fault.
--
-- Split out of epoch.lua so the lifecycle bookkeeping reads separately from the
-- epoch's own state transitions.
local SpokeException = require("common.spoke.runtime.spoke_exception")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local EpochBuilder = require("common.spoke.runtime.epoch_builder")

local EpochFrame = {}

local function identity_error(value)
  return value
end

function EpochFrame.wrap_fault(epoch, phase, error_value)
  if SpokeException.is(error_value) then
    return error_value
  end
  return SpokeException.new(
    "Uncaught Exception in " .. phase,
    error_value,
    epoch,
    phase,
    SpokeRuntime.snapshot_frames())
end

--- Runs `body(builder)` inside a pushed runtime frame. The caller owns the
--- matching SpokeRuntime.pop() so it can act on the result first.
function EpochFrame.run(epoch, phase, body)
  epoch._frame_depth = epoch._frame_depth + 1
  local frame = SpokeRuntime.push({
    type = phase,
    epoch = epoch,
    phase = phase,
  })
  epoch._frame_handle = frame
  local builder = EpochBuilder.new(epoch, frame)
  local ok, result = xpcall(function()
    return body(builder)
  end, identity_error)
  builder._active = false
  if epoch._is_ticker and phase == "Tick" then
    epoch._is_ticking = false
  end
  epoch._frame_depth = epoch._frame_depth - 1
  return ok, result, frame
end

--- A detach asked for while the frame was open runs once the frame pops.
--- Reports whether such a request was pending.
function EpochFrame.settle_detach_request(epoch, frame)
  if not epoch._detach_requested then
    return false
  end
  epoch._detach_requested = false
  frame:on_pop_self(function()
    epoch:_perform_detach()
  end)
  return true
end

--- Records the fault, releases the frame, and rethrows it to the caller.
function EpochFrame.fail(epoch, phase, frame, error_value)
  epoch.fault = EpochFrame.wrap_fault(epoch, phase, error_value)
  EpochFrame.settle_detach_request(epoch, frame)
  SpokeRuntime.pop()
  error(epoch.fault, 0)
end

return EpochFrame
