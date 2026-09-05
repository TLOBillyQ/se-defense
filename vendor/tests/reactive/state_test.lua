local lu = require("luaunit")
local State = require("vendor.spoke.reactive.state")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local SpokeRuntime = require("vendor.spoke.runtime.spoke_runtime")

TestState = {}

function TestState.test_new_no_args_has_nil_initial_value()
  local state = State.new()
  lu.assertNil(state:now())
end

function TestState.test_new_with_initial_value()
  local state = State.new(1)
  lu.assertEquals(state:now(), 1)
end

function TestState.test_new_single_string_is_initial_value_not_name()
  local state = State.new("hello")
  lu.assertEquals(state:now(), "hello")
  lu.assertNil(state.name)
end

function TestState.test_new_named_with_initial_value()
  local state = State.new("counter", 5)
  lu.assertEquals(state.name, "counter")
  lu.assertEquals(state:now(), 5)
end

function TestState.test_new_named_nil_initial_requires_both_args()
  local state = State.new("empty", nil)
  lu.assertEquals(state.name, "empty")
  lu.assertNil(state:now())
end

function TestState.test_new_with_equals_function()
  local state = State.new(0, function(a, b)
    return math.abs(a - b) < 2
  end)
  lu.assertEquals(state:now(), 0)
end

function TestState.test_set_same_value_does_not_notify()
  local state = State.new(1)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set(1)

  lu.assertEquals(calls, 0)
  handle:dispose()
end

function TestState.test_set_different_value_notifies()
  local state = State.new(1)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set(2)
  state:set(2)
  state:set(3)

  lu.assertEquals(calls, 2)
  handle:dispose()
end

function TestState.test_set_same_reference_does_not_notify()
  local inst = {}
  local state = State.new(inst)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set(inst)

  lu.assertEquals(calls, 0)
  handle:dispose()
end

function TestState.test_set_different_reference_notifies()
  local state = State.new({})
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set({})

  lu.assertEquals(calls, 1)
  handle:dispose()
end

function TestState.test_set_nil_to_nil_does_not_notify()
  local state = State.new(nil)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set(nil)

  lu.assertEquals(calls, 0)
  handle:dispose()
end

function TestState.test_update_applies_setter_to_current_value()
  local state = State.new(5)
  local observed = 0
  local handle = state:subscribe(function(v)
    observed = v
  end)

  state:update(function(x)
    return x * 2
  end)

  lu.assertEquals(state:now(), 10)
  lu.assertEquals(observed, 10)
  handle:dispose()
end

function TestState.test_update_nil_setter_is_no_op()
  local state = State.new(5)
  local notified = false
  local handle = state:subscribe(function()
    notified = true
  end)

  state:update(nil)

  lu.assertEquals(state:now(), 5)
  lu.assertFalse(notified)
  handle:dispose()
end

function TestState.test_initial_value_does_not_notify_subscribers()
  local state = State.new(1)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  lu.assertEquals(calls, 0)
  lu.assertEquals(state:now(), 1)
  handle:dispose()
end

