-- Sanity test: proves the toolchain link works (Lua 5.4 + vendored LuaUnit).
local lu = require("luaunit")

TestSanity = {}

function TestSanity.test_lua_version()
  lu.assertEquals(_VERSION, "Lua 5.4")
end

function TestSanity.test_bitops()
  -- The port relies on Lua 5.4 integer bit operations (tree coordinates).
  lu.assertEquals((0x12 << 8) | 0x34, 0x1234)
  lu.assertEquals(math.type(1 << 3), "integer")
end
