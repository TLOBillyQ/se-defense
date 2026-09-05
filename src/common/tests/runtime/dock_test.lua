local lu = require("luaunit")
local Dock = require("src.common.spoke.runtime.dock")
local LambdaEpoch = require("src.common.spoke.runtime.lambda_epoch")
local SpokeRuntime = require("src.common.spoke.runtime.spoke_runtime")
local SpokeTree = require("src.common.spoke.runtime.spoke_tree")
local State = require("src.common.spoke.reactive.state")
local Trigger = require("src.common.spoke.reactive.trigger")

TestDock = {}

function TestDock.test_call_attaches_epoch()
  local attached = false
  local ticked = false
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    attached = true
    return function()
      ticked = true
    end
  end))

  lu.assertTrue(attached)
  lu.assertFalse(ticked)

  tree:flush()
  lu.assertTrue(ticked)
end

function TestDock.test_call_children_tick_in_attach_order()
  local ticked = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("x", LambdaEpoch.new(function(s)
    return function()
      ticked[#ticked + 1] = "x"
    end
  end))
  dock:call("a", LambdaEpoch.new(function(s)
    return function()
      ticked[#ticked + 1] = "a"
    end
  end))
  dock:call("m", LambdaEpoch.new(function(s)
    return function()
      ticked[#ticked + 1] = "m"
    end
  end))

  tree:flush()

  lu.assertEquals(ticked, { "x", "a", "m" })
end

function TestDock.test_call_on_existing_key_first_detaches_old_child()
  local log = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "first-cleanup"
    end)
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    log[#log + 1] = "second-attached"
    return nil
  end))

  lu.assertEquals(log, { "first-cleanup", "second-attached" })
end

function TestDock.test_drop_missing_key_is_no_op()
  local dock
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  lu.assertNil(dock:drop("never-attached"))
end

function TestDock.test_drop_non_string_key_throws()
  local dock
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  lu.assertErrorMsgContains("Dock keys must be non-empty strings", function()
    dock:drop({})
  end)
  lu.assertError(function()
    dock:drop(1)
  end)

  tree:dispose()
end

function TestDock.test_drop_nil_is_no_op_and_child_stays_attached()
  local cleaned = false
  local dock
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      cleaned = true
    end)
    return nil
  end))

  lu.assertNil(dock:drop(nil))
  lu.assertFalse(cleaned, "drop(nil) must not detach an existing child")

  dock:drop("k")
  lu.assertTrue(cleaned, "the child remains attached and can be dropped later")

  tree:dispose()
end

function TestDock.test_drop_missing_or_empty_key_is_no_op()
  local cleaned = false
  local dock
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      cleaned = true
    end)
    return nil
  end))

  lu.assertNil(dock:drop("missing"))
  lu.assertNil(dock:drop(""))
  lu.assertFalse(cleaned, "missing/empty-string drops must leave the child attached")

  tree:dispose()
end

function TestDock.test_drop_detaches_child_and_runs_cleanup()
  local cleaned = false
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      cleaned = true
    end)
    return nil
  end))

  dock:drop("k")
  lu.assertTrue(cleaned)
end

function TestDock.test_drop_self_during_attach_runs_cleanup_and_does_not_tick()
  local log = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    dock:drop("k")
    s:on_cleanup(function()
      log[#log + 1] = "cleanup"
    end)
    return function()
      log[#log + 1] = "tick"
    end
  end))

  tree:flush()

  lu.assertNil(tree.fault)
  lu.assertEquals(log, { "cleanup" })
end

