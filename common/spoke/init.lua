-- Public facade for spoke-lua: require("common.spoke") returns an aggregate table
-- of the 13 public classes (#2 decision). SpokeRuntime and the utility types
-- (Heap, PackedTreeCoords, SpokeException, ...) stay internal; deep requires
-- are not blocked — tests and advanced usage can still reach the modules
-- directly under common/spoke/runtime/ and common/spoke/reactive/.

local Epoch = require("common.spoke.runtime.epoch")
local Ticker = require("common.spoke.runtime.ticker")
local SpokeTree = require("common.spoke.runtime.spoke_tree")
local Dock = require("common.spoke.runtime.dock")
local LambdaEpoch = require("common.spoke.runtime.lambda_epoch")
local SpokeHandle = require("common.spoke.runtime.spoke_handle")

local Trigger = require("common.spoke.reactive.trigger")
local State = require("common.spoke.reactive.state")
local Effect = require("common.spoke.reactive.effect")
local Reaction = require("common.spoke.reactive.reaction")
local Memo = require("common.spoke.reactive.memo")
local Phase = require("common.spoke.reactive.phase")
local EffectBuilder = require("common.spoke.reactive.effect_builder")

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
