-- Unit tests for common/unit_name.lua: the shared unit-name convention
-- (#18 decision 4 + #28 generation suffix).
local lu = require("luaunit")
local unit_name = require("common.unit_name")

TestUnitName = {}

function TestUnitName:test_first_game_is_bare_id()
  lu.assertEquals(unit_name.format(7, 0), "7")
  lu.assertEquals(unit_name.format(7), "7")
end

function TestUnitName:test_restart_appends_generation()
  lu.assertEquals(unit_name.format(7, 1), "7g1")
  lu.assertEquals(unit_name.format("abc", 2), "abcg2")
end