function TestDock.test_call_same_key_during_own_attach_replaces_self()
  local log = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("k", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "old-cleanup"
    end)
    dock:call("k", LambdaEpoch.new(function(s)
      log[#log + 1] = "new-attached"
      return function()
        log[#log + 1] = "new-tick"
      end
    end))
    return function()
      log[#log + 1] = "old-tick"
    end
  end))

  tree:flush()

  lu.assertEquals(log, { "new-attached", "old-cleanup", "new-tick" })
  lu.assertNil(tree.fault)
end

function TestDock.test_call_under_heavy_churn_children_still_tick_in_attach_order()
  local dock
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  for round = 0, 199 do
    local ticked = {}
    for k = 0, 3 do
      local stamp = round * 4 + k
      dock:call(tostring(k), LambdaEpoch.new(function(s)
        return function()
          ticked[#ticked + 1] = stamp
        end
      end))
    end
    tree:flush()
    local expected = {}
    for k = 0, 3 do
      expected[#expected + 1] = round * 4 + k
    end
    lu.assertEquals(ticked, expected)
  end
end

function TestDock.test_call_under_heavy_churn_descendants_still_tick_in_tree_coord_order()
  local ticked = {}
  local ports = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  for c = 0, 2 do
    local name = "c" .. c
    dock:call(name, LambdaEpoch.new(function(s)
      s:call(LambdaEpoch.new(function(inner_s)
        ports[name .. "-inner"] = inner_s:ports()
        return function()
          ticked[#ticked + 1] = name .. "-inner"
        end
      end))
      ports[name] = s:ports()
      return function()
        ticked[#ticked + 1] = name
      end
    end))
  end
  tree:flush()

  for i = 0, 599 do
    dock:call("churn", LambdaEpoch.new(function(s)
      return nil
    end))
  end
  dock:drop("churn")
  tree:flush()

  ticked = {}
  for _, key in ipairs({ "c1", "c2-inner", "c0", "c1-inner", "c2", "c0-inner" }) do
    ports[key]:request_tick()
  end
  tree:flush()

  lu.assertEquals(ticked, { "c0-inner", "c0", "c1-inner", "c1", "c2-inner", "c2" })
end

function TestDock.test_nested_dock_children_keep_correct_order_after_outer_dock_sweeps()
  local outer
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    outer = s:call(Dock.new())
    return nil
  end))

  for i = 0, 249 do
    outer:call("filler" .. i, LambdaEpoch.new(function(s)
      return nil
    end))
  end

  local inner
  outer:call("innerHost", LambdaEpoch.new(function(s)
    inner = s:call(Dock.new())
    return nil
  end))
  local inner_child = inner:call("c", LambdaEpoch.new(function(s)
    return nil
  end))
  local neighbour = outer:call("neighbour", LambdaEpoch.new(function(s)
    return nil
  end))

  lu.assertTrue(inner_child:compare_to(neighbour) < 0)

  for i = 0, 5 do
    outer:call("extra" .. i, LambdaEpoch.new(function(s)
      return nil
    end))
  end
  for i = 0, 249 do
    outer:drop("filler" .. i)
  end
  for i = 0, 5 do
    outer:drop("extra" .. i)
  end

  outer:call("trigger", LambdaEpoch.new(function(s)
    return nil
  end))

  lu.assertTrue(inner_child:compare_to(neighbour) < 0)
end

function TestDock.test_dock_cleanup_detaches_children_in_reverse_attach_order()
  local log = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:call("x", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "x"
    end)
    return nil
  end))
  dock:call("a", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "a"
    end)
    return nil
  end))
  dock:call("m", LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "m"
    end)
    return nil
  end))

  tree:dispose()

  lu.assertEquals(log, { "m", "a", "x" })
end

function TestDock.test_call_while_detaching_throws()
  local caught = nil

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    local dock = s:call(Dock.new())
    dock:call("k", LambdaEpoch.new(function(s)
      s:on_cleanup(function()
        local ok, err = pcall(function()
          dock:call("late", LambdaEpoch.new(function(s)
            return nil
          end))
        end)
        caught = not ok and err
      end)
      return nil
    end))
    return nil
  end))

  tree:dispose()

  lu.assertNotNil(caught)
end

