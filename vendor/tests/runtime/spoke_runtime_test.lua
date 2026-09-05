local lu = require("luaunit")
local Epoch = require("vendor.spoke.runtime.epoch")
local LambdaEpoch = require("vendor.spoke.runtime.lambda_epoch")
local Effect = require("vendor.spoke.reactive.effect")
local SpokeRuntime = require("vendor.spoke.runtime.spoke_runtime")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local State = require("vendor.spoke.reactive.state")

TestSpokeRuntime = {}

-- #39: port of SpokeRuntimeTests.Batch_NestedHolds_Stack — nested batches
-- stack their holds; only the outermost release flushes.
function TestSpokeRuntime.test_nested_batches_hold_until_outermost_releases()
  local ports
  local ticks = 0
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      ports = s:ports()
      return function()
        ticks = ticks + 1
      end
    end,
  })

  local tree = SpokeTree.spawn(Root.new())
  lu.assertEquals(ticks, 1)

  SpokeRuntime.batch(function()
    ports:request_tick()
    lu.assertEquals(ticks, 1, "outer hold defers")

    SpokeRuntime.batch(function()
      ports:request_tick()
      lu.assertEquals(ticks, 1, "inner hold defers")
    end)
    lu.assertEquals(ticks, 1, "inner release does not flush under outer hold")

    SpokeRuntime.batch(function()
      ports:request_tick()
      lu.assertEquals(ticks, 1, "sibling inner hold defers again")
    end)
    lu.assertEquals(ticks, 1)
  end)

  lu.assertEquals(ticks, 2, "outermost release flushes exactly once")

  tree:dispose()
end

-- #39: port of SpokeRuntimeTests.AutoTrees_OrderedByCreation_WhenSameFlushLayer
-- — auto trees spawned in one batch flush in creation order.
function TestSpokeRuntime.test_auto_trees_flush_in_creation_order_within_batch()
  local log = {}
  local function make(label)
    local Root = Epoch.extend("Root" .. label, {
      init = function()
        return function()
          log[#log + 1] = label
        end
      end,
    })
    return SpokeTree.spawn(Root.new())
  end

  local a, b
  SpokeRuntime.batch(function()
    a = make("A")
    b = make("B")
  end)

  lu.assertEquals(log, { "A", "B" })

  a:dispose()
  b:dispose()
end

-- #39/#46: port of SpokeRuntimeTests.SpawnEager_OutranksSpawn_WhenSameBatch —
-- the eager tree (flush layer -1) must outrank the default tree even when the
-- normal tree was created first in the same batch; creation order alone would
-- produce E,N even if the eager layer priority regressed.
function TestSpokeRuntime.test_eager_tree_flushes_before_normal_tree_in_same_batch()
  local log = {}
  local function make(label)
    local Root = Epoch.extend("Root" .. label, {
      init = function()
        return function()
          log[#log + 1] = label
        end
      end,
    })
    return Root.new()
  end

  local eager, normal
  SpokeRuntime.batch(function()
    normal = SpokeTree.spawn(make("N"))
    eager = SpokeTree.spawn_eager(make("E"))
  end)

  lu.assertEquals(log, { "E", "N" },
    "eager layer must outrank the earlier-spawned normal tree in the same batch")

  eager:dispose()
  normal:dispose()
end

-- #39/#46: port of SpokeRuntimeTests.SpawnEager_EnablesWriteThenRead_ViaNestedFlush.
-- When the default tree mutates `src` during its tick, the eager tree that
-- derives from `src` must flush NESTED (its layer -1 outranks layer 0) so the
-- default tree can immediately read the fresh derived value in the same tick.
function TestSpokeRuntime.test_eager_write_visible_to_later_normal_tree()
  local src = State.new(0)
  local derived = State.new(0)
  local go = State.new(false)
  local observed = -1

  local eager = SpokeTree.spawn_eager(Effect.new("derive", function(s)
    derived:set(s:d(src) * 2)
  end))
  local normal = SpokeTree.spawn(Effect.new("writer", function(s)
    if s:d(go) then
      src:set(5)
      observed = derived:now()
    end
  end))

  go:set(true)

  lu.assertEquals(observed, 10,
    "eager tree must flush nested on src change so the writer reads fresh derived value")

  normal:dispose()
  eager:dispose()
end

-- #39/#46: port of SpokeRuntimeTests.CompareTo_OrdersBySpawnOrder_WhileSpawnedTreeIsBoosted.
-- A nested-spawned tree receives a scoped scheduling boost so it flushes in
-- the current pass, but that boost must not leak into Epoch ordering:
-- SpokeTree overrides compare_to for the scheduler, so the assertion calls
-- the base epoch-comparison seam `_compare_to`, the colon-call equivalent of
-- upstream's `(inner as Epoch).CompareTo(main)`.
function TestSpokeRuntime.test_boosted_tree_flushes_in_same_pass_and_boost_expires()
  local inner = nil
  local cmp_during_boost = 0
  local main = nil
  main = LambdaEpoch.new("Main", function(s)
    return function()
      if inner ~= nil then
        return
      end
      inner = SpokeTree.spawn("Inner", LambdaEpoch.new("InnerRoot", function(s)
        return nil
      end))
      cmp_during_boost = inner:_compare_to(main)
    end
  end)

  local outer = SpokeTree.spawn("Outer", main)

  lu.assertTrue(cmp_during_boost > 0,
    "nested-spawned Inner must order after Outer while its scheduling boost is active")
  lu.assertNil(SpokeRuntime._boosted_trees[inner], "boost expired after bootstrap")
  lu.assertNil(SpokeRuntime._boosted_trees[outer])

  outer:dispose()
  inner:dispose()
end
