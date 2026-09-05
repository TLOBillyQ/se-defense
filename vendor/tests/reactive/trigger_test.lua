local lu = require("luaunit")
local Trigger = require("vendor.spoke.reactive.trigger")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local SpokeRuntime = require("vendor.spoke.runtime.spoke_runtime")
local Effect = require("vendor.spoke.reactive.effect")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local State = require("vendor.spoke.reactive.state")

TestTrigger = {}

function TestTrigger.test_new_creates_a_trigger()
  local t = Trigger.new()
  lu.assertNotNil(t)
  lu.assertEquals(type(t.subscribe), "function")
  lu.assertEquals(type(t.unsubscribe), "function")
  lu.assertEquals(type(t.invoke), "function")
end


function TestTrigger.test_fires_all_subscribers()
  local t = Trigger.new()
  local a, b = 0, 0
  t:subscribe(function() a = a + 1 end)
  t:subscribe(function() b = b + 1 end)
  t:invoke()
  t:invoke()
  lu.assertEquals(a, 2)
  lu.assertEquals(b, 2)
end

function TestTrigger.test_unsubscribe_by_handle_stops_further_invocations()
  local t = Trigger.new()
  local count = 0
  local handle = t:subscribe(function() count = count + 1 end)
  t:invoke()
  handle:dispose()
  t:invoke()
  lu.assertEquals(count, 1)
end

function TestTrigger.test_unsubscribe_by_action_removes_matching_subscriptions()
  local t = Trigger.new()
  local count = 0
  local function handler() count = count + 1 end
  t:subscribe(handler)
  t:invoke()
  t:unsubscribe(handler)
  t:invoke()
  lu.assertEquals(count, 1)
end

function TestTrigger.test_duplicate_subscriptions_of_same_fn_are_allowed()
  local t = Trigger.new()
  local count = 0
  local function handler() count = count + 1 end
  t:subscribe(handler)
  t:subscribe(handler)
  t:invoke()
  lu.assertEquals(count, 2)
  t:unsubscribe(handler)
  t:invoke()
  lu.assertEquals(count, 2)
end

