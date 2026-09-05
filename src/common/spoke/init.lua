-- Public facade for spoke-lua: require("src.common.spoke") returns an aggregate table
-- of the 13 public classes (#2 decision). SpokeRuntime and the utility types
-- (Heap, PackedTreeCoords, SpokeException, ...) stay internal; deep requires
-- are not blocked — tests and advanced usage can still reach the modules
-- directly under src/common/spoke/runtime/ and src/common/spoke/reactive/.

local Epoch = require("src.common.spoke.runtime.epoch")
local Ticker = require("src.common.spoke.runtime.ticker")
local SpokeTree = require("src.common.spoke.runtime.spoke_tree")
local Dock = require("src.common.spoke.runtime.dock")
local LambdaEpoch = require("src.common.spoke.runtime.lambda_epoch")
local SpokeHandle = require("src.common.spoke.runtime.spoke_handle")

local Trigger = require("src.common.spoke.reactive.trigger")
local State = require("src.common.spoke.reactive.state")
local Effect = require("src.common.spoke.reactive.effect")
local Reaction = require("src.common.spoke.reactive.reaction")
local Memo = require("src.common.spoke.reactive.memo")
local Phase = require("src.common.spoke.reactive.phase")
local EffectBuilder = require("src.common.spoke.reactive.effect_builder")

return {
  -- Runtime layer
  Epoch = Epoch,
  Ticker = Ticker,
  SpokeTree = SpokeTree,
  Dock = Dock,
  LambdaEpoch = LambdaEpoch,
  SpokeHandle = SpokeHandle,
  -- Reactive layer
  Trigger = Trigger,
  State = State,
  Effect = Effect,
  Reaction = Reaction,
  Memo = Memo,
  Phase = Phase,
  EffectBuilder = EffectBuilder,
}
