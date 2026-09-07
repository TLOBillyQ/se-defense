-- Sanity test: proves the toolchain link works (vendored LuaUnit + the
-- integer bit operations the tree coordinates rely on).
local lu = require("luaunit")

TestSanity = {}

function TestSanity.test_bitops()
  lu.assertEquals((0x12 << 8) | 0x34, 0x1234)
  lu.assertEquals(math.type(1 << 3), "integer")
end
