local lu = require("luaunit")
local Epoch = require("common.spoke.runtime.epoch")
local SpokeError = require("common.spoke.runtime.spoke_error")
local SpokeException = require("common.spoke.runtime.spoke_exception")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local SpokeTree = require("common.spoke.runtime.spoke_tree")

TestSpokeTree = {}

function TestSpokeTree.test_manual_tick_steps_once_and_flush_drains()
  local ports
  local ticks = 0
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      ports = s:ports()
      return function()
        ticks = ticks + 1
        if ticks < 3 then
          ports:request_tick()
        end
      end
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  tree:tick()
  lu.assertEquals(ticks, 1)
  lu.assertTrue(tree:has_pending())

  tree:flush()
  lu.assertEquals(ticks, 3)
  lu.assertFalse(tree:has_pending())
end

function TestSpokeTree.test_auto_tree_flushes_inline_and_batch_defers_until_release()
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
    lu.assertEquals(ticks, 1)
  end)
  lu.assertEquals(ticks, 2)
  lu.assertFalse(tree:has_pending())
end

function TestSpokeTree.test_auto_fault_is_recorded_without_escaping_to_host()
  local Root = Epoch.extend("Root", {
    init = function()
      return function()
        error("tick-boom")
      end
    end,
  })

  local tree = SpokeTree.spawn(Root.new())
  lu.assertTrue(SpokeException.is(tree.fault))
  lu.assertStrContains(tree.fault.cause, "tick-boom")
end

