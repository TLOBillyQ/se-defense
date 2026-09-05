local lu = require("luaunit")
local Epoch = require("src.common.spoke.runtime.epoch")
local SpokeHandle = require("src.common.spoke.runtime.spoke_handle")
local SpokeException = require("src.common.spoke.runtime.spoke_exception")

local function attach_root(epoch, services, tree)
  epoch:_attach(nil, 0, nil, services, tree or epoch)
  return epoch
end

TestEpoch = {}

function TestEpoch.test_init_runs_synchronously_and_call_attaches_child_immediately()
  local log = {}
  local Child = Epoch.extend("Child", {
    init = function()
      log[#log + 1] = "child-init"
    end,
  })
  local Parent = Epoch.extend("Parent", {
    init = function(_, s)
      log[#log + 1] = "parent-init-before-call"
      s:call(Child.new())
      log[#log + 1] = "parent-init-after-call"
    end,
  })

  attach_root(Parent.new())

  lu.assertEquals(log, {
    "parent-init-before-call",
    "child-init",
    "parent-init-after-call",
  })
end

function TestEpoch.test_tick_is_deferred_until_driven()
  local init_ran = false
  local tick_ran = false
  local Root = Epoch.extend("Root", {
    init = function()
      init_ran = true
      return function()
        tick_ran = true
      end
    end,
  })

  local root = attach_root(Root.new())
  lu.assertTrue(init_ran)
  lu.assertFalse(tick_ran)

  root:_tick()

  lu.assertTrue(tick_ran)
end

function TestEpoch.test_tick_rolls_back_tick_attachments_but_keeps_init_attachments()
  local log = {}
  local tick_number = 0
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function()
        log[#log + 1] = "init-cleanup"
      end)
      return function(s)
        local current = tick_number
        tick_number = tick_number + 1
        log[#log + 1] = "tick:" .. current
        s:on_cleanup(function()
          log[#log + 1] = "tick-cleanup:" .. current
        end)
      end
    end,
  })

  local root = attach_root(Root.new())
  root:_tick()
  root:_tick()
  root:detach()

  lu.assertEquals(log, {
    "tick:0",
    "tick-cleanup:0",
    "tick:1",
    "tick-cleanup:1",
    "init-cleanup",
  })
end

function TestEpoch.test_tick_children_are_detached_before_the_next_tick()
  local log = {}
  local Child = Epoch.extend("Child", {
    init = function(_, s)
      s:on_cleanup(function()
        log[#log + 1] = "child-cleanup"
      end)
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      return function(tick_s)
        tick_s:call(Child.new())
        log[#log + 1] = "root-tick"
      end
    end,
  })

  local root = attach_root(Root.new())
  root:_tick()
  root:_tick()

  lu.assertEquals(log, {
    "root-tick",
    "child-cleanup",
    "root-tick",
  })
end

function TestEpoch.test_use_disposes_a_spoke_handle_on_detach()
  local disposed = 0
  local handle = SpokeHandle.of("resource", function(id)
    lu.assertEquals(id, "resource")
    disposed = disposed + 1
  end)
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:use(handle)
    end,
  })

  local root = attach_root(Root.new())
  lu.assertEquals(disposed, 0)
  root:detach()
  lu.assertEquals(disposed, 1)
end

function TestEpoch.test_spoke_handle_disposal_is_idempotent_and_default_is_safe()
  local disposed = 0
  local handle = SpokeHandle.of(1, function()
    disposed = disposed + 1
  end)

  handle:dispose()
  handle:dispose()
  SpokeHandle.new():dispose()

  lu.assertEquals(disposed, 1)
end

function TestEpoch.test_exports_are_visible_only_to_later_siblings()
  local early_saw = nil
  local late_saw = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(Epoch.extend("Early", {
        init = function(_, child_s)
          early_saw = child_s:try_import("hello")
        end,
      }).new())
      s:export("hello", "world")
      s:call(Epoch.extend("Late", {
        init = function(_, child_s)
          local found, value = child_s:try_import("hello")
          late_saw = found and value
        end,
      }).new())
    end,
  })

  attach_root(Root.new())

  lu.assertFalse(early_saw)
  lu.assertEquals(late_saw, "world")
end

function TestEpoch.test_import_walks_ancestors_and_nearest_export_shadows()
  local imported = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:export("service", "root")
      s:call(Epoch.extend("Child", {
        init = function(_, child_s)
          child_s:export("service", "child")
          child_s:call(Epoch.extend("Grandchild", {
            init = function(_, grandchild_s)
              imported = grandchild_s:import("service")
            end,
          }).new())
        end,
      }).new())
    end,
  })

  attach_root(Root.new())

  lu.assertEquals(imported, "child")
