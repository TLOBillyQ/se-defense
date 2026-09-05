local lu = require("luaunit")
local Computation = require("vendor.spoke.reactive.computation")
local EffectBuilder = require("vendor.spoke.reactive.effect_builder")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local State = require("vendor.spoke.reactive.state")
local Trigger = require("vendor.spoke.reactive.trigger")

local DependencyTracker = Computation.DependencyTracker

-- Minimal Computation subclass standing in for Effect (ported later), the same
-- way upstream tests exercise the base through Effect.
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

TestComputation = {}

function TestComputation.test_runs_once_on_mount()
  local runs = 0
  local tree = SpokeTree.spawn(TestEffect.new("test", function()
    runs = runs + 1
  end))

  lu.assertEquals(runs, 1)
  tree:dispose()
end

function TestComputation.test_reruns_when_dynamic_dependency_changes()
  local state = State.new(0)
  local runs = 0
  local last_seen = -1

  local tree = SpokeTree.spawn(TestEffect.new("test", function(s)
    runs = runs + 1
    last_seen = s:d(state)
  end))
  lu.assertEquals(runs, 1)
  lu.assertEquals(last_seen, 0)

  state:set(7)
  lu.assertEquals(runs, 2)
  lu.assertEquals(last_seen, 7)
  tree:dispose()
end

function TestComputation.test_cleanup_runs_before_rerun()
  local state = State.new(0)
  local log = {}

  local tree = SpokeTree.spawn(TestEffect.new("test", function(s)
    local v = s:d(state)
    log[#log + 1] = "mount:" .. v
    s:on_cleanup(function()
      log[#log + 1] = "cleanup:" .. v
    end)
  end))

  state:set(1)

  lu.assertEquals(log, { "mount:0", "cleanup:0", "mount:1" })
  tree:dispose()
end

function TestComputation.test_static_trigger_reruns_on_fire()
  local trigger = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("t", function()
    runs = runs + 1
  end, trigger))
  lu.assertEquals(runs, 1)

  trigger:invoke()
  lu.assertEquals(runs, 2)

  trigger:invoke()
  lu.assertEquals(runs, 3)
  tree:dispose()
end

function TestComputation.test_multiple_static_triggers_as_array()
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("t", function()
    runs = runs + 1
  end, { t1, t2 }))

  t1:invoke()
  t2:invoke()

  lu.assertEquals(runs, 3)
  tree:dispose()
end

function TestComputation.test_dropped_dynamic_dependency_no_longer_reruns()
  local gate = State.new(true)
  local extra = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("dyn", function(s)
    runs = runs + 1
    if s:d(gate) then
      local _ = s:d(extra)
    end
  end))
  lu.assertEquals(runs, 1)

  extra:set(1)
  lu.assertEquals(runs, 2)

  gate:set(false)
  lu.assertEquals(runs, 3)

  extra:set(2)
  lu.assertEquals(runs, 3)

  gate:set(true)
  lu.assertEquals(runs, 4)
  tree:dispose()
end

function TestComputation.test_stale_dependency_fired_mid_rerun_is_suppressed()
  -- The block writes b before reading it, so at the instant of the write the
  -- computation is not yet subscribed to b this run; the write cannot schedule
  -- a redundant rerun.
  local a = State.new(0)
  local b = State.new(-1)
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("stale", function(s)
    local av = s:d(a)
    b:set(av)
    local _ = s:d(b)
    runs = runs + 1
  end))
  lu.assertEquals(runs, 1)

  a:set(5)
  lu.assertEquals(runs, 2)
  tree:dispose()
end

function TestComputation.test_reading_same_signal_twice_reruns_once_per_change()
  local a = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("twice", function(s)
    local _ = s:d(a)
    local _ = s:d(a)
    runs = runs + 1
  end))
  lu.assertEquals(runs, 1)

  a:set(1)
  lu.assertEquals(runs, 2)

  a:set(2)
  lu.assertEquals(runs, 3)
  tree:dispose()
end

