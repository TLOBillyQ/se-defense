-- Dock slot bookkeeping: the keyed child table, its key index, and the
-- compaction that keeps coordinate indices packable.
--
-- Slots are stored 1-based in `_child_slots`; the index published to a child
-- epoch (and held in `_slot_by_key`) is the 0-based coordinate index.
-- Split out of dock.lua, which owns the epoch lifecycle around these slots.
local PackedTreeCoords = require("vendor.spoke.runtime.packed_tree_coords")

local DockSlots = {}

function DockSlots.reset(dock)
  dock._child_slots = {}
  dock._slot_by_key = {}
  dock._live_count = 0
end

--- Whether the slot table has grown past the coordinate range with enough
--- holes that compacting it is worthwhile.
function DockSlots.should_compact(dock)
  return #dock._child_slots > PackedTreeCoords.MAX_INDEX
    and dock._live_count * 2 <= #dock._child_slots
end

--- Appends a slot, returning the 0-based coordinate index it took.
function DockSlots.append(dock, key, epoch)
  local index = #dock._child_slots
  dock._slot_by_key[key] = index
  dock._child_slots[index + 1] = { key = key, epoch = epoch }
  dock._live_count = dock._live_count + 1
  return index
end

--- The epoch filed under `key`, or nil when the key holds no live slot.
function DockSlots.find(dock, key)
  local index = dock._slot_by_key[key]
  if index == nil then
    return nil
  end
  return dock._child_slots[index + 1].epoch
end

--- Tombstones the slot under `key`. An emptied table is reset outright so
--- indices restart from zero.
function DockSlots.release(dock, key)
  local index = dock._slot_by_key[key]
  dock._child_slots[index + 1] = { key = key, epoch = nil }
  dock._slot_by_key[key] = nil
  dock._live_count = dock._live_count - 1
  if dock._live_count == 0 then
    dock._child_slots = {}
    dock._slot_by_key = {}
  end
end

local function is_live_slot(slot)
  return slot ~= nil and slot.epoch ~= nil
end

local function move_slot(dock, slot, write_index)
  dock._child_slots[write_index + 1] = slot
  dock._slot_by_key[slot.key] = write_index
  slot.epoch:_reindex(write_index)
end

local function truncate(dock, size)
  for index = #dock._child_slots, size + 1, -1 do
    dock._child_slots[index] = nil
  end
end

--- Closes the holes left by tombstoned slots, renumbering the epochs that
--- moved. With `reindex_all`, every live epoch is renumbered even if it stayed
--- in place (upstream Compact(reindexAll: true)).
function DockSlots.compact(dock, reindex_all)
  local write_index = 0
  for read_pos = 1, #dock._child_slots do
    local slot = dock._child_slots[read_pos]
    if is_live_slot(slot) then
      if reindex_all or write_index ~= (read_pos - 1) then
        move_slot(dock, slot, write_index)
      end
      write_index = write_index + 1
    end
  end
  truncate(dock, write_index)
end

--- The live child epochs, newest slot last.
function DockSlots.children(dock, store)
  store = store or {}
  for _, slot in ipairs(dock._child_slots) do
    if is_live_slot(slot) then
      store[#store + 1] = slot.epoch
    end
  end
  return store
end

--- Detaches every live child, newest first, and empties the table.
function DockSlots.detach_all(dock)
  for index = #dock._child_slots, 1, -1 do
    local slot = dock._child_slots[index]
    if is_live_slot(slot) then
      slot.epoch:detach()
    end
  end
  DockSlots.reset(dock)
end

return DockSlots
