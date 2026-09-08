-- Unit tests for common/color_norm.lua: the single shared normalisation
-- (named table / numeric array -> {r,g,b,a}, missing channels default to 1).
local lu = require("luaunit")
local color_norm = require("common.color_norm")

TestColorNorm = {}

function TestColorNorm:test_named_table_is_copied()
  local c = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
  local copy = color_norm.copy_color(c)
  lu.assertEquals(copy, { r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
  lu.assertTrue(copy ~= c)
end

function TestColorNorm:test_array_table_and_defaults()
  lu.assertEquals(color_norm.copy_color({ 0.1, 0.2, 0.3, 0.4 }),
    { r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
  lu.assertEquals(color_norm.copy_color({ r = 0.5 }), { r = 0.5, g = 1, b = 1, a = 1 })
  lu.assertEquals(color_norm.copy_color({}), { r = 1, g = 1, b = 1, a = 1 })
end

function TestColorNorm:test_non_table_is_opaque_white()
  lu.assertEquals(color_norm.copy_color(nil), { r = 1, g = 1, b = 1, a = 1 })
  lu.assertEquals(color_norm.copy_color("nope"), { r = 1, g = 1, b = 1, a = 1 })
  lu.assertEquals(color_norm.copy_color(42), { r = 1, g = 1, b = 1, a = 1 })
end

function TestColorNorm:test_named_table_wins_over_array_slot()
  lu.assertEquals(color_norm.copy_color({ 0.1, 0.2, 0.3, r = 0.9 }).r, 0.9)
end
