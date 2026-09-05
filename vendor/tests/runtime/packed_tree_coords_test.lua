-- LuaUnit port of upstream Tests~/RuntimeTests/PackedTreeCoordsTests.cs.
-- Invariant list F.1–6 in docs/research/packed-tree-coords-facts.md; design
-- per ADR docs/adr/0001-tree-coords-128bit-simulation.md (#3).
local lu = require("luaunit")
local PackedTreeCoords = require("vendor.spoke.runtime.packed_tree_coords")

-- Mirror of upstream PackedTreeCoordsTests.Path: extend the root through indices.
local function path(...)
  local coord = PackedTreeCoords.ROOT
  for _, i in ipairs({ ... }) do
    coord = coord:extend(i)
  end
  return coord
end

TestPackedTreeCoords = {}

function TestPackedTreeCoords.test_compare_parent_before_deeper_child()
  local parent = PackedTreeCoords.ROOT:extend(0)
  local child = parent:extend(0)
  lu.assertTrue(parent:compare_to(child) < 0)
  lu.assertTrue(child:compare_to(parent) > 0)
end

function TestPackedTreeCoords.test_compare_left_sibling_before_right()
  local left = PackedTreeCoords.ROOT:extend(0)
  local right = PackedTreeCoords.ROOT:extend(1)
  lu.assertTrue(left:compare_to(right) < 0)
end

function TestPackedTreeCoords.test_compare_nested_ordering_matches_imperative_walk()
  -- A representative epoch tree -- coords must sort in depth-first
  -- (imperative walk) order:
  --   []          (tree root)
  --   [0]         (Main)
  --   [0,0]       (epoch)
  --   [0,0,0]     (epoch *)
  --   [0,0,1]
  --   [0,1]       (epoch *)
  --   [0,1,0]     (epoch *)
  --   [0,1,1]
  local coords = {
    PackedTreeCoords.ROOT,
    path(0),
    path(0, 0),
    path(0, 0, 0),
    path(0, 0, 1),
    path(0, 1),
    path(0, 1, 0),
    path(0, 1, 1),
  }
  for i = 1, #coords - 1 do
    lu.assertTrue(coords[i]:compare_to(coords[i + 1]) < 0,
      string.format("coord[%d] should be before coord[%d]", i, i + 1))
  end
end

-- The first layers pack into one word and the rest into a second, so ordering
-- has to hold within each word and across the seam between them.
function TestPackedTreeCoords.test_compare_orders_correctly_across_both_packed_words()
  -- Diverging at a deep layer, well past the seam
  local a = path(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0)
  local b = path(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 1)
  lu.assertTrue(a:compare_to(b) < 0)

  -- A divergence in an early layer outranks anything deeper
  local early = path(0, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9)
  local late = path(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  lu.assertTrue(early:compare_to(late) < 0)

  -- A coord sorts before one that extends it, including right at the seam
  local at_seam = path(1, 1, 1, 1, 1, 1, 1, 1)
  lu.assertTrue(at_seam:compare_to(at_seam:extend(0)) < 0)
  lu.assertTrue(at_seam:extend(0):compare_to(at_seam:extend(1)) < 0)
end

function TestPackedTreeCoords.test_constants_match_upstream_bit_budget()
  -- 16 layers x 256 wide (upstream MaxIndex / MaxDepth public constants).
  lu.assertEquals(PackedTreeCoords.MAX_INDEX, 255)
  lu.assertEquals(PackedTreeCoords.MAX_DEPTH, 16)
end

function TestPackedTreeCoords.test_extend_uses_full_capacity_then_yields_invalid()
  local deep = PackedTreeCoords.ROOT
  for _ = 1, 16 do
    deep = deep:extend(255)
  end
  lu.assertTrue(deep:is_valid())
  lu.assertFalse(deep:extend(0):is_valid())
end

function TestPackedTreeCoords.test_extend_index_out_of_range_yields_invalid()
  lu.assertFalse(PackedTreeCoords.ROOT:extend(256):is_valid())
  lu.assertFalse(PackedTreeCoords.ROOT:extend(-1):is_valid())
end

function TestPackedTreeCoords.test_extend_of_invalid_stays_invalid()
  lu.assertFalse(PackedTreeCoords.INVALID:extend(0):is_valid())
end

-- Not an upstream test: pins the ADR 0001 "immutable value object" decision
-- behaviorally (upstream gets it for free from `readonly struct`): extend
-- returns a new value and never mutates its receiver.
function TestPackedTreeCoords.test_extend_is_value_semantic_no_mutation()
  local parent = path(1)
  local child = parent:extend(2)
  lu.assertNotEquals(parent, child)
  lu.assertEquals(parent.depth, 1)
  lu.assertEquals(parent:compare_to(path(1)), 0)
  lu.assertTrue(parent:compare_to(child) < 0)
end

-- Not an upstream test: layer values >= 128 set bit 63, so hi/lo must compare
-- unsigned (math.ult); signed `<` would sort them first instead of last.
-- Upstream cannot express this bug (ulong.CompareTo is unsigned by
-- definition), so no upstream test pins it.
function TestPackedTreeCoords.test_compare_unsigned_when_layer_sets_high_bit()
  local small = path(1)
  local big = path(200)
  lu.assertTrue(small:compare_to(big) < 0)
  lu.assertTrue(big:compare_to(small) > 0)
  -- Same guard on the lo word, past the seam.
  local lo_small = path(0, 0, 0, 0, 0, 0, 0, 0, 1)
  local lo_big = path(0, 0, 0, 0, 0, 0, 0, 0, 200)
  lu.assertTrue(lo_small:compare_to(lo_big) < 0)
  lu.assertTrue(lo_big:compare_to(lo_small) > 0)
end