function TestTrigger.test_fires_in_subscription_order_with_gaps_from_unsubscribes()
  local t = Trigger.new()
  local order = {}
  local handles = {}
  for i = 1, 200 do
    local n = i
    handles[i] = t:subscribe(function() order[#order + 1] = n end)
  end
  for i = 1, 200, 2 do
    handles[i]:dispose()
  end
  t:invoke()
  local expected = {}
  for i = 2, 200, 2 do
    expected[#expected + 1] = i
  end
  lu.assertEquals(order, expected)
end

function TestTrigger.test_churn_without_invoking_still_delivers_to_live_subscribers()
  local t = Trigger.new()
  local hits = 0
  local resident = t:subscribe(function() hits = hits + 1 end)
  for i = 1, 5000 do
    local h = t:subscribe(function() hits = hits + 100 end)
    h:dispose()
  end
  t:invoke()
  lu.assertEquals(hits, 1)
end

function TestTrigger.test_subscribe_compacts_tombstones_when_needed()
  local t = Trigger.new()
  local hits = 0
  -- Create many tombstones without ever invoking.
  for i = 1, 100 do
    local h = t:subscribe(function() hits = hits + 1 end)
    h:dispose()
  end
  local live = t:subscribe(function() hits = hits + 1 end)
  t:invoke()
  lu.assertEquals(hits, 1)
  live:dispose()
end

function TestTrigger.test_subscriber_added_during_invoke_is_not_notified_this_round()
  local t = Trigger.new()
  local calls = 0
  local late_sub = nil
  t:subscribe(function()
    calls = calls + 1
    if calls == 1 then
      late_sub = t:subscribe(function() calls = calls + 1 end)
    end
  end)
  t:invoke()
  lu.assertEquals(calls, 1)
  t:invoke()
  lu.assertEquals(calls, 3)
  if late_sub then late_sub:dispose() end
end

function TestTrigger.test_unsubscribed_during_invoke_still_fires_this_round()
  local t = Trigger.new()
  local late_fired = 0
  local second = nil
  local first = t:subscribe(function()
    if second then second:dispose() end
  end)
  second = t:subscribe(function() late_fired = late_fired + 1 end)
  t:invoke()
  lu.assertEquals(late_fired, 1)
  t:invoke()
  lu.assertEquals(late_fired, 1)
  first:dispose()
end

function TestTrigger.test_unsubscribed_during_earlier_event_does_not_fire_on_queued_event()
  local t = Trigger.new()
  local seen = {}
  local victim = nil
  local calls = 0
  local driver = t:subscribe(function(v)
    calls = calls + 1
    if calls == 1 then
      t:invoke(99)
      victim:dispose()
    end
  end)
  victim = t:subscribe(function(v) seen[#seen + 1] = v end)
  t:invoke(1)
  lu.assertEquals(seen, { 1 })
  driver:dispose()
end

function TestTrigger.test_mass_unsubscribe_then_subscribe_during_dispatch_delivers_to_dispatch_start_set()
  local t = Trigger.new()
  local handles = {}
  local survivors_fired = 0
  local added_fired = 0
  local first = t:subscribe(function()
    for i = 100, #handles do
      handles[i]:dispose()
    end
    handles[#handles + 1] = t:subscribe(function() added_fired = added_fired + 1 end)
  end)
  for i = 1, 1000 do
    handles[i] = t:subscribe(function() survivors_fired = survivors_fired + 1 end)
  end
  t:invoke()
  lu.assertEquals(survivors_fired, 1000)
  lu.assertEquals(added_fired, 0)
  first:dispose()
  for _, h in ipairs(handles) do h:dispose() end
end

function TestTrigger.test_payload_subscriber_receives_payload()
  local t = Trigger.new()
  local seen = nil
  t:subscribe(function(v) seen = v end)
  t:invoke(42)
  lu.assertEquals(seen, 42)
end

function TestTrigger.test_no_payload_subscriber_is_notified_on_payload_invoke()
  local t = Trigger.new()
  local ran = false
  t:subscribe(function() ran = true end)
  t:invoke(7)
  lu.assertTrue(ran)
end

function TestTrigger.test_reentrant_invoke_is_queued_fifo()
  local t = Trigger.new()
  local seen = {}
  local calls = 0
  t:subscribe(function(v)
    seen[#seen + 1] = v
    calls = calls + 1
    if calls == 1 then
      t:invoke(99)
    end
  end)
  t:invoke(1)
  lu.assertEquals(seen, { 1, 99 })
end

function TestTrigger.test_subscriber_error_is_swallowed_and_later_subscribers_still_fire()
  local t = Trigger.new()
  local second = false
  local logged = 0
  local previous_log = SpokeError.log
  SpokeError.log = function(message, cause)
    logged = logged + 1
  end
  t:subscribe(function() error("boom") end)
  t:subscribe(function() second = true end)
  t:invoke()
  SpokeError.log = previous_log
  lu.assertTrue(second)
  lu.assertEquals(logged, 1)
end

function TestTrigger.test_invoke_wraps_notification_in_spoke_runtime_batch()
  local t = Trigger.new()
  local observed = {}
  t:subscribe(function()
    observed[#observed + 1] = SpokeRuntime._hold_count
  end)
  t:invoke()
  -- Subscriber ran while the batch hold was still active (>=1); after the
  -- outer batch returns the hold is released (verified by no error below).
  lu.assertEquals(#observed, 1)
  lu.assertTrue(observed[1] >= 1)
end

-- #38: batched notifications — a trigger subscriber writing two States must
-- be observable by a dependent effect only as the final combined value,
-- never as an intermediate (partial) state.
function TestTrigger.test_batched_mutations_observe_only_final_combination()
  local a = State.new(0)
  local b = State.new(0)
  local t = Trigger.new()
  local observed = {}

  t:subscribe(function()
    a:set(10)
    b:set(30)
  end)

  local tree = SpokeTree.spawn(Effect.new("watcher", function(s)
    observed[#observed + 1] = { s:d(a), s:d(b) }
  end))

  lu.assertEquals(observed, { { 0, 0 } })

  t:invoke()

  lu.assertEquals(observed, { { 0, 0 }, { 10, 30 } },
    "dependent effect observes only the final combined value")

  tree:dispose()
end

-- #38: batched notifications — multiple writes to the same State inside one
-- batch merge into a single observation of the final value.
function TestTrigger.test_same_state_multi_write_merges_to_single_observation()
  local a = State.new(0)
  local t = Trigger.new()
  local observed = {}

  t:subscribe(function()
    a:set(1)
    a:set(2)
    a:set(3)
  end)

  local tree = SpokeTree.spawn(Effect.new("watcher", function(s)
    observed[#observed + 1] = s:d(a)
  end))

  t:invoke()

  lu.assertEquals(observed, { 0, 3 },
    "same-State writes merge into one observation of the final value")

  tree:dispose()
end