end

function TestEpoch.test_services_are_exported_before_root_init()
  local imported = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      imported = s:import("logger")
    end,
  })

  attach_root(Root.new(), { logger = "service" })

  lu.assertEquals(imported, "service")
end

function TestEpoch.test_try_import_distinguishes_exported_nil_from_missing()
  local found = false
  local value = "sentinel"
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:export("optional", nil)
      found, value = s:try_import("optional")
    end,
  })

  attach_root(Root.new())

  lu.assertTrue(found)
  lu.assertNil(value)
end

function TestEpoch.test_extension_constructor_can_accept_an_optional_name()
  local Custom = Epoch.extend("Custom", {
    constructor = function(self, value)
      self.value = value
    end,
  })

  local epoch = Custom.new("Named", 42)

  lu.assertEquals(epoch.name, "Named")
  lu.assertEquals(epoch.value, 42)
end

function TestEpoch.test_import_missing_key_raises()
  local captured = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      local ok, err = pcall(function()
        s:import("missing")
      end)
      captured = not ok and err
    end,
  })

  attach_root(Root.new())

  lu.assertStrContains(captured, "Failed to import: missing")
end

function TestEpoch.test_captured_builder_is_sealed_after_init()
  local captured = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      captured = s
    end,
  })

  attach_root(Root.new())

  local ok = pcall(function()
    captured:on_cleanup(function() end)
  end)
  lu.assertFalse(ok)
end

function TestEpoch.test_captured_ports_request_ticks_and_coalesces_until_tick()
  local scheduler = { calls = 0 }
  function scheduler:_schedule(epoch)
    self.calls = self.calls + 1
    self.last = epoch
  end
  local ports = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      ports = s:ports()
    end,
  })

  local root = attach_root(Root.new(), nil, scheduler)
  lu.assertEquals(scheduler.calls, 1, "Init should auto-arm the first tick")
  lu.assertEquals(scheduler.last, root)

  ports:request_tick()
  ports:request_tick()
  lu.assertEquals(scheduler.calls, 1)

  root:_tick()
  ports:request_tick()
  lu.assertEquals(scheduler.calls, 2)

  root:detach()
  ports:request_tick()
  lu.assertEquals(scheduler.calls, 2)
end

function TestEpoch.test_request_tick_is_deferred_until_the_owner_frame_pops()
  local scheduler = { calls = 0 }
  function scheduler:_schedule()
    self.calls = self.calls + 1
  end
  local ports
  local calls_during_init
  local calls_during_tick
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      ports = s:ports()
      ports:request_tick()
      calls_during_init = scheduler.calls
      return function()
        ports:request_tick()
        calls_during_tick = scheduler.calls
      end
    end,
  })

  local root = attach_root(Root.new(), nil, scheduler)
  lu.assertEquals(calls_during_init, 0)
  lu.assertEquals(scheduler.calls, 1)

  root:_tick()
  lu.assertEquals(calls_during_tick, 1)
  lu.assertEquals(scheduler.calls, 2)
end

function TestEpoch.test_parent_builder_cannot_mutate_while_child_init_is_on_top()
  local parent_builder
  local mutation_allowed
  local Child = Epoch.extend("Child", {
    init = function()
      mutation_allowed = pcall(function()
        parent_builder:on_cleanup(function() end)
      end)
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      parent_builder = s
      s:call(Child.new())
    end,
  })

  attach_root(Root.new())

  lu.assertFalse(mutation_allowed)
end

function TestEpoch.test_attachment_slots_generate_execution_coordinates()
  local first_child = nil
  local second_child = nil
  local Child = Epoch.extend("Child", {})
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function() end)
      s:export("value", true)
      s:use(function() end)
      first_child = s:call(Child.new())
      second_child = s:call(Child.new())
    end,
  })

  local root = attach_root(Root.new())

  lu.assertTrue(first_child:compare_to(second_child) < 0)
  lu.assertTrue(first_child:compare_to(root) < 0)
end

function TestEpoch.test_coordinate_comparison_falls_back_for_wide_attachment_lists()
  local first_child = nil
  local wide_child = nil
  local Child = Epoch.extend("Child", {})
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      for index = 0, 256 do
        local child = s:call(Child.new())
        if index == 0 then
          first_child = child
        elseif index == 256 then
          wide_child = child
        end
      end
    end,
  })

  attach_root(Root.new())

  lu.assertFalse(wide_child._tick_cursor:is_valid())
  lu.assertTrue(first_child:compare_to(wide_child) < 0)
