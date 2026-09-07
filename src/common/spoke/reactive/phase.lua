local Computation = require("common.spoke.reactive.computation")
local EffectBuilder = require("common.spoke.reactive.effect_builder")

-- Trigger-shape normalization lives on Computation (shared with the other
-- reactive subclasses); phase copies the result because it appends mount_when
-- and must not mutate a caller-owned trigger array.
local collect_triggers = Computation._collect_triggers

-- A Phase is a Computation that mounts its block only while `mount_when` is
-- true. The boolean signal is always a static dependency; when it becomes false
-- the previous block is cleaned up and nothing is remounted. Additional
-- triggers may still schedule the Phase while false, but the block remains
-- unmounted. Dynamic dependencies read by the block are dropped while false.
local Phase = Computation.extend("Phase", {
  constructor = function(self, mount_when, block, ...)
    local normalized = collect_triggers(...)
    -- mount_when is an additional static dependency beyond explicit triggers;
    -- copy into a fresh array so the caller's array is never mutated.
    local triggers = {}
    for index = 1, #(normalized or {}) do
      triggers[index] = normalized[index]
    end
    triggers[#triggers + 1] = mount_when
    Computation.constructor(self, triggers)
    self._mount_when = mount_when
    self._block = block
  end,

  on_run = function(self, s)
    if self._mount_when:now() then
      local builder = EffectBuilder.new(function(signal)
        self:_add_dynamic_trigger(signal)
      end, s)
      if self._block ~= nil then
        self._block(builder)
      end
    end
  end,
})

return Phase
