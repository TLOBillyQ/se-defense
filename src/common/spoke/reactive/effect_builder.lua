local Computation = require("src.common.spoke.reactive.computation")
local Dock = require("src.common.spoke.runtime.dock")
local SpokeHandle = require("src.common.spoke.runtime.spoke_handle")

-- DSL-style builders passed into effect blocks and memo selectors. They are
-- only valid while the owning block is executing; the underlying Epoch builder
-- is sealed when the window closes, and every method re-checks that seal.

local EffectBuilder = {}
EffectBuilder.__index = EffectBuilder

local MemoBuilder = {}
MemoBuilder.__index = MemoBuilder

local function assert_active(builder)
  local s = builder._s
  if not s._active
    or not s._frame_handle
    or not s._frame_handle:is_top() then
    error("Tried to mutate an Epoch that's been sealed for further changes.", 3)
  end
end

-- Trigger-shape normalization lives on Computation (shared with Memo/Phase).
local collect_triggers = Computation._collect_triggers

function EffectBuilder.new(add_dynamic, epoch_builder)
  return setmetatable({
    _add_dynamic = add_dynamic,
    _s = epoch_builder,
  }, EffectBuilder)
end

-- Dynamically adds a signal dependency to the block and returns its current
-- value. The block re-runs when the signal changes.
function EffectBuilder:d(signal)
  assert_active(self)
  self._add_dynamic(signal)
  return signal:now()
end

-- Subscribes to the trigger and owns the handle for the current run.
function EffectBuilder:subscribe(trigger, fn)
  assert_active(self)
  if trigger == nil then
    return self:use(SpokeHandle.new())
  end
  return self:use(trigger:subscribe(fn))
end

function EffectBuilder:use(resource)
  assert_active(self)
  return self._s:use(resource)
end

function EffectBuilder:call(epoch)
  assert_active(self)
  return self._s:call(epoch)
end

function EffectBuilder:export(key, value)
  assert_active(self)
  return self._s:export(key, value)
end

function EffectBuilder:import(key)
  assert_active(self)
  return self._s:import(key)
end

function EffectBuilder:try_import(key)
  assert_active(self)
  return self._s:try_import(key)
end

function EffectBuilder:on_cleanup(fn)
  assert_active(self)
  self._s:on_cleanup(fn)
end

function EffectBuilder:log(message)
  assert_active(self)
  self._s:log(message)
end

-- Nested factories: attach a child reactive epoch with bound lifetime. Each
-- accepts an optional leading name and trailing triggers (varargs or array).
-- The Effect/Reaction/Memo/Phase modules are required lazily because they are
-- ported after this module.

-- Memo and Reaction share one argument shape: (block [, triggers]) or
-- (name, block [, triggers]).
local function call_block_factory(builder, class, a, b, ...)
  if type(a) == "string" then
    return builder:call(class.new(a, b, collect_triggers(...)))
  end
  return builder:call(class.new(a, collect_triggers(b, ...)))
end

function EffectBuilder:memo(a, b, ...)
  assert_active(self)
  local Memo = require("src.common.spoke.reactive.memo")
  return call_block_factory(self, Memo, a, b, ...)
end

function EffectBuilder:effect(a, b, ...)
  assert_active(self)
  local Effect = require("src.common.spoke.reactive.effect")
  local name, block, triggers = Computation._parse_effect_args(a, b, ...)
  if name ~= nil then
    return self:call(Effect.new(name, block, triggers))
  end
  return self:call(Effect.new(block, triggers))
end

function EffectBuilder:reaction(a, b, ...)
  assert_active(self)
  local Reaction = require("src.common.spoke.reactive.reaction")
  return call_block_factory(self, Reaction, a, b, ...)
end

function EffectBuilder:phase(a, b, c, ...)
  assert_active(self)
  local Phase = require("src.common.spoke.reactive.phase")
  if type(a) == "string" then
    return self:call(Phase.new(a, b, c, collect_triggers(...)))
  end
  return self:call(Phase.new(a, b, collect_triggers(c, ...)))
end

function EffectBuilder:dock(name)
  assert_active(self)
  return self:call(Dock.new(name))
end

-- MemoBuilder is intentionally narrow, matching upstream: a Memo is a pure
-- derived value, not an attachment-building scope.

function MemoBuilder.new(add_dynamic, epoch_builder)
  return setmetatable({
    _add_dynamic = add_dynamic,
    _s = epoch_builder,
  }, MemoBuilder)
end

function MemoBuilder:d(signal)
  assert_active(self)
  self._add_dynamic(signal)
  return signal:now()
end

function MemoBuilder:on_cleanup(fn)
  assert_active(self)
  self._s:on_cleanup(fn)
end

EffectBuilder.MemoBuilder = MemoBuilder

return EffectBuilder