function TestState.test_subscribe_notifies_with_new_value_on_change()
  local state = State.new(1)
  local observed = {}
  local handle = state:subscribe(function(v)
    observed[#observed + 1] = v
  end)

  state:set(2)
  state:set(3)

  lu.assertEquals(observed, { 2, 3 })
  handle:dispose()
end

function TestState.test_unsubscribe_by_handle_stops_notifications()
  local state = State.new(1)
  local count = 0
  local handle = state:subscribe(function()
    count = count + 1
  end)

  state:set(2)
  handle:dispose()
  state:set(3)

  lu.assertEquals(count, 1)
end

function TestState.test_unsubscribe_by_action_stops_notifications()
  local state = State.new(1)
  local count = 0
  local function handler()
    count = count + 1
  end
  state:subscribe(handler)

  state:set(2)
  state:unsubscribe(handler)
  state:set(3)

  lu.assertEquals(count, 1)
end

function TestState.test_multiple_subscribers_notified_in_order()
  local state = State.new(0)
  local order = {}
  local ha = state:subscribe(function()
    order[#order + 1] = "a"
  end)
  local hb = state:subscribe(function()
    order[#order + 1] = "b"
  end)

  state:set(1)

  lu.assertEquals(order, { "a", "b" })
  ha:dispose()
  hb:dispose()
end

function TestState.test_custom_equals_suppresses_notifications()
  local state = State.new({ x = 0 }, function(a, b)
    return a.x == b.x
  end)
  local calls = 0
  local handle = state:subscribe(function()
    calls = calls + 1
  end)

  state:set({ x = 0 })
  lu.assertEquals(calls, 0)

  state:set({ x = 1 })
  lu.assertEquals(calls, 1)
  handle:dispose()
end

function TestState.test_subscriber_error_does_not_stop_later_subscribers()
  local state = State.new(0)
  local second_fired = false
  local previous_logger = SpokeError.log
  local logged = 0
  SpokeError.log = function()
    logged = logged + 1
  end

  local h1 = state:subscribe(function()
    error("boom")
  end)
  local h2 = state:subscribe(function()
    second_fired = true
  end)

  state:set(1)

  SpokeError.log = previous_logger
  lu.assertTrue(second_fired)
  lu.assertEquals(logged, 1)
  h1:dispose()
  h2:dispose()
end

function TestState.test_setting_state_from_subscriber_is_queued_and_batches()
  local state = State.new(0)
  local observations = {}
  local handle = state:subscribe(function(v)
    observations[#observations + 1] = v
    if v == 1 then
      state:set(2)
    end
  end)

  state:set(1)

  lu.assertEquals(observations, { 1, 2 })
  handle:dispose()
end

function TestState.test_state_changes_inside_runtime_batch_notify_subscribers_normally()
  local state = State.new(0)
  local observations = {}
  local handle = state:subscribe(function(v)
    observations[#observations + 1] = v
  end)

  SpokeRuntime.batch(function()
    state:set(1)
    state:set(2)
    state:set(3)
  end)

  lu.assertEquals(observations, { 1, 2, 3 })
  handle:dispose()
end

function TestState.test_subscriber_added_during_dispatch_is_not_notified_this_round()
  local state = State.new(0)
  local calls = 0
  local late_handle = nil
  local handle = state:subscribe(function()
    calls = calls + 1
    if calls == 1 then
      late_handle = state:subscribe(function()
        calls = calls + 1
      end)
    end
  end)

  state:set(1)
  lu.assertEquals(calls, 1)

  state:set(2)
  lu.assertEquals(calls, 3)
  handle:dispose()
  if late_handle then
    late_handle:dispose()
  end
end

function TestState.test_subscriber_removed_during_dispatch_still_fires_this_round()
  local state = State.new(0)
  local late_fired = 0
  local second = nil
  local first = state:subscribe(function()
    second:dispose()
  end)
  second = state:subscribe(function()
    late_fired = late_fired + 1
  end)

  state:set(1)
  lu.assertEquals(late_fired, 1)

  state:set(2)
  lu.assertEquals(late_fired, 1)
  first:dispose()
end

function TestState.test_unsubscribe_during_earlier_event_does_not_fire_on_queued_event()
  local state = State.new(0)
  local seen = {}
  local victim = nil
  local calls = 0
  local driver = state:subscribe(function(v)
    calls = calls + 1
    if calls == 1 then
      state:set(99)
      victim:dispose()
    end
  end)
  victim = state:subscribe(function(v)
    seen[#seen + 1] = v
  end)

  state:set(1)

  lu.assertEquals(seen, { 1 })
  driver:dispose()
end

function TestState.test_duplicate_subscriptions_of_same_fn_are_allowed()
  local state = State.new(0)
  local count = 0
  local function handler()
    count = count + 1
  end
  state:subscribe(handler)
  state:subscribe(handler)

  state:set(1)
  lu.assertEquals(count, 2)

  state:unsubscribe(handler)
  state:set(2)
  lu.assertEquals(count, 2)
end
