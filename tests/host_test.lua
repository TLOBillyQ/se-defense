-- Unit tests for src/server/adapter/host.lua message routing. host.handle is
-- pure with respect to SE globals (only boot touches the host), so it runs in
-- the plain unit-test process without the SE stub.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local host = require("server.adapter.host")

TestHost = {}

local function playing()
  local g = match_flow.new()
  g:start()
  return g
end

function TestHost.test_handle_routes_start_restart_place()
  local g = match_flow.new()
  host.handle(g, { action = "start" })
  lu.assertEquals(g.mode, "Playing")
  host.handle(g, { action = "place", kind = "Relay", x = 2, z = 0 })
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
  g.entities:deplete_sites(27)
  g:advance(1)
  lu.assertEquals(g.mode, "Victory")
  host.handle(g, { action = "restart" })
  lu.assertEquals(g.mode, "Pregame")
end

function TestHost.test_handle_ignores_malformed_messages()
  local g = playing()
  host.handle(nil, nil)
  host.handle(g, nil)
  host.handle(g, "start")
  host.handle(g, {})
  host.handle(g, { action = "bogus" })
  lu.assertEquals(g.mode, "Playing")
  lu.assertEquals(g.money, 100)
end
