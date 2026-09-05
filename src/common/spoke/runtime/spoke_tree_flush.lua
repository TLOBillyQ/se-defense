-- Driving a tree's pending epochs: the flush loop and the oscillation guard
-- that stops a tree looping forever.
--
-- Split out of spoke_tree.lua, which owns the tree state this operates on.
local SpokeException = require("src.common.spoke.runtime.spoke_exception")
local SpokeRuntime = require("src.common.spoke.runtime.spoke_runtime")
local Ordering = require("src.common.spoke.runtime.ordering")

local TreeFlush = {}

-- How many times the flush order may go backwards before the tree is judged to
-- be oscillating.
local MAX_PASSES = 1000

local function identity(value)
  return value
end

local function halt(tree, fault, message)
  tree.fault = fault
  tree:_clear_pending()
  tree:_log_error(message, fault)
end

local function oscillation_fault(tree)
  return SpokeException.new(
    "Exceed oscillation limit - possible infinite loop",
    "tree flush guard",
    tree,
    "Tick",
    SpokeRuntime.snapshot_frames())
end

--- Ticks one pending epoch. Returns false once the tree has faulted and the
--- caller should stop; rethrows anything that is not a Spoke exception.
local function tick_once(tree, context)
  local ok, error_value = xpcall(function()
    context:tick_next()
  end, identity)
  if ok then
    return true
  end
  if SpokeException.is(error_value) then
    halt(tree, error_value, "[SpokeTree] flush error")
    return false
  end
  error(error_value, 0)
end

local function compare_epochs(a, b)
  return a:compare_to(b)
end

--- Drives pending epochs until the tree is drained, the command is satisfied,
--- or the tree faults.
function TreeFlush.drive(tree, context)
  if not tree._command then
    return
  end
  local previous = nil
  local pass_count = 0
  while tree:has_pending() do
    if pass_count >= MAX_PASSES then
      halt(tree, oscillation_fault(tree), "[SpokeTree] flush stopped")
      return
    end
    local next_epoch = tree:peek_next()
    pass_count = Ordering.count_regression(pass_count, previous, next_epoch, compare_epochs)
    previous = next_epoch
    if not tick_once(tree, context) then
      return
    end
    if tree._command == "tick" then
      return
    end
  end
end

return TreeFlush
