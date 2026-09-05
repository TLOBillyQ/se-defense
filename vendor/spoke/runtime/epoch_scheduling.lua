-- Tick requests: deciding whether an epoch may ask to be ticked, and routing
-- that request to whoever schedules it (its ticker, the runtime, or its tree).
--
-- Split out of epoch.lua so the scheduling decision reads in one place.
local SpokeRuntime = require("vendor.spoke.runtime.spoke_runtime")

local EpochScheduling = {}

local function is_inert(epoch)
  return epoch.is_detached or epoch._detaching or epoch.fault
end

local function can_request_tick(epoch)
  return not is_inert(epoch)
    and not epoch._detach_requested
    and not epoch._is_pending
end

local function is_scheduler(target)
  return target ~= nil and type(target._schedule) == "function"
end

-- A root tree must be routed to the runtime scheduler (like
-- Ticker:_request_upstream); inserting the tree into its own pending heap would
-- tick it as if it were a plain epoch (compare_to/_tick on itself). Manual trees
-- are driven explicitly, so a self-tick request has nothing to do.
local function route(epoch)
  if is_scheduler(epoch._ticker) then
    epoch._ticker:_schedule(epoch)
  elseif epoch._is_tree then
    if not epoch._is_manual then
      SpokeRuntime.schedule(epoch)
    end
  elseif is_scheduler(epoch._tree) then
    epoch._tree:_schedule(epoch)
  end
end

--- Builds the epoch's `_request_tick` closure, bound to that epoch for life.
function EpochScheduling.make_request_tick(epoch)
  return function()
    if not can_request_tick(epoch) then
      return
    end
    epoch._is_pending = true
    route(epoch)
  end
end

return EpochScheduling
