-- Property tests for PackedTreeCoords (vendor/spoke/runtime/packed_tree_coords.lua).
--
-- The coordinate is an immutable {hi, lo, depth} 128-bit simulation compared
-- with math.ult; these properties pin the ordering semantics the epoch tree
-- scheduler relies on (docs/research/packed-tree-coords-facts.md, invariants
-- F.1-6). A signed comparison of hi/lo, a wrong shift, or a wrong word would
-- break one of these.
local property = require("vendor.tests.property.support.property")
local PackedTreeCoords = require("vendor.spoke.runtime.packed_tree_coords")

local gen = property.gen

-- A valid coordinate as a chain of extends from ROOT.
local function coord_gen(rng)
  local coord = PackedTreeCoords.ROOT
  for _ = 1, rng:int(0, 12) do
    coord = coord:extend(rng:int(0, PackedTreeCoords.MAX_INDEX))
  end
  return coord
end

-- An arbitrary value of the full value space (raw words + depth), including
-- Invalid and word patterns that set bit 63 (compare must be unsigned).
local function raw_coord_gen(rng)
  return PackedTreeCoords.new(rng:next(), rng:next(), rng:int(0, 255))
end

local function sign(c)
  return c < 0 and -1 or (c > 0 and 1 or 0)
end

-- A set of coordinates, mixed valid chains and raw values.
local function coord_set_gen(rng)
  local set = {}
  for _ = 1, rng:int(2, 6) do
    if rng:boolean() then
      set[#set + 1] = coord_gen(rng)
    else
      set[#set + 1] = raw_coord_gen(rng)
    end
  end
  return set
end

local LESS = -1
local EQUAL = 0
local GREATER = 1

-- compare_to is a total order: reflexive, antisymmetric, trichotomous, and
-- transitive over arbitrary sets of coordinates.
property.forall("compare_to_is_a_total_order", { coord_set_gen }, function(set)
  for _, a in ipairs(set) do
    if a:compare_to(a) ~= EQUAL then
      return "compare_to is not reflexive for " .. tostring(a)
    end
    for _, b in ipairs(set) do
      local ab = sign(a:compare_to(b))
      local ba = sign(b:compare_to(a))
      if ab ~= -ba then
        return "antisymmetry violated: " .. tostring(a) .. " vs " .. tostring(b)
      end
      for _, c in ipairs(set) do
        -- trichotomy is implied by sign() being one of -1/0/1 after the
        -- antisymmetry check; check transitivity for strict chains.
        if ab == LESS and sign(b:compare_to(c)) == LESS
           and sign(a:compare_to(c)) ~= LESS then
          return "transitivity violated: " .. tostring(a) .. " < "
            .. tostring(b) .. " < " .. tostring(c)
        end
      end
    end
  end
  return true
end)

-- An ordered pair of distinct child indices (lo < hi) under one parent.
local function index_pair_gen(rng)
  local lo = rng:int(0, PackedTreeCoords.MAX_INDEX - 1)
  return { lo, lo + rng:int(1, PackedTreeCoords.MAX_INDEX - lo) }
end

-- extend is monotonic in the child index: a lower index yields a strictly
-- earlier coordinate than a higher one under the same parent.
property.forall("extend_is_monotonic_in_child_index",
  { coord_gen, index_pair_gen },
  function(parent, pair)
    if type(pair) ~= "table" or pair[1] == nil or pair[2] == nil then
      return true -- shrunk-away pair
    end
    local lo_index, hi_index = pair[1], pair[2]
    if parent.depth >= PackedTreeCoords.MAX_DEPTH then
      return true -- parent is full; both extends are Invalid
    end
    local left = parent:extend(lo_index)
    local right = parent:extend(hi_index)
    if left:compare_to(right) >= 0 then
      return string.format("extend(%d) should precede extend(%d) under depth %d",
        lo_index, hi_index, parent.depth)
    end
    return true
  end)

-- Extending any valid coordinate yields a strict descendant: the ancestor
-- sorts before its child, even when the child index packs to zero bits.
property.forall("extend_yields_strict_descendant",
  { coord_gen, gen.integer(0, PackedTreeCoords.MAX_INDEX) },
  function(parent, idx)
    if parent.depth >= PackedTreeCoords.MAX_DEPTH then
      return true -- cannot extend a full coordinate
    end
    local child = parent:extend(idx)
    if parent:compare_to(child) >= 0 then
      return string.format("parent should sort before its child (depth %d)",
        parent.depth)
    end
    return true
  end)

-- ROOT is the least valid coordinate: every valid coordinate compares at or
-- after it, and only ROOT itself compares equal.
property.forall("root_is_least", { coord_gen }, function(coord)
  local cmp = PackedTreeCoords.ROOT:compare_to(coord)
  if cmp > 0 then
    return "ROOT should be the least coordinate"
  end
  if cmp == 0 and coord.depth ~= 0 then
    return "ROOT compare equal only to ROOT"
  end
  return true
end)

-- Equal coordinate chains compare equal: building the same chain twice yields
-- equal coordinates, and equal starting points stay equal under the same
-- extension chain. (Same-depth restriction in the second property's
-- generation is a property of lexicographic order, not an implementation
-- detail: appending a suffix preserves order only when neither coordinate is
-- a prefix of the other.)
property.forall("equal_chains_compare_equal",
  { gen.array(gen.integer(0, PackedTreeCoords.MAX_INDEX), 12) },
  function(chain)
    local a = PackedTreeCoords.ROOT
    local b = PackedTreeCoords.ROOT
    for _, idx in ipairs(chain) do
      a = a:extend(idx)
      b = b:extend(idx)
    end
    if a:compare_to(b) ~= EQUAL then
      return "same chain from ROOT built unequal coordinates"
    end
    return true
  end)

-- Comparison is stable under applying the same extension suffix to
-- equal-depth coordinates: the first differing byte wins at the same layer
-- both before and after the common suffix.
property.forall("suffix_extends_are_order_preserving_for_equal_depth",
  { coord_gen, coord_gen, gen.array(gen.integer(0, PackedTreeCoords.MAX_INDEX), 8) },
  function(left, right, suffix)
    if left.depth ~= right.depth then
      return true -- property statement applies to equal-depth coordinates
    end
    if left.depth + #suffix > PackedTreeCoords.MAX_DEPTH then
      return true -- chain would overflow into Invalid
    end
    local before = sign(left:compare_to(right))
    local a, b = left, right
    for _, idx in ipairs(suffix) do
      a = a:extend(idx)
      b = b:extend(idx)
    end
    local after = sign(a:compare_to(b))
    if before ~= after then
      return "common suffix changed the ordering of equal-depth coordinates"
    end
    return true
  end)

-- compare_to stays equal to 0 and consistent across equal starting points
-- extended by the same chain: two independently built copies of the same
-- coordinate compare equal after the same suffix.
property.forall("equal_coords_stay_equal_under_same_chain",
  { coord_gen, gen.array(gen.integer(0, PackedTreeCoords.MAX_INDEX), 8) },
  function(coord, suffix)
    local a = PackedTreeCoords.new(coord.hi, coord.lo, coord.depth)
    local b = PackedTreeCoords.new(coord.hi, coord.lo, coord.depth)
    for _, idx in ipairs(suffix) do
      a = a:extend(idx)
      b = b:extend(idx)
    end
    if a:compare_to(b) ~= EQUAL then
      return "equal coordinates diverged under the same extension chain"
    end
    return true
  end)
