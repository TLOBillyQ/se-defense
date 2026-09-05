-- Property tests for Heap (vendor/spoke/runtime/heap.lua), the binary min-heap
-- that orders pending epochs by coordinate. Properties are stated in terms of
-- the comparator contract: remove_min yields values in non-decreasing order,
-- insert/remove count and multiset are conserved, and rebuild restores the
-- invariant without losing or duplicating elements.
local property = require("vendor.tests.property.support.property")
local Heap = require("vendor.spoke.runtime.heap")

local gen = property.gen

-- Comparator contract is numeric (C#-style): negative/zero/positive, like
-- PackedTreeCoords.compare_to and the epoch Ticker's usage.
local ASCENDING = function(a, b)
  return a - b
end

-- A random insert/remove scenario as a list of {op = "insert"|"remove"} steps.
local function scenario_gen(rng)
  local ops = {}
  for _ = 1, rng:int(1, 80) do
    if rng:boolean() then
      ops[#ops + 1] = { op = "insert", value = rng:int(-1000000, 1000000) }
    else
      ops[#ops + 1] = { op = "remove" }
    end
  end
  return ops
end

-- Verify the heap invariant: every node sorts at or after its parent.
local function heap_is_valid(heap)
  local values = heap._values
  for index = 2, #values do
    if heap._compare(values[index], values[math.floor(index / 2)]) < 0 then
      return false
    end
  end
  return true
end

-- Multiset comparison by sorted copy (values here are plain numbers).
local function sort_copy(values)
  local copy = {}
  for i = 1, #values do
    copy[i] = values[i]
  end
  table.sort(copy)
  return copy
end

local function same_multiset(a, b)
  local sorted_a, sorted_b = sort_copy(a), sort_copy(b)
  if #sorted_a ~= #sorted_b then
    return false
  end
  for i = 1, #sorted_a do
    if sorted_a[i] ~= sorted_b[i] then
      return false
    end
  end
  return true
end

-- Draining a heap yields the pushed values in non-decreasing order and each
-- exactly once; the count returns to zero.
property.forall("remove_min_yields_non_decreasing_sequence",
  { gen.array(gen.integer(-1000000, 1000000), 120) }, function(values)
    local heap = Heap.new(ASCENDING)
    for _, value in ipairs(values) do
      heap:insert(value)
    end
    local drained = {}
    while heap:count() > 0 do
      drained[#drained + 1] = heap:remove_min()
    end
    for i = 1, #drained - 1 do
      if drained[i + 1] < drained[i] then
        return string.format("remove_min returned %s after %s",
          drained[i + 1], drained[i])
      end
    end
    if not same_multiset(values, drained) then
      return "drained multiset differs from inserted multiset"
    end
    return true
  end)

-- Random insert/remove sequences conserve the element count, hold the heap
-- invariant after every operation, and every inserted value is removed
-- exactly once: either by a remove_min op or by the final drain.
property.forall("count_conserved_across_insert_remove_sequences",
  { scenario_gen }, function(scenario)
    local heap = Heap.new(ASCENDING)
    local expected = 0
    local inserted = {}
    local removed = {}
    for step_index, step in ipairs(scenario) do
      if step.op == "insert" then
        heap:insert(step.value)
        inserted[#inserted + 1] = step.value
        expected = expected + 1
      elseif step.op == "remove" then
        if expected > 0 then
          removed[#removed + 1] = heap:remove_min()
          expected = expected - 1
        end
      else
        return "unknown op " .. tostring(step.op)
      end
      if heap:count() ~= expected then
        return string.format("count %d at step %d, expected %d",
          heap:count(), step_index, expected)
      end
      if not heap_is_valid(heap) then
        return string.format("heap invariant broken at step %d", step_index)
      end
    end
    while heap:count() > 0 do
      removed[#removed + 1] = heap:remove_min()
    end
    if not same_multiset(inserted, removed) then
      return "removed multiset differs from inserted multiset"
    end
    return true
  end)

-- rebuild restores the heap invariant after an external disturbance, keeps
-- the multiset of values, and is idempotent: a second rebuild is a no-op.
-- The disturbance is a swap inside the internal array: rebuild is meant for
-- exactly this kind of externally-corrupted ordering (upstream uses it after
-- bulk mutations), and insert/remove alone never break the invariant.
property.forall("rebuild_preserves_multiset_and_is_idempotent",
  { gen.array(gen.integer(-1000000, 1000000), 120),
    gen.integer(1, 120), gen.integer(1, 120) },
  function(values, pick_a, pick_b)
    local heap = Heap.new(ASCENDING)
    for _, value in ipairs(values) do
      heap:insert(value)
    end
    local n = #heap._values
    if n < 2 then
      return true
    end
    local a = ((pick_a - 1) % n) + 1
    local b = ((pick_b - 1) % n) + 1
    if a == b then
      return true
    end
    local values_before = heap._values
    values_before[a], values_before[b] = values_before[b], values_before[a]

    heap:rebuild()
    if not heap_is_valid(heap) then
      return "rebuild left the heap invariant broken"
    end
    if not same_multiset(values, heap._values) then
      return "rebuild changed the multiset"
    end

    local snapshot = {}
    for i = 1, #heap._values do
      snapshot[i] = heap._values[i]
    end
    heap:rebuild()
    for i = 1, #snapshot do
      if heap._values[i] ~= snapshot[i] then
        return "rebuild is not idempotent on an already-valid heap"
      end
    end
    return true
  end)
