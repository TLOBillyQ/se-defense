local lu = require("luaunit")
local Computation = require("common.spoke.reactive.computation")
local EffectBuilder = require("common.spoke.reactive.effect_builder")
local Memo = require("common.spoke.reactive.memo")
local SpokeTree = require("common.spoke.runtime.spoke_tree")
local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")

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

TestMemo = {}

function TestMemo.test_now_returns_computed_value()
  local src = State.new(5)
  local doubled

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    doubled = s:memo(function(m)
      return m:d(src) * 2
    end)
  end))

  lu.assertEquals(doubled:now(), 10)

  src:set(7)
  lu.assertEquals(doubled:now(), 14)

  tree:dispose()
end

function TestMemo.test_recomputes_on_dependency_change()
  local a = State.new(2)
  local b = State.new(3)
  local sum

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    sum = s:memo(function(m)
      return m:d(a) + m:d(b)
    end)
  end))

  lu.assertEquals(sum:now(), 5)

  a:set(10)
  lu.assertEquals(sum:now(), 13)

  b:set(20)
  lu.assertEquals(sum:now(), 30)

  tree:dispose()
end

function TestMemo.test_same_computed_value_does_not_propagate()
  local input = State.new(1)
  local capped
  local dependent_runs = 0

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    capped = s:memo(function(m)
      local v = m:d(input)
      return v < 10 and v or 10
    end)
    s:call(TestEffect.new("inner", function(e)
      dependent_runs = dependent_runs + 1
      local _ = e:d(capped)
    end))
  end))

  lu.assertEquals(dependent_runs, 1)

  input:set(20)
  lu.assertEquals(capped:now(), 10)
  lu.assertEquals(dependent_runs, 2)

  input:set(30)
  lu.assertEquals(capped:now(), 10)
  lu.assertEquals(dependent_runs, 2)

  tree:dispose()
end

function TestMemo.test_cleanup_runs_before_rerun()
  local src = State.new(0)
  local log = {}

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    s:memo(function(m)
      local v = m:d(src)
      log[#log + 1] = "compute:" .. v
      m:on_cleanup(function()
        log[#log + 1] = "cleanup:" .. v
      end)
      return v
    end)
  end))

  src:set(1)

  lu.assertEquals(log, { "compute:0", "cleanup:0", "compute:1" })
  tree:dispose()
end

function TestMemo.test_recompute_propagates_to_dependent_effect()
  local log = {}
  local src = State.new(0)

  local tree = SpokeTree.spawn(TestEffect.new("outer", function(s)
    log[#log + 1] = "outer"
    local memo = s:memo(function(m)
      local v = m:d(src)
      log[#log + 1] = "memo:" .. v
      return v * 2
    end)
    s:call(TestEffect.new("inner", function(e)
      log[#log + 1] = "inner:" .. e:d(memo)
    end))
  end))

  lu.assertEquals(log, { "outer", "memo:0", "inner:0" })

  log = {}
  src:set(3)

  lu.assertEquals(log, { "memo:3", "inner:6" })
  tree:dispose()
end

function TestMemo.test_named_memo()
  local src = State.new(1)
  local memo

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    memo = s:memo("doubler", function(m)
      return m:d(src) * 2
    end)
  end))

  lu.assertEquals(memo.name, "doubler")
  lu.assertEquals(memo:now(), 2)
  tree:dispose()
end

function TestMemo.test_static_trigger_reruns_memo()
  local trigger = Trigger.new()
  local runs = 0
  local memo

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    memo = s:memo("count", function(m)
      runs = runs + 1
      return runs
    end, trigger)
  end))

  lu.assertEquals(runs, 1)
  lu.assertEquals(memo:now(), 1)

  trigger:invoke()
  lu.assertEquals(runs, 2)
  lu.assertEquals(memo:now(), 2)

  tree:dispose()
end

function TestMemo.test_static_triggers_as_array()
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0
  local memo

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    memo = s:memo("count", function(m)
      runs = runs + 1
      return runs
    end, { t1, t2 })
  end))

  lu.assertEquals(runs, 1)

  t1:invoke()
  lu.assertEquals(runs, 2)

  t2:invoke()
  lu.assertEquals(runs, 3)

  tree:dispose()
end

function TestMemo.test_subscribe_notifies_on_value_change()
  local src = State.new(0)
  local memo
  local values = {}

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    memo = s:memo(function(m)
      return m:d(src)
    end)
  end))

  local handle = memo:subscribe(function(v)
    values[#values + 1] = v
  end)

  src:set(1)
  src:set(2)

  lu.assertEquals(values, { 1, 2 })

  handle:dispose()
  src:set(3)
  lu.assertEquals(values, { 1, 2 })

  tree:dispose()
end

function TestMemo.test_unsubscribe_by_function()
  local src = State.new(0)
  local memo
  local values = {}

  local tree = SpokeTree.spawn(TestEffect.new("root", function(s)
    memo = s:memo(function(m)
      return m:d(src)
    end)
  end))

  local function on_change(v)
    values[#values + 1] = v
  end
  memo:subscribe(on_change)

  src:set(1)
  memo:unsubscribe(on_change)
  src:set(2)

  lu.assertEquals(values, { 1 })
  tree:dispose()
end

function TestMemo.test_direct_constructor_with_name_and_triggers()
  local trigger = Trigger.new()
  local src = State.new(1)
  local memo = Memo.new("direct", function(m)
    return m:d(src) * 3
  end, trigger)

  local tree = SpokeTree.spawn(memo)

  lu.assertEquals(memo.name, "direct")
  lu.assertEquals(memo:now(), 3)

  trigger:invoke()
  lu.assertEquals(memo:now(), 3)

  src:set(2)
  lu.assertEquals(memo:now(), 6)

  tree:dispose()
end

function TestMemo.test_direct_constructor_with_multiple_static_triggers()
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0
  local memo = Memo.new(function(m)
    runs = runs + 1
    return runs
  end, t1, t2)

  local tree = SpokeTree.spawn(memo)

  lu.assertEquals(runs, 1)

  t1:invoke()
  lu.assertEquals(runs, 2)

  t2:invoke()
  lu.assertEquals(runs, 3)

  tree:dispose()
end

-- #42: upstream Memo tolerates a null selector as a no-op; a nil-selector
-- memo must construct, run, and expose nil without error.
function TestMemo.test_nil_selector_memo_is_a_noop()
  local tree = SpokeTree.spawn(Memo.new("nil-selector", nil))
  lu.assertNil(tree.fault)
  tree:dispose()
end
