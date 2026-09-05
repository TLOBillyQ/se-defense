-- Cursor comparison: the ordering fallback used when either epoch's packed
-- tree coordinate has overflowed (see packed_tree_coords.lua). Walks both
-- epochs up to their common ancestor and compares the branch they diverge on,
-- mirroring upstream Epoch.CompareTo's uncoordinated path.
--
-- Also owns deriving an epoch's coordinate and tick cursor from its position.
local PackedTreeCoords = require("vendor.spoke.runtime.packed_tree_coords")

-- SE server Lua sandbox may not expose the standard `rawequal` function.
-- Epoch identity is what matters here; epochs never overload __eq, so `==`
-- behaves as raw equality in practice.
local rawequal = rawequal or function(a, b) return a == b end

local EpochCursor = {}

-- The component an epoch contributes at its own depth: its tick index while it
-- has one, otherwise the sentinel that sorts before any real index.
local function leaf_component(epoch)
  return epoch._tick_index or -1
end

-- Climbs `epoch` until it sits at `target_depth`, reporting the branch index it
-- last stepped through.
local function climb_to_depth(epoch, depth, target_depth, component)
  for _ = depth, target_depth + 1, -1 do
    component = epoch._coord_index
    epoch = epoch._parent
  end
  return epoch, component
end

-- Climbs both epochs in lockstep until they meet, reporting the branch indices
-- they diverged on.
local function climb_to_common_ancestor(a, b, component_a, component_b)
  while not rawequal(a, b) do
    component_a = a._coord_index
    component_b = b._coord_index
    a = a._parent
    b = b._parent
  end
  return component_a, component_b
end

-- Two epochs are never equal here (the identity case returns earlier), so a
-- strict comparison is enough.
local function order_by(is_less)
  if is_less then
    return -1
  end
  return 1
end

--- Three-way compare of two epochs by tree position. Equal branch indices mean
--- one epoch is an ancestor of the other, which the shallower one wins.
function EpochCursor.compare(a, b)
  if rawequal(a, b) then
    return 0
  end
  local depth_a = a._depth
  local depth_b = b._depth
  local component_a = leaf_component(a)
  local component_b = leaf_component(b)

  a, component_a = climb_to_depth(a, depth_a, depth_b, component_a)
  b, component_b = climb_to_depth(b, depth_b, depth_a, component_b)
  component_a, component_b = climb_to_common_ancestor(a, b, component_a, component_b)

  if component_a ~= component_b then
    return order_by(component_a < component_b)
  end
  return order_by(depth_a < depth_b)
end

--- The epoch's own coordinate, derived from its parent and branch index.
function EpochCursor.resolve_coords(epoch)
  if epoch._parent then
    return epoch._parent._coords:extend(epoch._coord_index)
  end
  return PackedTreeCoords.ROOT
end

--- The coordinate an epoch sorts by once its tick window is open.
function EpochCursor.resolve_cursor(epoch)
  if epoch._tick_index >= 0 then
    return epoch._coords:extend(epoch._tick_index)
  end
  return epoch._coords
end

return EpochCursor
