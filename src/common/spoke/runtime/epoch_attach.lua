-- The steps of attaching an epoch: linking it into its tree, publishing the
-- services it was spawned with, running its Init block, and opening the tick
-- window that later ticks roll back to.
--
-- Split out of epoch.lua; Epoch:_attach orchestrates these in order.
local PackedTreeCoords = require("src.common.spoke.runtime.packed_tree_coords")
local EpochBuilder = require("src.common.spoke.runtime.epoch_builder")

local EpochAttach = {}

-- An epoch attached to a parent inherits its position from it; a root epoch
-- starts a tree of its own.
local function import_index_of(parent)
  if parent then
    return #parent._attachments - 1
  end
  return -1
end

local function depth_of(parent)
  if parent then
    return parent._depth + 1
  end
  return 0
end

local function coords_of(parent, index)
  if parent then
    return parent._coords:extend(index)
  end
  return PackedTreeCoords.ROOT
end

local function tree_of(epoch, parent, tree)
  if tree then
    return tree
  end
  if parent then
    return parent._tree
  end
  return epoch
end

--- Fixes the epoch's position: parent, branch index, depth, coordinate, the
--- ticker that schedules it and the tree that owns it.
function EpochAttach.link_into_tree(epoch, parent, index, ticker, tree)
  epoch._parent = parent
  epoch._coord_index = index
  epoch._import_index = import_index_of(parent)
  epoch._depth = depth_of(parent)
  epoch._coords = coords_of(parent, index)
  epoch._tick_cursor = epoch._coords
  epoch._ticker = ticker
  epoch._tree = tree_of(epoch, parent, tree)
  epoch._attached = true
  epoch.is_detached = false
  epoch._is_pending = false
end

--- Services arrive as a keyed table; they are exported in a stable order so an
--- epoch's attachment indices do not depend on table iteration order.
function EpochAttach.export_services(epoch, services)
  if not services then
    return
  end
  local keys = {}
  for key in pairs(services) do
    EpochBuilder.assert_export_key(key)
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    epoch._attachments[#epoch._attachments + 1] = {
      kind = "export",
      key = key,
      value = services[key],
    }
  end
end

--- Runs the epoch's Init block and validates what it returned.
function EpochAttach.invoke_init(epoch, builder)
  local init_result = epoch:init(builder)
  if init_result ~= nil and type(init_result) ~= "function" then
    -- Fail fast at attach time instead of surfacing as an obscure
    -- "attempt to call" error on the first tick.
    error("Epoch init must return a tick function or nil, got " .. type(init_result), 0)
  end
  return init_result
end

--- Marks where Init ended, so each tick rolls back exactly the tick-scoped
--- attachments and the epoch sorts by its tick cursor from now on.
function EpochAttach.open_tick_window(epoch)
  epoch._tick_index = #epoch._attachments
  epoch._tick_cursor = epoch._coords:extend(epoch._tick_index)
end

return EpochAttach
