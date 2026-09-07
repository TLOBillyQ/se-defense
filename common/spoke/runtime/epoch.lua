local SpokeError = require("common.spoke.runtime.spoke_error")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local EpochAttach = require("common.spoke.runtime.epoch_attach")
local EpochBuilder = require("common.spoke.runtime.epoch_builder")
local EpochClass = require("common.spoke.runtime.epoch_class")
local EpochCursor = require("common.spoke.runtime.epoch_cursor")
local EpochFrame = require("common.spoke.runtime.epoch_frame")
local EpochScheduling = require("common.spoke.runtime.epoch_scheduling")
local EpochTeardown = require("common.spoke.runtime.epoch_teardown")

local Epoch = {}
Epoch.__index = Epoch
Epoch._log_error = function(message, error_value)
  SpokeError.log(message, error_value)
end
Epoch._log = function(message, error_value)
  SpokeError.log(message, error_value)
end

-- Resolved at call time so a host (or a test) can replace Epoch._log_error.
local function fallback_log(message, error_value)
  Epoch._log_error(message, error_value)
end

-- The builder emits structural logs through Epoch's own hook.
EpochBuilder.set_log_sink(function(message)
  Epoch._log(message)
end)

function Epoch.new(name)
  return EpochClass.new_instance(Epoch, name)
end

function Epoch.extend(name, definition)
  return EpochClass.define(Epoch, name, definition, Epoch.__tostring)
end

-- Internal class-construction seam used by Ticker and SpokeTree. Keeping it on
-- Epoch lets those modules inherit the exact instance initialization rules.
Epoch._new_instance = EpochClass.new_instance

function Epoch:init()
  return nil
end

-- Ordering -------------------------------------------------------------------

local function compare_across_trees(epoch, other)
  if epoch._tree and type(epoch._tree.compare_to) == "function" then
    return epoch._tree:compare_to(other._tree)
  end
  return 0
end

local function both_cursors_valid(epoch, other)
  return epoch._tick_cursor:is_valid() and other._tick_cursor:is_valid()
end

-- Base comparison implementation, kept as a separate method so callers can
-- reach epoch ordering through a colon call even when a subclass (SpokeTree)
-- overrides compare_to with a scheduler-specific contract. Upstream tests
-- express the same dispatch with `(epoch as Epoch).CompareTo(other)`.
function Epoch:_compare_to(other)
  if self._tree ~= other._tree then
    return compare_across_trees(self, other)
  end
  if both_cursors_valid(self, other) then
    return self._tick_cursor:compare_to(other._tick_cursor)
  end
  return EpochCursor.compare(self, other)
end

function Epoch:compare_to(other)
  return self:_compare_to(other)
end

function Epoch:__tostring()
  return self.name or "Epoch"
end

-- Attach ---------------------------------------------------------------------

function Epoch:_attach(parent, index, ticker, services, tree)
  if self._attached then
    error("Tried to attach an epoch which was already attached", 2)
  end
  EpochAttach.link_into_tree(self, parent, index, ticker, tree)
  self._request_tick = EpochScheduling.make_request_tick(self)

  local ok, result, frame = EpochFrame.run(self, "Init", function(builder)
    EpochAttach.export_services(self, services)
    return EpochAttach.invoke_init(self, builder)
  end)
  if not ok then
    EpochFrame.fail(self, "Init", frame, result)
  end

  self._tick_block = result
  EpochAttach.open_tick_window(self)
  if not EpochFrame.settle_detach_request(self, frame)
    and self._auto_arm_tick_after_init then
    frame:on_pop_self(function()
      self:_request_tick()
    end)
  end
  SpokeRuntime.pop()
end

-- Teardown -------------------------------------------------------------------

function Epoch:_detach_from(index)
  EpochTeardown.release_from(self, index, fallback_log)
end

function Epoch:_perform_detach()
  if self.is_detached or not self._attached or self._detaching then
    return
  end
  self._detaching = true
  self:_detach_from(0)
  if type(self._discard_pending) == "function" then
    self:_discard_pending()
  end
  self.is_detached = true
  self._is_pending = false
  self._detaching = false
end

function Epoch:detach()
  if self.is_detached or not self._attached then
    return
  end
  if self._frame_depth > 0 then
    self._detach_requested = true
    return
  end
  self:_perform_detach()
end

-- Tick -----------------------------------------------------------------------

function Epoch:_tick()
  if self.is_detached or self.fault then
    return
  end
  self._is_pending = false
  if self._is_ticker then
    -- Upstream isTicking spans the whole Tick frame, including the rollback
    -- cleanup at the top; schedules made there must not re-request upstream
    -- (the current pass absorbs them).
    self._is_ticking = true
  end

  local ok, result, frame = EpochFrame.run(self, "Tick", function(builder)
    self:_detach_from(self._tick_index)
    if self._tick_block then
      return self._tick_block(builder)
    end
  end)
  if not ok then
    EpochFrame.fail(self, "Tick", frame, result)
  end

  EpochFrame.settle_detach_request(self, frame)
  SpokeRuntime.pop()
end

-- Coordinates ----------------------------------------------------------------

function Epoch:_refresh_coords()
  self._coords = EpochCursor.resolve_coords(self)
  self._tick_cursor = EpochCursor.resolve_cursor(self)
  for _, record in ipairs(self._attachments) do
    if record.kind == "call" then
      record.value:_refresh_coords()
    end
  end
end

function Epoch:_reindex(index)
  self._coord_index = index
  self:_refresh_coords()
end

-- Accessors ------------------------------------------------------------------

function Epoch:_get_parent()
  return self._parent
end

function Epoch:_get_ticker()
  return self._ticker
end

function Epoch:_set_fault(fault)
  self.fault = fault
end

function Epoch:_get_children(store)
  store = store or {}
  for _, record in ipairs(self._attachments) do
    if record.kind == "call" then
      store[#store + 1] = record.value
    end
  end
  return store
end

return Epoch