function TestComputation.test_read_order_flip_keeps_both_dependencies_live()
  local flip = State.new(false)
  local a = State.new(0)
  local b = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("order", function(s)
    runs = runs + 1
    if s:d(flip) then
      local _ = s:d(a)
      local _ = s:d(b)
    else
      local _ = s:d(b)
      local _ = s:d(a)
    end
  end))
  lu.assertEquals(runs, 1)

  flip:set(true)
  lu.assertEquals(runs, 2)

  a:set(1)
  lu.assertEquals(runs, 3)

  b:set(1)
  lu.assertEquals(runs, 4)
  tree:dispose()
end

function TestComputation.test_block_error_faults_epoch_and_dynamic_tracking_still_ends()
  local a = State.new(0)
  local b = State.new(0)
  local should_raise = false
  local comp = TestEffect.new("raising", function(s)
    local _ = s:d(a)
    if should_raise then
      error("boom")
    end
    local _ = s:d(b)
  end)

  local previous_log = SpokeError.log
  SpokeError.log = function() end
  local tree = SpokeTree.spawn(comp)
  should_raise = true
  a:set(1)
  SpokeError.log = previous_log

  lu.assertNotNil(comp.fault)
  -- The finally-equivalent ran during the faulted tick: the unread slot for b
  -- was dropped and unsubscribed even though the block raised.
  lu.assertEquals(#comp._tracker._dynamic, 1)
  lu.assertEquals(comp._tracker._dep_index, 1)
  tree:dispose()
end

function TestComputation.test_detach_disposes_all_subscriptions()
  local trigger = Trigger.new()
  local state = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("t", function(s)
    runs = runs + 1
    local _ = s:d(state)
  end, trigger))
  lu.assertEquals(runs, 1)

  tree:dispose()

  trigger:invoke()
  state:set(1)
  lu.assertEquals(runs, 1)
end

TestDependencyTracker = {}

function TestDependencyTracker.test_static_trigger_schedules_until_disposed()
  local trigger = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:add_static(trigger)
  trigger:invoke()
  lu.assertEquals(scheduled, 1)

  tracker:dispose()
  trigger:invoke()
  lu.assertEquals(scheduled, 1)
end

function TestDependencyTracker.test_first_read_at_a_slot_subscribes()
  local a = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:end_dynamic()

  a:invoke()
  lu.assertEquals(scheduled, 1)
end

function TestDependencyTracker.test_different_signal_at_slot_swaps_subscription()
  local a = Trigger.new()
  local b = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:end_dynamic()

  tracker:begin_dynamic()
  tracker:add_dynamic(b)
  tracker:end_dynamic()

  a:invoke()
  lu.assertEquals(scheduled, 0)

  b:invoke()
  lu.assertEquals(scheduled, 1)
end

function TestDependencyTracker.test_slots_beyond_current_run_are_unsubscribed()
  local a = Trigger.new()
  local b = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:add_dynamic(b)
  tracker:end_dynamic()

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:end_dynamic()

  b:invoke()
  lu.assertEquals(scheduled, 0)

  a:invoke()
  lu.assertEquals(scheduled, 1)
end

function TestDependencyTracker.test_stale_slot_callback_is_suppressed()
  local a = Trigger.new()
  local b = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:add_dynamic(b)
  tracker:end_dynamic()

  -- Next run: b fires after its slot was taken by a previous run, but before
  -- the slot is re-established this run. The callback is stale and must not
  -- schedule.
  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  b:invoke()
  lu.assertEquals(scheduled, 0)

  tracker:add_dynamic(b)
  tracker:end_dynamic()
  b:invoke()
  lu.assertEquals(scheduled, 1)
end

function TestDependencyTracker.test_duplicate_reads_take_two_slots_and_both_fire()
  -- Two slots, two callbacks: the coalescing into one tick happens at the
  -- epoch level, not in the tracker.
  local a = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:add_dynamic(a)
  tracker:end_dynamic()

  a:invoke()
  lu.assertEquals(scheduled, 2)
end

function TestDependencyTracker.test_dispose_drops_dynamic_subscriptions()
  local a = Trigger.new()
  local scheduled = 0
  local tracker = DependencyTracker.new(function()
    scheduled = scheduled + 1
  end)

  tracker:begin_dynamic()
  tracker:add_dynamic(a)
  tracker:end_dynamic()

  tracker:dispose()
  a:invoke()
  lu.assertEquals(scheduled, 0)
end