end

function TestEpoch.test_coordinate_comparison_falls_back_for_deep_trees()
  local left_leaf = nil
  local right_leaf = nil
  local function chain(level, sink)
    return Epoch.extend("Node" .. level, {
      init = function(self, s)
        if level == 17 then
          sink(self)
        else
          s:call(chain(level + 1, sink))
        end
      end,
    }).new()
  end
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(chain(0, function(leaf)
        left_leaf = leaf
      end))
      s:call(chain(0, function(leaf)
        right_leaf = leaf
      end))
    end,
  })

  attach_root(Root.new())

  lu.assertFalse(left_leaf._tick_cursor:is_valid())
  lu.assertFalse(right_leaf._tick_cursor:is_valid())
  lu.assertTrue(left_leaf:compare_to(right_leaf) < 0)
end

function TestEpoch.test_detach_unwinds_mixed_attachments_in_reverse_order()
  local log = {}
  local Child = Epoch.extend("Child", {
    init = function(_, s)
      s:on_cleanup(function()
        log[#log + 1] = "child-cleanup"
      end)
    end,
  })
  local function resource(name)
    return {
      dispose = function()
        log[#log + 1] = name
      end,
    }
  end
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(Child.new())
      s:use(resource("resource-a"))
      s:on_cleanup(function()
        log[#log + 1] = "cleanup-mid"
      end)
      s:use(resource("resource-b"))
      s:call(Child.new())
    end,
  })

  local root = attach_root(Root.new())
  root:detach()

  lu.assertEquals(log, {
    "child-cleanup",
    "resource-b",
    "cleanup-mid",
    "resource-a",
    "child-cleanup",
  })
end

function TestEpoch.test_detach_requested_during_init_waits_until_init_finishes()
  local log = {}
  local Root = Epoch.extend("Root", {
    init = function(self, s)
      s:on_cleanup(function()
        log[#log + 1] = "first"
      end)
      self:detach()
      s:on_cleanup(function()
        log[#log + 1] = "second"
      end)
    end,
  })

  local root = attach_root(Root.new())

  lu.assertTrue(root.is_detached)
  lu.assertEquals(log, { "second", "first" })
end

function TestEpoch.test_detach_requested_during_tick_waits_until_tick_finishes()
  local log = {}
  local root = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function()
        log[#log + 1] = "cleanup"
      end)
      return function(tick_s)
        log[#log + 1] = "tick"
        root:detach()
        tick_s:on_cleanup(function()
          log[#log + 1] = "tick-cleanup"
        end)
      end
    end,
  })

  root = attach_root(Root.new())
  root:_tick()

  lu.assertTrue(root.is_detached)
  lu.assertEquals(log, { "tick", "tick-cleanup", "cleanup" })
end

function TestEpoch.test_child_detach_errors_are_logged_and_do_not_stop_parent_teardown()
  local cleaned = false
  local logged = 0
  local previous_logger = Epoch._log_error
  Epoch._log_error = function()
    logged = logged + 1
  end
  local child
  local Child = Epoch.extend("Child", {})
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      child = s:call(Child.new())
      s:on_cleanup(function()
        cleaned = true
      end)
    end,
  })

  local root = attach_root(Root.new())
  child.detach = function()
    error("child-detach-boom")
  end
  root:detach()
  Epoch._log_error = previous_logger

  lu.assertTrue(root.is_detached)
  lu.assertTrue(cleaned)
  lu.assertEquals(logged, 1)
end

function TestEpoch.test_faulted_epoch_stops_future_tick_requests()
  local scheduler = { calls = 0 }
  function scheduler:_schedule()
    self.calls = self.calls + 1
  end
  local ports = nil
  local ticks = 0
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      ports = s:ports()
      return function()
        ticks = ticks + 1
        error("tick-boom")
      end
    end,
  })

  local root = attach_root(Root.new(), nil, scheduler)
  local ok = pcall(function()
    root:_tick()
  end)
  lu.assertFalse(ok)
  lu.assertNotNil(root.fault)
  lu.assertTrue(SpokeException.is(root.fault))
  lu.assertStrContains(root.fault.cause, "tick-boom")
  lu.assertEquals(ticks, 1)

  ports:request_tick()
  root:_tick()
  lu.assertEquals(scheduler.calls, 1)
  lu.assertEquals(ticks, 1)
end

