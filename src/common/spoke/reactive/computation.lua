local Epoch = require("common.spoke.runtime.epoch")

-- DependencyTracker manages a Computation's dynamic signal dependencies.
-- Dependencies are matched to slots by read position, so a run that reads the
-- same signals in the same order rebinds nothing. Reading one signal twice
-- simply takes two slots.
local DependencyTracker = {}
DependencyTracker.__index = DependencyTracker

function DependencyTracker.new(schedule)
  return setmetatable({
    _schedule = schedule,
    _static_handles = {},
    _dynamic = {},
    _slot_callbacks = {},
    _dep_index = 0,
  }, DependencyTracker)
end

function DependencyTracker:add_static(trigger)
  self._static_handles[#self._static_handles + 1] = trigger:subscribe(self._schedule)
end

function DependencyTracker:begin_dynamic()
  self._dep_index = 0
end

function DependencyTracker:add_dynamic(trigger)
  local slot = self._dynamic[self._dep_index + 1]
  if slot == nil then
    self._dynamic[self._dep_index + 1] = {
      trigger = trigger,
      handle = trigger:subscribe(self:_schedule_from_index(self._dep_index)),
    }
  elseif slot.trigger ~= trigger then
    slot.handle:dispose()
    slot.trigger = trigger
    slot.handle = trigger:subscribe(self:_schedule_from_index(self._dep_index))
  end
  self._dep_index = self._dep_index + 1
end

function DependencyTracker:end_dynamic()
  while #self._dynamic > self._dep_index do
    table.remove(self._dynamic).handle:dispose()
  end
end

function DependencyTracker:dispose()
  for _, handle in ipairs(self._static_handles) do
    handle:dispose()
  end
  for _, slot in ipairs(self._dynamic) do
    slot.handle:dispose()
  end
  self._static_handles = {}
  self._dynamic = {}
end

-- Dependencies may fire while we're in the middle of refreshing them. The
-- callback captures the slot index at the time of subscription; the index
-- tells whether the dependency is valid or stale when it fires. Callbacks are
-- cached per slot, so rebinding a slot does not allocate.
function DependencyTracker:_schedule_from_index(index)
  while #self._slot_callbacks <= index do
    local captured = #self._slot_callbacks
    local tracker = self
    self._slot_callbacks[#self._slot_callbacks + 1] = function()
      if captured < tracker._dep_index then
        tracker._schedule()
      end
    end
  end
  return self._slot_callbacks[index + 1]
end

-- Accepts varargs of triggers, a single trigger, or a single array of
-- triggers; returns the normalized array, or nil when absent. Shared by the
-- reactive subclasses (Effect/Reaction/Memo/Phase) so trigger-shape handling
-- cannot drift between them.
local function collect_triggers(...)
  local count = select("#", ...)
  if count == 0 then
    return nil
  end
  if count == 1 then
    local only = ...
    if type(only) == "table" and type(only.subscribe) ~= "function" then
      return only
    end
  end
  return { ... }
end

-- Parses the two Effect-style argument shapes shared by EffectBuilder:effect
-- and Dock:effect:
--   (name, block [, triggers]) when the first arg is a string
--   (block [, triggers])      otherwise
-- Triggers are normalized by collect_triggers (varargs or one array). The
-- parsed name is returned first so nil can be distinguished from an absent
-- name; callers must branch on `name ~= nil` before constructing the epoch.
local function parse_effect_args(a, b, ...)
  if type(a) == "string" then
    return a, b, collect_triggers(...)
  end
  return nil, a, collect_triggers(b, ...)
end

-- Accepts nil, a single trigger, or an array of triggers.
local function normalize_triggers(triggers)
  if triggers == nil then
    return {}
  end
  if type(triggers) == "table" then
    if type(triggers.subscribe) == "function" then
      return { triggers }
    end
    return triggers
  end
  error("Computation triggers must be a trigger or an array of triggers", 3)
end

-- Abstract Epoch base for all reactive objects (Effect, Reaction, Memo,
-- Phase). A Computation runs when any of its triggers fire and supports both
-- static and dynamic trigger subscriptions:
-- - static triggers are subscribed once, during Init, for its lifetime;
-- - dynamic triggers are declared per run through builder:d(signal).
local Computation = Epoch.extend("Computation", {
  constructor = function(self, triggers)
    self._triggers = normalize_triggers(triggers)
  end,

  init = function(self, s)
    local ports = s:ports()
    local tracker = DependencyTracker.new(function()
      ports:request_tick()
    end)
    s:use(tracker)
    self._tracker = tracker
    for _, trigger in ipairs(self._triggers) do
      tracker:add_static(trigger)
    end
    return function(tick_s)
      tracker:begin_dynamic()
      -- finally-equivalent: dynamic tracking ends even when on_run raises.
      local ok, err = pcall(function()
        self:on_run(tick_s)
      end)
      tracker:end_dynamic()
      if not ok then
        error(err, 0)
      end
    end
  end,

  on_run = function(self)
    error("Computation.on_run is abstract", 2)
  end,

  _add_static_trigger = function(self, trigger)
    self._tracker:add_static(trigger)
  end,

  _add_dynamic_trigger = function(self, trigger)
    self._tracker:add_dynamic(trigger)
  end,
})

-- Subclass seam for the reactive variants: identical to Epoch.extend, but the
-- new class inherits from Computation instead of directly from Epoch.
function Computation.extend(name, definition)
  local class = Epoch.extend(name, definition)
  getmetatable(class).__index = Computation
  return class
end

-- Deep-require surface for tests and advanced integrations.
Computation.DependencyTracker = DependencyTracker
-- Internal seam for subclasses sharing the varargs-normalization helper.
Computation._collect_triggers = collect_triggers
-- Internal seam for EffectBuilder/Dock sharing Effect-style arg parsing.
Computation._parse_effect_args = parse_effect_args

return Computation