function TestDock.test_call_child_init_throws_leaves_runtime_stack_balanced()
  local log = {}
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  local ok = pcall(function()
    dock:call("k", LambdaEpoch.new(function(s)
      s:on_cleanup(function()
        log[#log + 1] = "partial-cleanup"
      end)
      error("boom")
    end))
  end)

  lu.assertFalse(ok)
  lu.assertEquals(#SpokeRuntime.frames, 0)

  dock:call("k", LambdaEpoch.new(function(s)
    log[#log + 1] = "replacement-attached"
    return function()
      log[#log + 1] = "replacement-tick"
    end
  end))
  tree:flush()

  lu.assertEquals(log, { "partial-cleanup", "replacement-attached", "replacement-tick" })
  lu.assertNil(tree.fault)
end

-- #33: refreshing a nested dock's coords must compact its child slots
-- (upstream Compact(reindexAll: true)); otherwise holey slot lists leave
-- child coords unpackable (INVALID) after the parent dock reindexes it.
function TestDock.test_refresh_coords_compacts_nested_dock_children()
  local inner
  local outer

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    outer = s:call(Dock.new())
    return nil
  end))

  outer:call("filler", LambdaEpoch.new(function() end))
  outer:call("innerHost", LambdaEpoch.new(function(s)
    inner = s:call(Dock.new())
    return nil
  end))

  -- Inner: fill 300 slots, drop the first 100 (holes), so the live child
  -- lands past the packable index (MAX_INDEX = 255) and cannot re-pack.
  for i = 1, 300 do
    inner:call("fill" .. i, LambdaEpoch.new(function() end))
  end
  for i = 1, 100 do
    inner:drop("fill" .. i)
  end
  local inner_child = inner:call("c", LambdaEpoch.new(function() end))
  lu.assertFalse(inner_child._coords:is_valid(),
    "child coord should overflow at slot 300")

  -- Outer: hole at slot 0 (dropped filler) so the compaction must move the
  -- inner dock; long holey list makes the next call auto-compact, which
  -- reindexes the inner dock and (via #33) re-packs its children.
  outer:drop("filler")
  for i = 2, 301 do
    outer:call("fill" .. i, LambdaEpoch.new(function() end))
  end
  for i = 2, 201 do
    outer:drop("fill" .. i)
  end
  local trigger = outer:call("trigger", LambdaEpoch.new(function() end))

  lu.assertTrue(inner_child._coords:is_valid(),
    "inner child coords must be packable again after compaction")
  lu.assertTrue(inner_child:compare_to(trigger) < 0,
    "relative order preserved after compaction")

  tree:dispose()
end

-- #37: DockExtensions port — keyed effects with EffectBuilder-style argument
-- shapes, key reuse replacing the previous effect, triggers passing through,
-- and child effects cleaned up when the dock detaches.
function TestDock.test_effect_reuse_detaches_previous_and_triggers_pass_through()
  local state = State.new(0)
  local trigger = Trigger.new()
  local runs = 0
  local cleanups = 0
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:effect("k", function(s2)
    runs = runs + 1
    local _ = s2:d(state)
    s2:on_cleanup(function()
      cleanups = cleanups + 1
    end)
  end, trigger)

  tree:flush()
  lu.assertEquals(runs, 1)

  trigger:invoke()
  tree:flush()
  lu.assertEquals(runs, 2, "static trigger passes through to the effect")
  lu.assertEquals(cleanups, 1, "rerun rollback cleaned the tick attachments")

  dock:effect("k", function(s2)
    local _ = s2:d(state)
  end)
  lu.assertEquals(cleanups, 2, "reusing the key detaches the old effect")

  state:set(1)
  tree:flush()
  lu.assertEquals(runs, 2, "old effect no longer reruns")

  tree:dispose()
end

function TestDock.test_effect_named_form_and_dock_detach_cleanup()
  local cleanups = 0
  local dock

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))

  dock:effect("k", "named", function(s2)
    s2:on_cleanup(function()
      cleanups = cleanups + 1
    end)
  end)

  tree:flush()
  lu.assertEquals(cleanups, 0)

  tree:dispose()
  lu.assertEquals(cleanups, 1, "dock detach cleans up its child effects")
end
