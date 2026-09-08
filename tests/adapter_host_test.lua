-- Unit test for the reset_scene adapter merge (#43): the host table must keep
-- reset_scene as a function value that tolerates the business colon call.
local lu = require("luaunit")
require("tools.headless.se_stub")
local host = require("server.adapter.host")

TestAdapterHost = {}

function TestAdapterHost:setUp()
  self.originals = {
    entity_reset = host.entity.reset,
    eui_reset = host.eui.reset,
    input_reset = host.input.reset_all,
  }
  self.calls = {}
  host.entity.reset = function() self.calls[#self.calls + 1] = "entity" end
  host.eui.reset = function() self.calls[#self.calls + 1] = "eui" end
  host.input.reset_all = function() self.calls[#self.calls + 1] = "input" end
end

function TestAdapterHost:tearDown()
  host.entity.reset = self.originals.entity_reset
  host.eui.reset = self.originals.eui_reset
  host.input.reset_all = self.originals.input_reset
end

function TestAdapterHost:test_reset_scene_is_callable_with_colon()
  lu.assertEquals(type(host.reset_scene), "function")
  host:reset_scene()
  lu.assertEquals(self.calls, { "entity", "eui", "input" })
end
