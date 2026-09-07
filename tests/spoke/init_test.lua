-- Facade test: require("common.spoke") aggregates exactly the 13 public classes
-- from the #2 decision, identical to the deep requires; internals stay out.
local lu = require("luaunit")

TestInit = {}

local PUBLIC = {
  "Epoch", "Ticker", "SpokeTree", "Dock", "LambdaEpoch", "SpokeHandle",
  "Trigger", "State", "Effect", "Reaction", "Memo", "Phase", "EffectBuilder",
}

function TestInit.test_facade_exposes_exactly_the_public_surface()
  local spoke = require("common.spoke")
  lu.assertEquals(type(spoke), "table")

  for _, name in ipairs(PUBLIC) do
    lu.assertEquals(type(spoke[name]), "table", name .. " missing from facade")
  end

  local public_set = {}
  for _, name in ipairs(PUBLIC) do
    public_set[name] = true
  end
  local count = 0
  for key, _ in pairs(spoke) do
    count = count + 1
    lu.assertTrue(public_set[key] == true, "unexpected export: " .. tostring(key))
  end
  lu.assertEquals(count, #PUBLIC)

  -- Internal types are not promoted into the facade (#2: 保持内部).
  lu.assertNil(spoke.SpokeRuntime)
  lu.assertNil(spoke.Heap)
  lu.assertNil(spoke.PackedTreeCoords)
  lu.assertNil(spoke.SpokeException)
end

function TestInit.test_facade_entries_are_the_deep_require_classes()
  local spoke = require("common.spoke")
  lu.assertIs(spoke.Epoch, require("common.spoke.runtime.epoch"))
  lu.assertIs(spoke.Ticker, require("common.spoke.runtime.ticker"))
  lu.assertIs(spoke.SpokeTree, require("common.spoke.runtime.spoke_tree"))
  lu.assertIs(spoke.Dock, require("common.spoke.runtime.dock"))
  lu.assertIs(spoke.LambdaEpoch, require("common.spoke.runtime.lambda_epoch"))
  lu.assertIs(spoke.SpokeHandle, require("common.spoke.runtime.spoke_handle"))
  lu.assertIs(spoke.Trigger, require("common.spoke.reactive.trigger"))
  lu.assertIs(spoke.State, require("common.spoke.reactive.state"))
  lu.assertIs(spoke.Effect, require("common.spoke.reactive.effect"))
  lu.assertIs(spoke.Reaction, require("common.spoke.reactive.reaction"))
  lu.assertIs(spoke.Memo, require("common.spoke.reactive.memo"))
  lu.assertIs(spoke.Phase, require("common.spoke.reactive.phase"))
  lu.assertIs(spoke.EffectBuilder, require("common.spoke.reactive.effect_builder"))
end

function TestInit.test_facade_smoke_tree_and_reactive()
  local spoke = require("common.spoke")

  -- Runtime smoke: a LambdaEpoch tree ticks and flushes.
  local ticks = 0
  local tree = spoke.SpokeTree.spawn_manual(spoke.LambdaEpoch.new("root", function(_)
    return function()
      ticks = ticks + 1
    end
  end))
  tree:tick()
  tree:flush()
  lu.assertEquals(ticks, 1)
  tree:dispose()

  -- Reactive smoke: State notifies subscribers through the facade classes.
  local seen
  local state = spoke.State.new(1)
  state:subscribe(function(v) seen = v end)
  state:set(2)
  lu.assertEquals(seen, 2)
  lu.assertEquals(state:now(), 2)
end
