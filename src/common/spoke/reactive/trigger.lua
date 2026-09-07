local SpokeHandle = require("common.spoke.runtime.spoke_handle")
local SpokeError = require("common.spoke.runtime.spoke_error")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")

local Trigger = {}
Trigger.__index = Trigger

function Trigger.new(name)
  local self = setmetatable({
    name = name,
    _subs = {},
    _dead_count = 0,
    _id_count = 0,
    _events = {},
    _event_head = 1,
    _event_tail = 0,
    _is_flushing = false,
    _dispatch_list = nil,
  }, Trigger)
  return self
end

local function compact(subs, dead_count)
  if dead_count * 2 <= #subs then
    return subs, dead_count
  end
  local write = 0
  for read = 1, #subs do
    if subs[read].fn ~= nil then
      write = write + 1
      subs[write] = subs[read]
    end
  end
  for index = write + 1, #subs do
    subs[index] = nil
  end
  return subs, 0
end

function Trigger:_subscribe(fn)
  if type(fn) ~= "function" then
    error("Trigger.subscribe expects a function", 2)
  end
  self._subs, self._dead_count = compact(self._subs, self._dead_count)
  local id = self._id_count
  self._id_count = id + 1
  local sub = { id = id, fn = fn }
  local subs = self._subs
  subs[#subs + 1] = sub
  local trigger = self
  return SpokeHandle.of(id, function()
    trigger:_unsub_by_id(id)
  end)
end

function Trigger:subscribe(fn)
  return self:_subscribe(fn)
end

function Trigger:_unsub_by_id(id)
  local subs = self._subs
  local lo, hi = 1, #subs
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local sub = subs[mid]
    if sub.id < id then
      lo = mid + 1
    elseif sub.id > id then
      hi = mid - 1
    else
      if sub.fn == nil then
        return
      end
      sub.fn = nil
      self._dead_count = self._dead_count + 1
      return
    end
  end
end

function Trigger:_unsub_by_fn(fn)
  local ids = {}
  for _, sub in ipairs(self._subs) do
    if sub.fn == fn then
      ids[#ids + 1] = sub.id
    end
  end
  for _, id in ipairs(ids) do
    self:_unsub_by_id(id)
  end
end

function Trigger:unsubscribe(fn)
  if type(fn) ~= "function" then
    error("Trigger.unsubscribe expects a function", 2)
  end
  self:_unsub_by_fn(fn)
end

-- The dispatch list is reused between events to avoid allocating per invoke.
local function reset_dispatch_list(trigger)
  local list = trigger._dispatch_list
  if list == nil then
    list = {}
    trigger._dispatch_list = list
    return list
  end
  for index = 1, #list do
    list[index] = nil
  end
  return list
end

-- A throwing subscriber is reported and never stops the remaining subscribers.
local function invoke_subscriber(fn, payload)
  local ok, err = pcall(function()
    fn(payload)
  end)
  if not ok then
    SpokeError.log("Trigger subscriber error", err)
  end
end

function Trigger:_dispatch(payload)
  local dispatch_list = reset_dispatch_list(self)
  -- Snapshot the callable at dispatch start so tombstoning a slot mid-dispatch
  -- does not suppress its call for this event (upstream copies structs by value).
  for _, sub in ipairs(self._subs) do
    dispatch_list[#dispatch_list + 1] = sub.fn
  end
  for _, fn in ipairs(dispatch_list) do
    if fn ~= nil then
      invoke_subscriber(fn, payload)
    end
  end
end

function Trigger:_flush()
  if self._is_flushing then
    return
  end
  self._is_flushing = true
  local ok, err = pcall(function()
    while self._event_head <= self._event_tail do
      local payload = self._events[self._event_head]
      self._events[self._event_head] = nil
      self._event_head = self._event_head + 1
      self:_dispatch(payload)
    end
  end)
  self._is_flushing = false
  self._subs, self._dead_count = compact(self._subs, self._dead_count)
  if not ok then
    error(err, 0)
  end
end

function Trigger:invoke(payload)
  local events = self._events
  self._event_tail = self._event_tail + 1
  events[self._event_tail] = payload
  SpokeRuntime.batch(function()
    self:_flush()
  end)
end

return Trigger
