-- Unit tests for server/adapter/convert.lua, the shared colour conversion and
-- table-normalising copies extracted by #43. The module only touches the SE
-- Color global inside rgb01, so the test supplies a minimal fake.
local lu = require("luaunit")
local convert = require("server.adapter.convert")

TestAdapterConvert = {}

function TestAdapterConvert:setUp()
  self.original_color = _G.Color
  _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
end

function TestAdapterConvert:tearDown()
  _G.Color = self.original_color
end

function TestAdapterConvert:test_copy_vec3_named_table_is_copied()
  local v = { x = 1, y = 2, z = 3 }
  local copy = convert.copy_vec3(v)
  lu.assertEquals(copy, { x = 1, y = 2, z = 3 })
  lu.assertTrue(copy ~= v)
  copy.x = 9
  lu.assertEquals(v.x, 1)
end

function TestAdapterConvert:test_copy_vec3_array_table_and_defaults()
  lu.assertEquals(convert.copy_vec3({ 1, 2, 3 }), { x = 1, y = 2, z = 3 })
  lu.assertEquals(convert.copy_vec3({ x = 1 }), { x = 1, y = 0, z = 0 })
  lu.assertEquals(convert.copy_vec3(nil), { x = 0, y = 0, z = 0 })
end

function TestAdapterConvert:test_copy_color_named_table_is_copied()
  local c = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
  local copy = convert.copy_color(c)
  lu.assertEquals(copy, { r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
  lu.assertTrue(copy ~= c)
end

function TestAdapterConvert:test_copy_color_array_table_and_defaults()
  lu.assertEquals(convert.copy_color({ 0.1, 0.2, 0.3, 0.4 }),
    { r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
  lu.assertEquals(convert.copy_color({ r = 0.5 }), { r = 0.5, g = 1, b = 1, a = 1 })
  lu.assertEquals(convert.copy_color(nil), { r = 1, g = 1, b = 1, a = 1 })
end

function TestAdapterConvert:test_rgb01_rounds_half_up_and_defaults_alpha()
  lu.assertEquals(convert.rgb01(0, 0.5, 1), { r = 0, g = 128, b = 255, a = 255 })
end

function TestAdapterConvert:test_rgb01_keeps_explicit_alpha()
  lu.assertEquals(convert.rgb01(0.2, 0.4, 0.6, 0.8), { r = 51, g = 102, b = 153, a = 204 })
end
