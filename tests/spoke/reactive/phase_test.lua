local lu = require("luaunit")
local Phase = require("common.spoke.reactive.phase")
local SpokeTree = require("common.spoke.runtime.spoke_tree")
local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")

TestPhase = {}

function TestPhase.test_mounts_and_unmounts_on_bool_flip()
  local gate = State.new(false)
  local mounted = 0
  local cleaned = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function(s)
    mounted = mounted + 1
    s:on_cleanup(function()
      cleaned = cleaned + 1
    end)
  end))

  lu.assertEquals(mounted, 0, "Phase should not mount while gate=false")

  gate:set(true)
  lu.assertEquals(mounted, 1)
  lu.assertEquals(cleaned, 0)

  gate:set(false)
  lu.assertEquals(mounted, 1)
  lu.assertEquals(cleaned, 1)

  gate:set(true)
  lu.assertEquals(mounted, 2)
  lu.assertEquals(cleaned, 1)

  tree:dispose()
end

function TestPhase.test_mounts_on_spawn_when_gate_initially_true()
  local gate = State.new(true)
  local mounted = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function()
    mounted = mounted + 1
  end))

  lu.assertEquals(mounted, 1)

  gate:set(false)
  lu.assertEquals(mounted, 1)

  gate:set(true)
  lu.assertEquals(mounted, 2)

  tree:dispose()
end

function TestPhase.test_reruns_while_mounted_when_additional_triggers_fire()
  local gate = State.new(true)
  local pulse = Trigger.new()
  local runs = 0
  local cleanups = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function(s)
    runs = runs + 1
    s:on_cleanup(function()
      cleanups = cleanups + 1
    end)
  end, pulse))

  lu.assertEquals(runs, 1)
  lu.assertEquals(cleanups, 0)

  pulse:invoke()
  lu.assertEquals(runs, 2)
  lu.assertEquals(cleanups, 1)

  pulse:invoke()
  lu.assertEquals(runs, 3)
  lu.assertEquals(cleanups, 2)

  tree:dispose()
end

function TestPhase.test_additional_triggers_do_not_mount_when_gate_is_false()
  local gate = State.new(false)
  local pulse = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function()
    runs = runs + 1
  end, pulse))

  pulse:invoke()
  lu.assertEquals(runs, 0, "Triggers should not cause Phase block to run while gate=false")

  gate:set(true)
  lu.assertEquals(runs, 1)

  tree:dispose()
end

function TestPhase.test_dynamic_dependencies_are_removed_while_unmounted()
  local gate = State.new(false)
  local extra = State.new(0)
  local runs = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function(s)
    runs = runs + 1
    if s:d(gate) then
      local _ = s:d(extra)
    end
  end))

  lu.assertEquals(runs, 0)

  gate:set(true)
  lu.assertEquals(runs, 1)

  extra:set(1)
  lu.assertEquals(runs, 2)

  gate:set(false)
  lu.assertEquals(runs, 2)

  extra:set(2)
  lu.assertEquals(runs, 2)

  gate:set(true)
  lu.assertEquals(runs, 3)

  tree:dispose()
end

function TestPhase.test_named_and_unnamed_constructors()
  local gate = State.new(true)

  local named = Phase.new("named_phase", gate, function() end)
  lu.assertEquals(named.name, "named_phase")

  local unnamed = Phase.new(gate, function() end)
  lu.assertEquals(unnamed.name, "Phase")
end

function TestPhase.test_explicit_triggers_as_array()
  local gate = State.new(true)
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function()
    runs = runs + 1
  end, { t1, t2 }))

  t1:invoke()
  lu.assertEquals(runs, 2)

  t2:invoke()
  lu.assertEquals(runs, 3)

  tree:dispose()
end

function TestPhase.test_explicit_triggers_as_varargs()
  local gate = State.new(true)
  local t1 = Trigger.new()
  local t2 = Trigger.new()
  local runs = 0

  local tree = SpokeTree.spawn(Phase.new("p", gate, function()
    runs = runs + 1
  end, t1, t2))

  t1:invoke()
  lu.assertEquals(runs, 2)

  t2:invoke()
  lu.assertEquals(runs, 3)

  tree:dispose()
end
