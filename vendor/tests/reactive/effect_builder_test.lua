local lu = require("luaunit")
local Computation = require("vendor.spoke.reactive.computation")
local EffectBuilder = require("vendor.spoke.reactive.effect_builder")
local LambdaEpoch = require("vendor.spoke.runtime.lambda_epoch")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local State = require("vendor.spoke.reactive.state")
local Trigger = require("vendor.spoke.reactive.trigger")

local MemoBuilder = EffectBuilder.MemoBuilder

-- Minimal Computation subclass driving an EffectBuilder, standing in for
-- Effect (ported later).
local TestEffect = Computation.extend("TestEffect", {
  constructor = function(self, block, triggers)
    Computation.constructor(self, triggers)
    self._block = block
  end,

  on_run = function(self, s)
    self._block(EffectBuilder.new(function(signal)
      self:_add_dynamic_trigger(signal)
    end, s))
  end,
})

-- Minimal Computation subclass driving a MemoBuilder, standing in for Memo.
local TestSelector = Computation.extend("TestSelector", {
  constructor = function(self, selector, triggers)
    Computation.constructor(self, triggers)
    self._selector = selector
  end,

  on_run = function(self, s)
    self.result = self._selector(MemoBuilder.new(function(signal)
      self:_add_dynamic_trigger(signal)
    end, s))
  end,
})

TestEffectBuilder = {}

function TestEffectBuilder.test_d_returns_current_value_and_tracks()
  local state = State.new(42)
  local seen = {}

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    seen[#seen + 1] = s:d(state)
  end))

  state:set(43)

  lu.assertEquals(seen, { 42, 43 })
  tree:dispose()
end

function TestEffectBuilder.test_subscribe_owns_handle_for_the_current_run()
  local state = State.new(0)
  local trigger = Trigger.new()
  local calls = 0

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    local _ = s:d(state)
    s:subscribe(trigger, function()
      calls = calls + 1
    end)
  end))

  trigger:invoke()
  lu.assertEquals(calls, 1)

  -- Rerun: the previous run's subscription is disposed, a new one is owned.
  state:set(1)
  trigger:invoke()
  lu.assertEquals(calls, 2)
  tree:dispose()
end

function TestEffectBuilder.test_subscribe_nil_trigger_is_a_noop_handle()
  local calls = 0
  local handle

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    handle = s:subscribe(nil, function()
      calls = calls + 1
    end)
  end))

  lu.assertEquals(calls, 0)
  handle:dispose() -- safe to dispose
  tree:dispose()
end

function TestEffectBuilder.test_use_disposes_owned_resource_on_rerun()
  local state = State.new(0)
  local disposed = 0

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    local _ = s:d(state)
    s:use({
      dispose = function()
        disposed = disposed + 1
      end,
    })
  end))
  lu.assertEquals(disposed, 0)

  state:set(1)
  lu.assertEquals(disposed, 1)
  tree:dispose()
end

function TestEffectBuilder.test_call_attaches_child_rebuilt_with_rerun()
  local state = State.new(0)
  local child_ticks = 0

  local tree = SpokeTree.spawn(TestEffect.new("parent", function(s)
    local _ = s:d(state)
    s:call(LambdaEpoch.new(function()
      return function()
        child_ticks = child_ticks + 1
      end
    end))
  end))

  state:set(1)

  -- Each run attaches a fresh child that auto-arms and ticks once.
  lu.assertEquals(child_ticks, 2)
  tree:dispose()
end

function TestEffectBuilder.test_export_and_import_roundtrip_in_block()
  local imported

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    s:export("answer", 42)
    imported = s:import("answer")
  end))

  lu.assertEquals(imported, 42)
  tree:dispose()
end

function TestEffectBuilder.test_try_import_missing_returns_false_nil()
  local found, value = "unset", "unset"

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    found, value = s:try_import("missing")
  end))

  lu.assertFalse(found)
  lu.assertNil(value)
  tree:dispose()
end

function TestEffectBuilder.test_import_missing_raises_inside_block()
  local previous_log = SpokeError.log
  SpokeError.log = function() end
  local comp = TestEffect.new("e", function(s)
    local _ = s:import("missing")
  end)
  local tree = SpokeTree.spawn(comp)
  SpokeError.log = previous_log

  lu.assertNotNil(comp.fault)
  tree:dispose()
end

