local Computation = require("src.common.spoke.reactive.computation")
local EffectBuilder = require("src.common.spoke.reactive.effect_builder")

-- A Reaction is an Effect whose block is not run on initial mount. Static
-- subscriptions are installed during Init, so the first trigger fire schedules
-- the initial Tick; after that it follows normal Effect cleanup/rerun rules.
local Reaction = Computation.extend("Reaction", {
  -- Inherit Computation's auto-arm behavior, then disable the initial tick.
  auto_arm_tick_after_init = false,

  constructor = function(self, block, triggers)
    Computation.constructor(self, triggers)
    self._block = block
  end,

  on_run = function(self, s)
    if self._block ~= nil then
      self._block(EffectBuilder.new(function(signal)
        self:_add_dynamic_trigger(signal)
      end, s))
    end
  end,
})

return Reaction