function TestSpokeTree.test_runtime_frame_is_visible_during_tick_and_captured_on_fault()
  local observed_type
  local Root = Epoch.extend("Root", {
    init = function()
      return function()
        observed_type = SpokeRuntime.frames[#SpokeRuntime.frames].type
        error("frame-boom")
      end
    end,
  })

  local tree = SpokeTree.spawn(Root.new())
  lu.assertEquals(observed_type, "Tick")
  lu.assertEquals(tree.fault.stack_snapshot[#tree.fault.stack_snapshot].type, "Tick")
  local bootstrap_seen = false
  for _, frame in ipairs(tree.fault.stack_snapshot) do
    if frame.type == "Bootstrap" then
      bootstrap_seen = true
    end
  end
  lu.assertTrue(bootstrap_seen)
end

function TestSpokeTree.test_manual_drive_rejects_reentrancy()
  local tree
  local Root = Epoch.extend("Root", {
    init = function()
      return function()
        lu.assertError(function()
          tree:flush()
        end)
      end
    end,
  })

  tree = SpokeTree.spawn_manual(Root.new())
  tree:tick()
end

function TestSpokeTree.test_auto_and_manual_drive_methods_are_separate()
  local auto = SpokeTree.spawn(Epoch.new())
  lu.assertError(function()
    auto:flush()
  end)
  lu.assertError(function()
    auto:tick()
  end)

  local manual = SpokeTree.spawn_manual(Epoch.new())
  lu.assertNil(manual.fault)
end

function TestSpokeTree.test_tree_guard_stops_a_ping_ponging_manual_tree()
  local first_ports
  local second_ports
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(Epoch.extend("First", {
        init = function(_, child_s)
          first_ports = child_s:ports()
          return function()
            second_ports:request_tick()
          end
        end,
      }).new())
      s:call(Epoch.extend("Second", {
        init = function(_, child_s)
          second_ports = child_s:ports()
          return function()
            first_ports:request_tick()
          end
        end,
      }).new())
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  tree:flush()

  lu.assertNotNil(tree.fault)
  lu.assertFalse(tree:has_pending())
end

function TestSpokeTree.test_flush_can_process_more_than_1000_ordinary_epochs()
  local ticks = 0
  local Child = Epoch.extend("Child", {
    init = function()
      return function()
        ticks = ticks + 1
      end
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      for _ = 1, 1001 do
        s:call(Child.new())
      end
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  tree:flush()

  lu.assertEquals(ticks, 1001)
  lu.assertNil(tree.fault)
end

function TestSpokeTree.test_nested_auto_tree_flushes_inside_creator_frame()
  local log = {}
  local inner
  local outer = SpokeTree.spawn(Epoch.extend("Outer", {
    init = function()
      return function()
        log[#log + 1] = "before"
        inner = SpokeTree.spawn(Epoch.extend("Inner", {
          init = function()
            return function()
              log[#log + 1] = "inner"
            end
          end,
        }).new())
        log[#log + 1] = "after"
      end
    end,
  }).new())

  lu.assertEquals(log, { "before", "inner", "after" })
  lu.assertNil(outer.fault)
  lu.assertNil(inner.fault)
end

function TestSpokeTree.test_runtime_guard_stops_cross_tree_ping_pong()
  local first_ports
  local second_ports
  local armed = false
  local messages = {}
  local first_ticks = 0
  local previous_log = SpokeError.log
  SpokeError.log = function(message)
    messages[#messages + 1] = tostring(message)
  end

  local first = SpokeTree.spawn(Epoch.extend("FirstTree", {
    init = function(_, s)
      first_ports = s:ports()
      return function()
        first_ticks = first_ticks + 1
        if armed then
          second_ports:request_tick()
        end
      end
    end,
  }).new())
  local second = SpokeTree.spawn(Epoch.extend("SecondTree", {
    init = function(_, s)
      second_ports = s:ports()
      return function()
        if armed then
          first_ports:request_tick()
        end
      end
    end,
  }).new())
  armed = true
  first_ports:request_tick()
  SpokeError.log = previous_log

  lu.assertNotNil(first)
  lu.assertNotNil(second)
  lu.assertTrue(table.concat(messages, "\n"):find("oscillation limit", 1, true) ~= nil)

  armed = false
  local before_rearm = first_ticks
  first_ports:request_tick()
  lu.assertEquals(first_ticks, before_rearm + 1)
end

function TestSpokeTree.test_dispose_during_tick_is_deferred_until_tick_returns()
  local log = {}
  local frames_during_cleanup
  local tree
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function()
        log[#log + 1] = "cleanup"
        frames_during_cleanup = #SpokeRuntime.frames
      end)
      return function()
        log[#log + 1] = "before"
        tree:dispose()
        log[#log + 1] = "after"
      end
    end,
  })

  tree = SpokeTree.spawn_manual(Root.new())
  tree:flush()
  lu.assertEquals(log, { "before", "after", "cleanup" })
  lu.assertEquals(frames_during_cleanup, 0)
end


-- #31: a root tree's _request_tick must route to the runtime scheduler, not
-- fall back to inserting the tree into its own pending heap (which would tick
-- the tree itself as if it were a plain epoch).
function TestSpokeTree.test_tree_request_tick_routes_to_runtime_not_own_heap()
  local ticks = 0
  local Root = Epoch.extend("Root", {
    init = function()
      return function()
        ticks = ticks + 1
      end
    end,
  })

  local tree = SpokeTree.spawn(Root.new())
  lu.assertEquals(ticks, 1)

  SpokeRuntime.batch(function()
    tree:_request_tick()
    -- Queued on the runtime scheduler (try_flush is held by the batch),
    -- while the tree's own pending heap stays empty.
    lu.assertTrue(tree._runtime_pending)
    lu.assertEquals(SpokeRuntime._scheduled_trees:count(), 1)
    lu.assertEquals(tree._pending:count(), 0)
  end)

  tree:dispose()
end

-- #31: manual trees are driven explicitly; a self-tick request is a no-op.
function TestSpokeTree.test_manual_tree_request_tick_is_inert()
  local Root = Epoch.extend("Root", {
    init = function()
      return function() end
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  lu.assertEquals(tree._pending:count(), 1)

  tree:_request_tick()

  lu.assertFalse(tree._runtime_pending)
  lu.assertEquals(tree._pending:count(), 1)

  tree:dispose()
end

function TestSpokeTree.test_new_without_a_name_defaults_the_name_and_flush_mode()
  local Root = Epoch.extend("Root", {
    init = function()
      return nil
    end,
  })

  local tree = SpokeTree.new(Root.new())

  lu.assertEquals(tostring(tree), "SpokeTree")
  lu.assertEquals(tree.flush_mode, "Auto")
  lu.assertEquals(tree.flush_layer, 0)

  tree:dispose()
end

function TestSpokeTree.test_new_takes_a_leading_name_with_mode_and_layer()
  local Root = Epoch.extend("Root", {
    init = function()
      return nil
    end,
  })

  local tree = SpokeTree.new("Named", Root.new(), "Manual", 7)

  lu.assertEquals(tostring(tree), "Named")
  lu.assertEquals(tree.flush_mode, "Manual")
  lu.assertEquals(tree.flush_layer, 7)

  tree:dispose()
end

function TestSpokeTree.test_new_rejects_a_root_that_is_not_an_epoch()
  lu.assertErrorMsgContains(
    "SpokeTree.spawn expects an unattached Epoch root",
    function()
      SpokeTree.new({})
    end)
end

function TestSpokeTree.test_spawn_eager_uses_a_lower_flush_layer_than_spawn()
  local Root = Epoch.extend("Root", {
    init = function()
      return nil
    end,
  })

  local eager = SpokeTree.spawn_eager(Root.new())
  local normal = SpokeTree.spawn(Root.new())

  lu.assertEquals(eager.flush_layer, -1)
  lu.assertEquals(normal.flush_layer, 0)
  lu.assertEquals(eager:compare_to(normal), -1)
  lu.assertEquals(normal:compare_to(eager), 1)

  eager:dispose()
  normal:dispose()
end

function TestSpokeTree.test_spawn_variants_take_a_leading_name()
  local Root = Epoch.extend("Root", {
    init = function()
      return nil
    end,
  })

  local spawned = SpokeTree.spawn("Spawned", Root.new())
  local eager = SpokeTree.spawn_eager("Eager", Root.new())
  local manual = SpokeTree.spawn_manual("Manual", Root.new())

  lu.assertEquals(tostring(spawned), "Spawned")
  lu.assertEquals(tostring(eager), "Eager")
  lu.assertEquals(tostring(manual), "Manual")
  lu.assertEquals(manual.flush_mode, "Manual")

  spawned:dispose()
  eager:dispose()
  manual:dispose()
end

function TestSpokeTree.test_trees_on_one_layer_order_by_creation()
  local Root = Epoch.extend("Root", {
    init = function()
      return nil
    end,
  })

  local first = SpokeTree.spawn(Root.new())
  local second = SpokeTree.spawn(Root.new())

  lu.assertEquals(first:compare_to(second), -1)
  lu.assertEquals(second:compare_to(first), 1)
  lu.assertEquals(first:compare_to(first), 0)

  first:dispose()
  second:dispose()
end

function TestSpokeTree.test_drive_pending_without_a_command_leaves_the_queue_alone()
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

  local tree = SpokeTree.spawn_manual(Root.new())
  ports:request_tick()
  lu.assertTrue(tree:has_pending())

  -- A manual tree carries no command between explicit drives, so a pass that
  -- reaches it anyway must leave the queue untouched.
  local driven = 0
  tree:_drive_pending({
    tick_next = function()
      driven = driven + 1
    end,
  })

  lu.assertEquals(driven, 0)
  lu.assertEquals(ticks, 0)
  lu.assertTrue(tree:has_pending())

  tree:dispose()
end