function TestEffectBuilder.test_log_forwards_to_default_logger()
  local previous_log = SpokeError.log
  local logged = {}
  SpokeError.log = function(message)
    logged[#logged + 1] = message
  end

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    s:log("hello from effect")
  end))
  SpokeError.log = previous_log

  -- #35: the log carries the tree trace and names the structural node.
  lu.assertEquals(#logged, 1)
  lu.assertStrContains(logged[1], "hello from effect")
  lu.assertStrContains(logged[1], "Log: hello from effect")
  lu.assertStrContains(logged[1], "SpokeTree")
  lu.assertStrContains(logged[1], "<------------ Spoke Frame Trace ------------>")
  lu.assertStrContains(logged[1], "<------------ Spoke Tree Trace ------------>")
  lu.assertStrContains(logged[1], "0: Bootstrap")
  tree:dispose()
end

function TestEffectBuilder.test_log_forwards_to_service_logger()
  local captured = {}
  local logger = {
    log = function(_, text)
      captured[#captured + 1] = text
    end,
  }

  local tree = SpokeTree.spawn("Logged", TestEffect.new("e", function(s)
    s:log("svc log")
  end), { logger = logger })

  lu.assertEquals(#captured, 1)
  lu.assertStrContains(captured[1], "<------------ Spoke Frame Trace ------------>")
  lu.assertStrContains(captured[1], "<------------ Spoke Tree Trace ------------>")
  lu.assertStrContains(captured[1], "Log: svc log")
  tree:dispose()
end

function TestEffectBuilder.test_log_swallows_errors_from_both_logger_paths()
  local previous_log = SpokeError.log

  local service_ok, service_tree = pcall(SpokeTree.spawn, "Logged",
    TestEffect.new("e", function(s)
      s:log("svc boom")
    end), {
      logger = {
        log = function()
          error("service-logger-boom")
        end,
      },
    })
  SpokeError.log = previous_log
  lu.assertTrue(service_ok)
  lu.assertNotNil(service_tree)
  lu.assertNil(service_tree.fault)
  service_tree:dispose()

  SpokeError.log = function()
    error("default-logger-boom")
  end
  local default_ok, default_tree = pcall(SpokeTree.spawn, TestEffect.new("e", function(s)
    s:log("default boom")
  end))
  SpokeError.log = previous_log
  lu.assertTrue(default_ok)
  lu.assertNotNil(default_tree)
  lu.assertNil(default_tree.fault)
  default_tree:dispose()
end

-- #35: s:log mounts a LambdaEpoch child so the log is a visible structural
-- node, and the child is rolled back with its owning tick.
function TestEffectBuilder.test_log_mounts_structural_child_cleaned_up_on_rerun()
  local state = State.new(0)
  local SpokeIntrospect = require("vendor.spoke.runtime.spoke_introspect")
  local captured

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    local _ = s:d(state)
    s:log("tick log")
    captured = SpokeIntrospect.get_children(s._s._owner)
  end))

  lu.assertEquals(#captured, 1)
  lu.assertEquals(captured[1].name, "Log: tick log")

  state:set(1)
  local after_rerun = SpokeIntrospect.get_children(captured[1]._parent)
  lu.assertEquals(#after_rerun, 1, "tick-time log child is rolled back and rebuilt")
  lu.assertEquals(after_rerun[1].name, "Log: tick log")

  tree:dispose()
end

function TestEffectBuilder.test_builder_is_sealed_outside_the_block()
  local captured
  local state = State.new(0)

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    captured = s
  end))

  lu.assertError(function()
    captured:on_cleanup(function() end)
  end)
  lu.assertError(function()
    captured:d(state)
  end)
  lu.assertError(function()
    captured:subscribe(Trigger.new(), function() end)
  end)
  tree:dispose()
end

function TestEffectBuilder.test_dock_returns_dock_callable_after_window()
  local dock

  local tree = SpokeTree.spawn(TestEffect.new("e", function(s)
    dock = s:dock()
  end))

  lu.assertNotNil(dock)
  local child = LambdaEpoch.new(function() end)
  dock:call("k", child)
  lu.assertTrue(child._attached)

  tree:dispose()
  lu.assertTrue(child.is_detached)
end

TestMemoBuilder = {}

function TestMemoBuilder.test_surface_is_d_and_on_cleanup_only()
  lu.assertEquals(type(MemoBuilder.d), "function")
  lu.assertEquals(type(MemoBuilder.on_cleanup), "function")
  lu.assertNil(MemoBuilder.use)
  lu.assertNil(MemoBuilder.call)
  lu.assertNil(MemoBuilder.subscribe)
  lu.assertNil(MemoBuilder.export)
  lu.assertNil(MemoBuilder.import)
  lu.assertNil(MemoBuilder.memo)
  lu.assertNil(MemoBuilder.effect)
  lu.assertNil(MemoBuilder.dock)
end

function TestMemoBuilder.test_d_tracks_and_selector_reruns()
  local state = State.new(2)
  local comp = TestSelector.new(function(s)
    return s:d(state) * 10
  end)
  local tree = SpokeTree.spawn(comp)
  lu.assertEquals(comp.result, 20)

  state:set(3)
  lu.assertEquals(comp.result, 30)
  tree:dispose()
end

function TestMemoBuilder.test_on_cleanup_runs_before_recomputation()
  local state = State.new(0)
  local log = {}

  local comp = TestSelector.new(function(s)
    local v = s:d(state)
    log[#log + 1] = "run:" .. v
    s:on_cleanup(function()
      log[#log + 1] = "cleanup:" .. v
    end)
    return v
  end)
  local tree = SpokeTree.spawn(comp)

  state:set(1)

  lu.assertEquals(log, { "run:0", "cleanup:0", "run:1" })
  tree:dispose()
end

function TestMemoBuilder.test_builder_is_sealed_outside_the_block()
  local captured
  local state = State.new(0)

  local comp = TestSelector.new(function(s)
    captured = s
    return 0
  end)
  local tree = SpokeTree.spawn(comp)

  lu.assertError(function()
    captured:d(state)
  end)
  lu.assertError(function()
    captured:on_cleanup(function() end)
  end)
  tree:dispose()
end
