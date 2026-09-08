-- Property tests for common/unit_name.lua: the shared naming format is
-- stable for arbitrary ids and generations.
local property = require("tests.spoke.property.support.property")
local unit_name = require("common.unit_name")

local gen = property.gen
local id = gen.one_of(gen.integer(0, 9999), gen.string(8, { 97, 98, 99 }))
local generation = gen.integer(0, 100)

property.forall("unit_name_first_generation_is_bare_id", { id }, function(value)
  return unit_name.format(value, 0) == tostring(value)
end)

property.forall("unit_name_restart_is_id_g_generation", { id, generation }, function(value, g)
  local want = tostring(value)
  if g > 0 then want = want .. "g" .. tostring(g) end
  return unit_name.format(value, g) == want
end)

property.forall("unit_name_nil_generation_is_first_generation", { id }, function(value)
  return unit_name.format(value) == unit_name.format(value, 0)
end)
