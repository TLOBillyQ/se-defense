local lu = require("luaunit")
local Effect = require("vendor.spoke.reactive.effect")
local EffectBuilder = require("vendor.spoke.reactive.effect_builder")
local SpokeError = require("vendor.spoke.runtime.spoke_error")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local State = require("vendor.spoke.reactive.state")
local Trigger = require("vendor.spoke.reactive.trigger")

TestEffect = {}

function TestEffect.test_runs_on_mount()
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("test", function()
    runs = runs + 1
  end))

  lu.assertEquals(runs, 1)
  tree:dispose()
end

function TestEffect.test_reruns_when_dynamic_dependency_changes()
  local state = State.new(0)
  local runs = 0
  local last_seen = -1

  local tree = SpokeTree.spawn(Effect.new("test", function(s)
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

function TestEffect.test_cleanup_runs_before_rerun()
  local state = State.new(0)
  local log = {}

  local tree = SpokeTree.spawn(Effect.new("test", function(s)
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

function TestEffect.test_static_trigger_reruns_on_fire()
  local trigger = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("t", function()
    runs = runs + 1
  end, trigger))

  lu.assertEquals(runs, 1)

  trigger:invoke()
  lu.assertEquals(runs, 2)

  trigger:invoke()
  lu.assertEquals(runs, 3)

  tree:dispose()
end

function TestEffect.test_dynamic_dependencies_dropped_trigger_no_longer_reruns()
  local gate = State.new(true)
  local extra = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("dyn", function(s)
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

function TestEffect.test_rerun_detaches_prior_children()
  local state = State.new(0)
  local child_cleanups = 0

  local tree = SpokeTree.spawn(Effect.new("parent", function(s)
    local _ = s:d(state)
    s:effect(function(s2)
      s2:on_cleanup(function()
        child_cleanups = child_cleanups + 1
      end)
    end)
  end))

  lu.assertEquals(child_cleanups, 0)

  state:set(1)
  lu.assertEquals(child_cleanups, 1)

  state:set(2)
  lu.assertEquals(child_cleanups, 2)

  tree:dispose()
end

function TestEffect.test_nested_effects_run_in_imperative_order()
  local state = State.new(0)
  local log = {}

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    s:effect(function(s2)
      log[#log + 1] = "O1:" .. s2:d(state)
      s2:on_cleanup(function()
        log[#log + 1] = "O1clean"
      end)
      s2:effect(function(s3)
        log[#log + 1] = "I1:" .. s3:d(state)
        s3:on_cleanup(function()
          log[#log + 1] = "I1clean"
        end)
      end)
    end)
    s:effect(function(s2)
      log[#log + 1] = "O2:" .. s2:d(state)
      s2:on_cleanup(function()
        log[#log + 1] = "O2clean"
      end)
      s2:effect(function(s3)
        log[#log + 1] = "I2:" .. s3:d(state)
        s3:on_cleanup(function()
          log[#log + 1] = "I2clean"
        end)
      end)
    end)
  end))

  lu.assertEquals(log, { "O1:0", "I1:0", "O2:0", "I2:0" })

  log = {}
  state:set(1)
  lu.assertEquals(log,
    { "I1clean", "O1clean", "O1:1", "I1:1", "I2clean", "O2clean", "O2:1", "I2:1" })

  tree:dispose()
end

function TestEffect.test_deferred_execution_child_runs_after_attaching_block()
  local log = {}

  local tree = SpokeTree.spawn(Effect.new("outer", function(s)
    log[#log + 1] = "outer:start"
    s:effect(function()
      log[#log + 1] = "inner"
    end)
    log[#log + 1] = "outer:end"
  end))

  lu.assertEquals(log, { "outer:start", "outer:end", "inner" })
  tree:dispose()
end

function TestEffect.test_signal_effect_mirrors_returned_signal()
  local source = State.new(10)
  local observed = {}
  local derived

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    derived = s:effect(function()
      return source
    end)
    s:effect(function(s2)
      observed[#observed + 1] = s2:d(derived)
    end)
  end))

  lu.assertEquals(observed, { 10 })
  lu.assertEquals(derived:now(), 10)

  source:set(20)
  lu.assertEquals(observed, { 10, 20 })
  lu.assertEquals(derived:now(), 20)

  tree:dispose()
end

function TestEffect.test_signal_effect_can_attach_nested_children_before_returning_signal()
  local input = State.new(1)
  local observed = {}
  local derived

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    derived = s:effect(function(s2)
      local doubled = State.new(s2:d(input) * 2)
      s2:effect(function(s3)
        local v = s3:d(input)
        doubled:set(v * 2)
      end)
      local plus_one = State.new(doubled:now() + 1)
      s2:effect(function(s3)
        local v = s3:d(doubled)
        plus_one:set(v + 1)
      end)
      return plus_one
    end)
    s:effect(function(s2)
      observed[#observed + 1] = s2:d(derived)
    end)
  end))

  lu.assertEquals(observed, { 3 }) -- 1 * 2 + 1

  input:set(5)
  lu.assertEquals(observed, { 3, 11 }) -- 5 * 2 + 1

  tree:dispose()
end

function TestEffect.test_signal_effect_resets_to_nil_when_rerun_returns_no_signal()
  local gate = State.new(true)
  local source = State.new(7)
  local observed = {}
  local derived

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    derived = s:effect(function(s2)
      if s2:d(gate) then
        return source
      end
    end)
    s:effect(function(s2)
      observed[#observed + 1] = s2:d(derived)
    end)
  end))

  lu.assertEquals(observed, { 7 })
  lu.assertEquals(derived:now(), 7)

  gate:set(false)
  lu.assertEquals(observed, { 7, nil })
  lu.assertNil(derived:now())

  source:set(99)
  lu.assertEquals(observed, { 7, nil })

  tree:dispose()
end

function TestEffect.test_signal_effect_cleans_up_old_returned_signal_subscription_on_rerun()
  local selector = State.new(true)
  local a = State.new(1)
  local b = State.new(100)
  local observed = {}
  local derived

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    derived = s:effect(function(s2)
      return s2:d(selector) and a or b
    end)
    s:effect(function(s2)
      observed[#observed + 1] = s2:d(derived)
    end)
  end))

  lu.assertEquals(observed, { 1 })

  selector:set(false)
  lu.assertEquals(observed, { 1, 100 })

  a:set(2)
  lu.assertEquals(observed, { 1, 100 })

  b:set(200)
  lu.assertEquals(observed, { 1, 100, 200 })

  tree:dispose()
end

function TestEffect.test_rescheduled_by_later_sibling_reruns_before_other_pending()
  local log = {}
  local x = State.new(0)
  local triggered = false

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    s:effect(function(s2)
      log[#log + 1] = "E1:" .. s2:d(x)
    end)
    s:effect(function(s2)
      log[#log + 1] = "E2"
      if not triggered then
        triggered = true
        x:set(1)
      end
    end)
    s:effect(function(s2)
      log[#log + 1] = "E3:" .. s2:d(x)
    end)
  end))

  lu.assertEquals(log, { "E1:0", "E2", "E1:1", "E3:1" })
  tree:dispose()
end

function TestEffect.test_self_reschedules_when_it_writes_a_state_it_reads()
  local x = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("inc", function(s)
    runs = runs + 1
    local v = s:d(x)
    if v < 5 then
      x:set(v + 1)
    end
  end))

  lu.assertEquals(x:now(), 5)
  lu.assertEquals(runs, 6)
  tree:dispose()
end

function TestEffect.test_captured_builder_outside_mutation_window_throws()
  local captured

  local tree = SpokeTree.spawn(Effect.new("e", function(s)
    captured = s
  end))

  lu.assertError(function()
    captured:on_cleanup(function() end)
  end)

  tree:dispose()
end

function TestEffect.test_stale_dependency_fired_mid_rerun_is_suppressed()
  local a = State.new(0)
  local b = State.new(-1)
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("stale", function(s)
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

function TestEffect.test_reads_same_signal_twice_reruns_once()
  local a = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("twice", function(s)
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

function TestEffect.test_dependency_read_order_flips_both_stay_live()
  local flip = State.new(false)
  local a = State.new(0)
  local b = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Effect.new("order", function(s)
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

function TestEffect.test_signal_effect_block_returns_null_exposes_default()
  local observed = -1

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    local derived = s:effect(function()
      return nil
    end)
    s:effect(function(s2)
      observed = s2:d(derived)
    end)
  end))

  lu.assertNil(observed)
  tree:dispose()
end

function TestEffect.test_signal_effect_block_returns_null_after_value_resets_to_default()
  local has_value = State.new(true)
  local source = State.new(7)
  local observed = -1

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    local derived = s:effect(function(s2)
      if s2:d(has_value) then
        return source
      end
    end)
    s:effect(function(s2)
      observed = s2:d(derived)
    end)
  end))

  lu.assertEquals(observed, 7)

  has_value:set(false)
  lu.assertNil(observed)

  tree:dispose()
end

-- Regression for #25: is_signal must stay module-local, not leak onto _G.
-- The eggy host shares one global env across scripts; a leaked helper could
-- be overwritten by (or mislead autocomplete for) unrelated scripts.
function TestEffect.test_is_signal_helper_not_leaked_to_global()
  lu.assertNil(rawget(_G, "is_signal"))
end

-- #28: signal-returning effects still mirror the signal's current value
-- through now() (regression for the deferred-initializer skip on the
-- non-signal path).
function TestEffect.test_signal_effect_now_tracks_signal_value()
  local source = State.new(5)
  local effect

  local tree = SpokeTree.spawn(Effect.new("root", function(s)
    effect = s:effect(function()
      return source
    end)
  end))

  lu.assertEquals(effect:now(), 5)

  source:set(9)
  lu.assertEquals(effect:now(), 9)

  tree:dispose()
end

-- #42: upstream Effect tolerates a null block as a no-op; a nil-block
-- effect must construct and run without error.
function TestEffect.test_nil_block_effect_is_a_noop()
  local tree = SpokeTree.spawn(Effect.new("nil-block", nil))
  lu.assertNil(tree.fault)
  tree:dispose()
end
