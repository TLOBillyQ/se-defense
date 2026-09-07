-- The runtime's queue of trees awaiting a flush: how two trees are ordered, and
-- how pending trees are dropped when they die or when the queue is cleared.
--
-- Split out of spoke_runtime.lua, which owns the queue itself and the boost set
-- the comparator reads.
local Ordering = require("common.spoke.runtime.ordering")

local TreeQueue = {}

-- A scoped boost lets a tree flush at the layer that boosted it, so a boosted
-- tree sorts ahead of an unboosted one on the same layer.
local function compare_boost(a, b, boosted)
  return Ordering.compare_flag(boosted[a] == true, boosted[b] == true)
end

--- Builds the queue comparator: flush layer, then scoped boost, then the
--- timestamp the tree was created with. The boost set is read from the runtime
--- on every comparison, since resetting the runtime replaces that table.
function TreeQueue.make_comparator(runtime)
  return function(a, b)
    local by_layer = Ordering.compare(a._flush_layer, b._flush_layer)
    if by_layer ~= 0 then
      return by_layer
    end
    local by_boost = compare_boost(a, b, runtime._boosted_trees)
    if by_boost ~= 0 then
      return by_boost
    end
    return Ordering.compare(a._timestamp, b._timestamp)
  end
end

--- Forgets a tree's pending state and lets it release whatever it had queued.
function TreeQueue.discard(tree)
  tree._runtime_pending = false
  if type(tree._discard_pending) == "function" then
    tree:_discard_pending()
  end
end

--- Whether the queue holds a tree still worth flushing. Dead and faulted trees
--- are dropped on the way.
function TreeQueue.has_live_head(queue)
  while queue:count() > 0 do
    local tree = queue:peek_min()
    if tree.is_detached or tree.fault then
      queue:remove_min()
      TreeQueue.discard(tree)
    else
      return true
    end
  end
  return false
end

--- Empties the queue, discarding every tree still in it.
function TreeQueue.drain(queue)
  while queue:count() > 0 do
    TreeQueue.discard(queue:remove_min())
  end
end

return TreeQueue