function TestEpoch.test_init_failure_wraps_and_retains_partial_attachments_for_cleanup()
  local cleaned = false
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function()
        cleaned = true
      end)
      error("init-boom")
    end,
  })
  local root = Root.new()

  local ok = pcall(function()
    attach_root(root)
  end)

  lu.assertFalse(ok)
  lu.assertTrue(SpokeException.is(root.fault))
  lu.assertStrContains(root.fault.cause, "init-boom")
  root:detach()
  lu.assertTrue(cleaned)
end

function TestEpoch.test_cleanup_failures_are_logged_and_do_not_stop_unwinding()
  local last_ran = false
  local logged = 0
  local previous_logger = Epoch._log_error
  Epoch._log_error = function()
    logged = logged + 1
  end
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:on_cleanup(function()
        last_ran = true
      end)
      s:on_cleanup(function()
        error("cleanup-boom")
      end)
    end,
  })

  local root = attach_root(Root.new())
  root:detach()
  Epoch._log_error = previous_logger

  lu.assertTrue(last_ran)
  lu.assertEquals(logged, 1)
end

function TestEpoch.test_detached_epoch_cannot_be_attached_again()
  local child = Epoch.extend("Child", {}).new()
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(child)
    end,
  })
  local root = attach_root(Root.new())
  root:detach()

  local second_root = Epoch.extend("SecondRoot", {
    init = function(_, s)
      s:call(child)
    end,
  }).new()
  local ok = pcall(function()
    attach_root(second_root)
  end)

  lu.assertFalse(ok)
end

-- #36: an init that returns a non-function, non-nil value faults at attach
-- time with a clear type message, instead of surfacing as an obscure
-- "attempt to call" error on the first tick.
function TestEpoch.test_init_non_function_return_faults_at_attach()
  local Root = Epoch.extend("Root", {
    init = function()
      return true
    end,
  })
  local root = Root.new()

  local ok = pcall(function()
    attach_root(root)
  end)

  lu.assertFalse(ok)
  lu.assertTrue(SpokeException.is(root.fault))
  lu.assertStrContains(root.fault.cause, "tick function or nil")
  lu.assertStrContains(root.fault.cause, "boolean")
end

-- #41: an epoch attached while already attached to a live parent must fault
-- the tree with a wrapped SpokeException (upstream
-- Call_AlreadyAttachedEpoch_FaultsTheTree).
function TestEpoch.test_attaching_to_two_live_parents_faults_the_tree()
  local child = Epoch.extend("Child", {}).new()
  local first_root = Epoch.extend("FirstRoot", {
    init = function(_, s)
      s:call(child)
    end,
  }).new()
  local root = attach_root(first_root)

  local second_root = Epoch.extend("SecondRoot", {
    init = function(_, s)
      s:call(child)
    end,
  }).new()
  local ok = pcall(function()
    attach_root(second_root)
  end)

  lu.assertFalse(ok)
  lu.assertTrue(SpokeException.is(second_root.fault))
  lu.assertStrContains(tostring(second_root.fault), "already attached")

  root:detach()
  lu.assertTrue(root.is_detached)
end

-- #41: import must walk up multiple levels through export-less nodes
-- (upstream Import_WalksUp_ToAncestor); an import that only searched the
-- immediate parent would fail here.
function TestEpoch.test_import_walks_up_multiple_levels_through_exportless_nodes()
  local imported = nil
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:export("service", "deep")
      s:call(Epoch.extend("Middle", {
        init = function(_, middle_s)
          -- no export on this node
          middle_s:call(Epoch.extend("Leaf", {
            init = function(_, leaf_s)
              imported = leaf_s:import("service")
            end,
          }).new())
        end,
      }).new())
    end,
  })

  attach_root(Root.new())

  lu.assertEquals(imported, "deep")
end

-- #41: a throwing `use` resource dispose is swallowed and subsequent
-- cleanups still run (upstream DisposeException_IsSwallowed_AndSubsequentCleanupsStillRun).
function TestEpoch.test_dispose_error_is_swallowed_and_later_cleanups_still_run()
  local cleaned = false
  local previous_logger = Epoch._log_error
  local logged = 0
  Epoch._log_error = function()
    logged = logged + 1
  end

  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:use({
        dispose = function()
          error("dispose-boom")
        end,
      })
      s:on_cleanup(function()
        cleaned = true
      end)
    end,
  })

  local root = attach_root(Root.new())
  root:detach()
  Epoch._log_error = previous_logger

  lu.assertTrue(cleaned)
  lu.assertEquals(logged, 1)
end
