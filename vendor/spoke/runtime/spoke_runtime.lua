local Heap = require("vendor.spoke.runtime.heap")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local Ordering = require("vendor.spoke.runtime.ordering")
local RuntimeFrames = require("vendor.spoke.runtime.runtime_frames")
local TreeQueue = require("vendor.spoke.runtime.tree_queue")

-- Oscillation guards: how many times a flush may go backwards in queue order
-- before the runtime decides it is looping and clears what is pending.
local MAX_FLUSH_PASSES = 100

local SpokeRuntime = {
  frames = {},
  _frame_aux = {},
  _clock = 0,
  _scheduled_trees = nil,
  _boosted_trees = {},
  _hold_count = 0,
  _flush_layer = math.huge,
  _flush_depth = 0,
}
SpokeRuntime.FrameKind = {
  None = "None",
  Init = "Init",
  Tick = "Tick",
  Dock = "Dock",
  Bootstrap = "Bootstrap",
}

local function identity(value)
  return value
end

local tree_compare = TreeQueue.make_comparator(SpokeRuntime)

SpokeRuntime._scheduled_trees = Heap.new(tree_compare)

function SpokeRuntime.next_timestamp()
  local timestamp = SpokeRuntime._clock
  SpokeRuntime._clock = timestamp + 1
  return timestamp
end

-- Frame stack ----------------------------------------------------------------

function SpokeRuntime.push(frame)
  return RuntimeFrames.push(SpokeRuntime, frame)
end

function SpokeRuntime.pop()
  return RuntimeFrames.pop(SpokeRuntime)
end

function SpokeRuntime.snapshot_frames()
  return RuntimeFrames.snapshot(SpokeRuntime)
end

function SpokeRuntime.current_handle()
  return RuntimeFrames.current_handle(SpokeRuntime)
end

-- Scheduling -----------------------------------------------------------------

function SpokeRuntime.batch(fn)
  if type(fn) ~= "function" then
    error("SpokeRuntime.batch expects a function", 2)
  end
  SpokeRuntime._hold_count = SpokeRuntime._hold_count + 1
  local ok, error_value = xpcall(fn, identity)
  SpokeRuntime._hold_count = SpokeRuntime._hold_count - 1
  if SpokeRuntime._hold_count == 0 then
    SpokeRuntime.try_flush()
  end
  if not ok then
    error(error_value, 0)
  end
end

function SpokeRuntime._log(message, cause)
  SpokeError.log(message, cause)
end

function SpokeRuntime._has_pending()
  return TreeQueue.has_live_head(SpokeRuntime._scheduled_trees)
end

-- A tree may only flush inside a strictly higher layer than the one currently
-- flushing; a boosted tree is allowed to flush at its own layer.
local function may_flush_tree(tree)
  if tree._bootstrapping then
    return false
  end
  local current_layer = SpokeRuntime._flush_layer
  if SpokeRuntime._boosted_trees[tree] then
    return tree._flush_layer <= current_layer
  end
  return tree._flush_layer < current_layer
end

function SpokeRuntime.schedule(tree)
  if not tree or tree.is_detached or tree.fault then
    return
  end
  if not tree._runtime_pending then
    tree._runtime_pending = true
    SpokeRuntime._scheduled_trees:insert(tree)
  end
  SpokeRuntime.try_flush()
end

function SpokeRuntime.try_scoped_layer_boost(tree)
  local handle = SpokeRuntime.current_handle()
  if not handle or tree._flush_layer > SpokeRuntime._flush_layer then
    return
  end
  if SpokeRuntime._boosted_trees[tree] then
    return
  end
  SpokeRuntime._boosted_trees[tree] = true
  handle:on_pop_self(function()
    SpokeRuntime._boosted_trees[tree] = nil
    SpokeRuntime._scheduled_trees:rebuild()
  end)
end

function SpokeRuntime.tick_tree(tree)
  local previous_layer = SpokeRuntime._flush_layer
  SpokeRuntime._flush_layer = math.min(previous_layer, tree._flush_layer)
  local ok, error_value = xpcall(function()
    tree:_tick()
  end, identity)
  SpokeRuntime._flush_layer = previous_layer
  if not ok then
    SpokeRuntime._log("Uncaught Spoke error", error_value)
  end
  if #SpokeRuntime.frames == 0 and SpokeRuntime._flush_depth == 0 then
    SpokeRuntime.try_flush()
  end
end

-- Flushing -------------------------------------------------------------------

local function abandon_flush(tree)
  SpokeRuntime._log(
    "SpokeRuntime exceeded oscillation limit; pending trees were cleared",
    tree)
  TreeQueue.drain(SpokeRuntime._scheduled_trees)
end

local function take_next_tree()
  local tree = SpokeRuntime._scheduled_trees:remove_min()
  tree._runtime_pending = false
  return tree
end

function SpokeRuntime.try_flush()
  if SpokeRuntime._hold_count > 0 then
    return
  end

  SpokeRuntime._flush_depth = SpokeRuntime._flush_depth + 1
  local previous = nil
  local pass_count = 0
  while SpokeRuntime._has_pending() do
    local tree = SpokeRuntime._scheduled_trees:peek_min()
    if not may_flush_tree(tree) then
      break
    end
    pass_count = Ordering.count_regression(pass_count, previous, tree, tree_compare)
    if pass_count >= MAX_FLUSH_PASSES then
      abandon_flush(tree)
      break
    end
    previous = tree
    SpokeRuntime.tick_tree(take_next_tree())
  end
  SpokeRuntime._flush_depth = SpokeRuntime._flush_depth - 1
end

-- Tests and host adapters may need to discard stale global scheduler state after
-- tearing down a whole embedding. Normal callers should not need this.
function SpokeRuntime._reset_for_tests()
  SpokeRuntime.frames = {}
  SpokeRuntime._frame_aux = {}
  SpokeRuntime._clock = 0
  TreeQueue.drain(SpokeRuntime._scheduled_trees)
  SpokeRuntime._boosted_trees = {}
  SpokeRuntime._hold_count = 0
  SpokeRuntime._flush_layer = math.huge
  SpokeRuntime._flush_depth = 0
end

return SpokeRuntime
