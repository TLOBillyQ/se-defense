-- Public facade for spoke-lua: require("vendor.spoke") returns an aggregate table
-- of the 13 public classes (#2 decision). SpokeRuntime and the utility types
-- (Heap, PackedTreeCoords, SpokeException, ...) stay internal; deep requires
-- are not blocked — tests and advanced usage can still reach the modules
-- directly under vendor/spoke/runtime/ and vendor/spoke/reactive/.

local Epoch = require("vendor.spoke.runtime.epoch")
local Ticker = require("vendor.spoke.runtime.ticker")
local SpokeTree = require("vendor.spoke.runtime.spoke_tree")
local Dock = require("vendor.spoke.runtime.dock")
local LambdaEpoch = require("vendor.spoke.runtime.lambda_epoch")
local SpokeHandle = require("vendor.spoke.runtime.spoke_handle")

local Trigger = require("vendor.spoke.reactive.trigger")
local State = require("vendor.spoke.reactive.state")
local Effect = require("vendor.spoke.reactive.effect")
local Reaction = require("vendor.spoke.reactive.reaction")
local Memo = require("vendor.spoke.reactive.memo")
local Phase = require("vendor.spoke.reactive.phase")
local EffectBuilder = require("vendor.spoke.reactive.effect_builder")

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
