local lu = require("luaunit")
local LambdaEpoch = require("common.spoke.runtime.lambda_epoch")
local SpokeTree = require("common.spoke.runtime.spoke_tree")

TestLambdaEpoch = {}

function TestLambdaEpoch.test_lambda_epoch_runs_init_and_tick()
  local init_ran = false
  local tick_ran = false

  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    init_ran = true
    return function()
      tick_ran = true
    end
  end))

  lu.assertTrue(init_ran)
  lu.assertFalse(tick_ran)

  tree:flush()
  lu.assertTrue(tick_ran)
end

function TestLambdaEpoch.test_named_constructor_sets_name()
  local ticked = false
  local epoch = LambdaEpoch.new("NamedLambda", function(s)
    return function()
      ticked = true
    end
  end)

  lu.assertEquals(epoch.name, "NamedLambda")

  local tree = SpokeTree.spawn_manual(epoch)
  tree:flush()
  lu.assertTrue(ticked)
end

function TestLambdaEpoch.test_nil_tick_is_allowed()
  local init_ran = false
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    init_ran = true
    return nil
  end))

  lu.assertTrue(init_ran)
  lu.assertTrue(tree:has_pending())
  tree:flush()
  lu.assertFalse(tree:has_pending())
end

function TestLambdaEpoch.test_lambda_epoch_can_use_builder_attachments()
  local log = {}
  local tree = SpokeTree.spawn_manual(LambdaEpoch.new(function(s)
    s:on_cleanup(function()
      log[#log + 1] = "cleanup"
    end)
    s:export("key", "value")
    return function(tick_s)
      log[#log + 1] = tick_s:import("key")
    end
  end))

  tree:flush()
  lu.assertEquals(log, { "value" })

  tree:dispose()
  lu.assertEquals(log, { "value", "cleanup" })
end
