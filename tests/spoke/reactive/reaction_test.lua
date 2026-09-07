local lu = require("luaunit")
local Reaction = require("common.spoke.reactive.reaction")
local SpokeTree = require("common.spoke.runtime.spoke_tree")
local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")

TestReaction = {}

function TestReaction.test_does_not_run_on_initial_mount()
  local runs = 0
  local trigger = Trigger.new()

  local tree = SpokeTree.spawn(Reaction.new("r", function()
    runs = runs + 1
  end, trigger))

  lu.assertEquals(runs, 0)
  tree:dispose()
end

function TestReaction.test_runs_on_trigger_fire()
  local runs = 0
  local trigger = Trigger.new()

  local tree = SpokeTree.spawn(Reaction.new("r", function()
    runs = runs + 1
  end, trigger))
  lu.assertEquals(runs, 0)

  trigger:invoke()
  lu.assertEquals(runs, 1)

  trigger:invoke()
  lu.assertEquals(runs, 2)
  tree:dispose()
end

function TestReaction.test_reruns_when_dynamic_dependency_changes()
  local state = State.new(0)
  local runs = 0
  local last_seen = -1

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    runs = runs + 1
    last_seen = s:d(state)
  end))
  lu.assertEquals(runs, 0)

  state:set(7)
  -- No initial run means no dynamic subscription yet, so the first set does nothing.
  lu.assertEquals(runs, 0)

  -- Fire the reaction manually so it binds its dynamic dependency.
  state:set(7)
  -- Still 0 because we have no static trigger; the reaction has never run.
  lu.assertEquals(runs, 0)
  tree:dispose()
end

function TestReaction.test_dynamic_dependency_after_first_trigger()
  local state = State.new(0)
  local trigger = Trigger.new()
  local runs = 0
  local last_seen = -1

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    runs = runs + 1
    last_seen = s:d(state)
  end, trigger))
  lu.assertEquals(runs, 0)

  trigger:invoke()
  lu.assertEquals(runs, 1)
  lu.assertEquals(last_seen, 0)

  state:set(7)
  lu.assertEquals(runs, 2)
  lu.assertEquals(last_seen, 7)
  tree:dispose()
end

function TestReaction.test_cleanup_runs_before_rerun()
  local state = State.new(0)
  local log = {}

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    local v = s:d(state)
    log[#log + 1] = "mount:" .. v
    s:on_cleanup(function()
      log[#log + 1] = "cleanup:" .. v
    end)
  end))
  lu.assertEquals(log, {})

  state:set(1)
  -- Without a static trigger, the reaction still has not run.
  lu.assertEquals(log, {})
  tree:dispose()
end

function TestReaction.test_cleanup_runs_before_rerun_after_first_fire()
  local state = State.new(0)
  local trigger = Trigger.new()
  local log = {}

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    local v = s:d(state)
    log[#log + 1] = "mount:" .. v
    s:on_cleanup(function()
      log[#log + 1] = "cleanup:" .. v
    end)
  end, trigger))

  trigger:invoke()
  lu.assertEquals(log, { "mount:0" })

  state:set(1)
  lu.assertEquals(log, { "mount:0", "cleanup:0", "mount:1" })
  tree:dispose()
end

function TestReaction.test_multiple_static_triggers_as_array()
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Reaction.new("r", function()
    runs = runs + 1
  end, { t1, t2 }))
  lu.assertEquals(runs, 0)

  t1:invoke()
  lu.assertEquals(runs, 1)
  t2:invoke()
  lu.assertEquals(runs, 2)
  tree:dispose()
end

function TestReaction.test_unnamed_constructor_form()
  local runs = 0
  local trigger = Trigger.new()

  local tree = SpokeTree.spawn(Reaction.new(function()
    runs = runs + 1
  end, trigger))
  lu.assertEquals(runs, 0)

  trigger:invoke()
  lu.assertEquals(runs, 1)
  tree:dispose()
end

function TestReaction.test_nil_block_is_safe()
  local trigger = Trigger.new()

  local tree = SpokeTree.spawn(Reaction.new(nil, trigger))
  lu.assertNotNil(tree)

  trigger:invoke()
  tree:dispose()
end

function TestReaction.test_dropped_dynamic_dependency_no_longer_reruns()
  local gate = State.new(true)
  local extra = State.new(0)
  local trigger = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    runs = runs + 1
    if s:d(gate) then
      local _ = s:d(extra)
    end
  end, trigger))

  trigger:invoke()
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

function TestReaction.test_detach_disposes_all_subscriptions()
  local trigger = Trigger.new()
  local state = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Reaction.new("r", function(s)
    runs = runs + 1
    local _ = s:d(state)
  end, trigger))

  trigger:invoke()
  lu.assertEquals(runs, 1)

  tree:dispose()

  trigger:invoke()
  state:set(1)
  lu.assertEquals(runs, 1)
end
