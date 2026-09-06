-- Unit tests for the snapshot routing adapter (CONTEXT.md「快照」「双路由」):
-- node-level incremental updates with a monotonic seq, full resync on
-- handshake (client_ready), and the client dumb mirror folding the envelope.
local lu = require("luaunit")
local eui = require("server.adapter.eui")

local function fake_channel()
  return { sent = {}, FireAllClients = function(self, msg) self.sent[#self.sent + 1] = msg end }
end

TestEuiRouter = {}

-- 首帧全量；之后只发变化节点，seq 单调。
function TestEuiRouter.test_incremental_diff_with_seq()
  local ch = fake_channel()
  local r = eui.new(ch)
  r:push({ ["hud.money"] = { text = "$100" }, ["hud.wave"] = { text = "Wave 1" } })
  r:push({ ["hud.money"] = { text = "$103" }, ["hud.wave"] = { text = "Wave 1" } })
  lu.assertEquals(#ch.sent, 2)
  lu.assertEquals(ch.sent[1].seq, 1)
  lu.assertEquals(ch.sent[1].nodes["hud.money"].text, "$100")
  lu.assertEquals(ch.sent[2].seq, 2)
  lu.assertEquals(ch.sent[2].nodes["hud.money"].text, "$103")
  lu.assertNil(ch.sent[2].nodes["hud.wave"]) -- 未变不发
end

-- 无变化不发帧。
function TestEuiRouter.test_no_frame_when_nothing_changed()
  local ch = fake_channel()
  local r = eui.new(ch)
  r:push({ a = { text = "x" } })
  r:push({ a = { text = "x" } })
  lu.assertEquals(#ch.sent, 1)
end

-- 节点消失按 visible=false 通知；颜色/填充值按内容比较。
function TestEuiRouter.test_removed_node_and_deep_value_compare()
  local ch = fake_channel()
  local r = eui.new(ch)
  r:push({ a = { visible = true, color = { 1, 0, 0 } }, b = { visible = true } })
  r:push({ a = { visible = true, color = { 1, 0, 0 } } })
  lu.assertEquals(#ch.sent, 2)
  lu.assertEquals(ch.sent[2].nodes.b.visible, false)
  lu.assertNil(ch.sent[2].nodes.a)
end

-- 握手：client_ready 触发全量重同步。
function TestEuiRouter.test_client_ready_triggers_full_resync()
  local ch = fake_channel()
  local r = eui.new(ch)
  r:push({ a = { text = "x" }, b = { text = "y" } })
  r:client_ready()
  lu.assertEquals(#ch.sent, 2)
  lu.assertTrue(ch.sent[2].full)
  lu.assertEquals(ch.sent[2].nodes.a.text, "x")
  lu.assertEquals(ch.sent[2].nodes.b.text, "y")
end

-- 客户端哑镜像折叠信封：full 替换、增量合并。
function TestEuiRouter.test_client_mirror_folds_envelope()
  package.loaded["client.eui_render"] = nil
  local mirror = require("client.eui_render")
  local delivered = {}
  local channel = {
    OnClientEvent = { Connect = function(_, fn) delivered[#delivered + 1] = fn end },
  }
  mirror.connect(channel)
  local feed = delivered[1]
  feed({ seq = 1, nodes = { a = { text = "x" } } })
  feed({ seq = 2, nodes = { a = { text = "y" }, b = { visible = true } } })
  lu.assertEquals(mirror.applied.a.text, "y")
  lu.assertEquals(mirror.applied.b.visible, true)
  feed({ seq = 3, full = true, nodes = { c = { text = "z" } } })
  lu.assertNil(mirror.applied.a)
  lu.assertEquals(mirror.applied.c.text, "z")
end
