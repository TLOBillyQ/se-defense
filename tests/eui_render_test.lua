-- Unit tests for src/client/eui_render.lua snapshot application. M.apply is a
-- pure table merge over M.applied; the RemoteEvent seam (M.connect) is covered
-- by the acceptance harness, not here.
local lu = require("luaunit")
local eui_render = require("client.eui_render")

TestEuiRender = {}

function TestEuiRender.test_apply_merges_snapshot_nodes()
  eui_render.applied = {}
  eui_render.apply({ ["hud/money"] = { text = "100" } })
  eui_render.apply({ ["hud/wave"] = { text = "1" } })
  lu.assertEquals(eui_render.applied["hud/money"].text, "100")
  lu.assertEquals(eui_render.applied["hud/wave"].text, "1")
end

function TestEuiRender.test_apply_ignores_non_table_input()
  eui_render.applied = {}
  eui_render.apply(nil)
  eui_render.apply("snapshot")
  eui_render.apply(42)
  lu.assertNil(next(eui_render.applied))
end
