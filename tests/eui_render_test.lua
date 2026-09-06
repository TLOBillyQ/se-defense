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

-- 假通道：记录上行消息，并可从服务端侧投递信封。
local function fake_channel()
  local ch = { up = {}, handler = nil }
  ch.FireServer = function(_, msg) ch.up[#ch.up + 1] = msg end
  ch.OnClientEvent = { Connect = function(_, fn) ch.handler = fn end }
  return ch
end

-- 握手：订阅即发 client_ready；全量信封替换整树并对齐 seq。
function TestEuiRender.test_connect_requests_full_and_full_replaces_tree()
  eui_render.applied, eui_render.seq = { ["stale"] = { text = "x" } }, 0
  local ch = fake_channel()
  eui_render.connect(ch)
  lu.assertEquals(ch.up, { { action = "client_ready" } })
  ch.handler({ seq = 7, full = true, nodes = { ["hud/money"] = { text = "1" } } })
  lu.assertNil(eui_render.applied["stale"])
  lu.assertEquals(eui_render.applied["hud/money"].text, "1")
  lu.assertEquals(eui_render.seq, 7)
end

-- 增量：seq 连续则合并；出现缺口则丢弃该帧并再次索取全量。
function TestEuiRender.test_delta_requires_consecutive_seq()
  eui_render.applied, eui_render.seq = {}, 0
  local ch = fake_channel()
  eui_render.connect(ch)
  ch.handler({ seq = 1, nodes = { ["a"] = { text = "1" } } })
  ch.handler({ seq = 3, nodes = { ["a"] = { text = "3" } } })
  lu.assertEquals(eui_render.applied["a"].text, "1")
  lu.assertEquals(eui_render.seq, 1)
  lu.assertEquals(#ch.up, 2)
  ch.handler({ seq = 2, nodes = { ["a"] = { text = "2" } } })
  lu.assertEquals(eui_render.applied["a"].text, "2")
end
