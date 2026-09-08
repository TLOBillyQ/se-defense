-- Property tests for server/adapter/convert.lua normalization:
-- canonical shape/defaults for named tables and non-mutating copies.
local property = require("tests.spoke.property.support.property")
local convert = require("server.adapter.convert")

local gen = property.gen
local number = gen.float(-100, 100)

local function named_table(fields)
  return function(rng)
    local out = {}
    for _, field in ipairs(fields) do
      if rng:boolean() then out[field] = number(rng) end
    end
    return out
  end
end

local scalar = gen.one_of(
  function() return nil end,
  gen.boolean,
  gen.integer(-100, 100),
  gen.float(-100, 100),
  gen.string(8))

property.forall("copy_vec3_canonicalizes_without_mutation", { named_table({ "x", "y", "z" }) },
  function(v)
    local before = { x = v.x, y = v.y, z = v.z }
    local copy = convert.copy_vec3(v)
    if copy == v then return "copy aliases input" end
    if copy.x ~= (v.x or 0) or copy.y ~= (v.y or 0) or copy.z ~= (v.z or 0) then
      return "copy_vec3 changed values"
    end
    if v.x ~= before.x or v.y ~= before.y or v.z ~= before.z then
      return "copy_vec3 mutated input"
    end
    return true
  end)

property.forall("copy_vec3_non_table_is_origin", { scalar }, function(v)
  local copy = convert.copy_vec3(v)
  return copy.x == 0 and copy.y == 0 and copy.z == 0
end)

property.forall("copy_color_canonicalizes_without_mutation", { named_table({ "r", "g", "b", "a" }) },
  function(c)
    local before = { r = c.r, g = c.g, b = c.b, a = c.a }
    local copy = convert.copy_color(c)
    if copy == c then return "copy aliases input" end
    if copy.r ~= (c.r or 1) or copy.g ~= (c.g or 1)
      or copy.b ~= (c.b or 1) or copy.a ~= (c.a or 1) then
      return "copy_color changed values"
    end
    if c.r ~= before.r or c.g ~= before.g or c.b ~= before.b or c.a ~= before.a then
      return "copy_color mutated input"
    end
    return true
  end)

property.forall("copy_color_non_table_is_opaque_white", { scalar }, function(c)
  local copy = convert.copy_color(c)
  return copy.r == 1 and copy.g == 1 and copy.b == 1 and copy.a == 1
end)
