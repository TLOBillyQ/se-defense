local Computation = require("src.common.spoke.reactive.computation")
local EffectBuilder = require("src.common.spoke.reactive.effect_builder")
local LambdaEpoch = require("src.common.spoke.runtime.lambda_epoch")
local State = require("src.common.spoke.reactive.state")

local function is_signal(value)
  return type(value) == "table"
    and type(value.now) == "function"
    and type(value.subscribe) == "function"
    and type(value.unsubscribe) == "function"
end

-- An Effect runs an EffectBlock and re-runs whenever any of its triggers fire.
-- It also covers the upstream Effect<T> form: when the block returns a signal,
-- the Effect mirrors that signal's current value through now/subscribe/unsubscribe.
local Effect = Computation.extend("Effect", {
  constructor = function(self, block, triggers)
    if block ~= nil and type(block) ~= "function" then
      error("Effect.new expects a block function", 2)
    end
    Computation.constructor(self, triggers)
    self._block = block
    -- Output state for the signal-producing form. Side-effect effects simply
    -- leave this at nil; the same state is reused across reruns.
    self._output_state = State.new()
    -- Whether any run has produced a signal. Once true, later runs that stop
    -- producing a signal must clear the mirrored value (upstream Effect<T>
    -- resets to default when the block returns null).
    self._was_signal = false
  end,

  on_run = function(self, s)
    if self._block == nil then
      -- Upstream Effect tolerates a null block as a no-op.
      return
    end
    local builder = EffectBuilder.new(function(signal)
      self:_add_dynamic_trigger(signal)
    end, s)

    local result = self._block(builder)

    local result_is_signal = is_signal(result)
    if result_is_signal then
      -- Mirror the signal's current value through the output state. This is
      -- done in a child epoch so downstream observers see a stable update
      -- order matching upstream's deferred initializer.
      builder:subscribe(result, function(value)
        self._output_state:set(value)
      end)
      builder:call(LambdaEpoch.new("Deferred Initializer", function()
        return function()
          self._output_state:set(result:now())
        end
      end))
    elseif self._was_signal then
      -- The block stopped returning a signal: clear the mirrored value so
      -- downstream observers reset, matching upstream Effect<T> when the
      -- block returns null.
      builder:call(LambdaEpoch.new("Deferred Initializer", function()
        return function()
          self._output_state:set(nil)
        end
      end))
    end
    -- Pure side-effect path (never produced a signal): nothing allocated and
    -- no output_state notification, per ADR 0003 allocation notes.
    self._was_signal = self._was_signal or result_is_signal
  end,
})

-- Effect:now() mirrors the output state of the signal-producing form.

function Effect:now()
  return self._output_state:now()
end

function Effect:subscribe(fn)
  return self._output_state:subscribe(fn)
end

function Effect:unsubscribe(fn)
  return self._output_state:unsubscribe(fn)
end

return Effect
