local lu = require("luaunit")
local EpochCursor = require("src.common.spoke.runtime.epoch_cursor")

-- Build a minimal fake epoch tree: only the fields EpochCursor reads.
local function make_epoch(name, parent, coord_index, depth, tick_index)
  local epoch = {
    name = name,
    _parent = parent,
    _coord_index = coord_index,
    _depth = depth,
    _tick_index = tick_index,
  }
  return epoch
end

TestEpochCursor = {}

function TestEpochCursor.test_compare_orders_siblings_by_coord_index()
  local root = make_epoch("root", nil, 0, 0, -1)
  local a = make_epoch("a", root, 0, 1, -1)
  local b = make_epoch("b", root, 1, 1, -1)

  lu.assertEquals(EpochCursor.compare(a, a), 0)
  lu.assertTrue(EpochCursor.compare(a, b) < 0)
  lu.assertTrue(EpochCursor.compare(b, a) > 0)
end

function TestEpochCursor.test_compare_orders_ancestor_before_descendant()
  local root = make_epoch("root", nil, 0, 0, -1)
  local child = make_epoch("child", root, 0, 1, -1)
  local grandchild = make_epoch("grandchild", child, 0, 2, -1)

  lu.assertTrue(EpochCursor.compare(root, child) < 0)
  lu.assertTrue(EpochCursor.compare(child, grandchild) < 0)
end

function TestEpochCursor.test_compare_falls_back_for_deep_divergence()
  -- Depth 17 forces packed coords invalid, so EpochCursor.compare walks parents.
  local root = make_epoch("root", nil, 0, 0, -1)
  local function chain(side)
    local parent = root
    local leaf
    for depth = 1, 17 do
      leaf = make_epoch(side .. "-" .. depth, parent, side == "left" and 0 or 1, depth, -1)
      parent = leaf
    end
    return leaf
  end

  local left_leaf = chain("left")
  local right_leaf = chain("right")

  lu.assertTrue(EpochCursor.compare(left_leaf, right_leaf) < 0)
  lu.assertTrue(EpochCursor.compare(right_leaf, left_leaf) > 0)
end

function TestEpochCursor.test_compare_works_without_global_rawequal()
  local saved_rawequal = rawequal
  _G.rawequal = nil
  package.loaded["src.common.spoke.runtime.epoch_cursor"] = nil

  local ok, err = pcall(function()
    local EpochCursorNoRaw = require("src.common.spoke.runtime.epoch_cursor")
    local root = make_epoch("root", nil, 0, 0, -1)
    local a = make_epoch("a", root, 0, 1, -1)
    local b = make_epoch("b", root, 1, 1, -1)

    lu.assertEquals(EpochCursorNoRaw.compare(a, a), 0)
    lu.assertTrue(EpochCursorNoRaw.compare(a, b) < 0)
    lu.assertTrue(EpochCursorNoRaw.compare(b, a) > 0)
  end)

  _G.rawequal = saved_rawequal
  package.loaded["src.common.spoke.runtime.epoch_cursor"] = nil

  lu.assertTrue(ok, err)
end

function TestEpochCursor.test_resolve_coords_builds_root_for_orphan()
  local root = make_epoch("root", nil, 0, 0, -1)
  local coords = EpochCursor.resolve_coords(root)
  lu.assertTrue(coords:is_valid())
  lu.assertEquals(coords.depth, 0)
end
