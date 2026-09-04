-- 无头验证：SE 桩 + 真适配层 + GameRootFull 跑服务端 main.lua，断言 #21 放置流。
-- 运行（仓库根）：lua5.4 tools/headless/run_server.lua
package.path = "./?.lua;./?/init.lua;vendor/spoke-lua/?.lua;vendor/spoke-lua/?/init.lua;" .. package.path

-- mock 同路径替换（与 tools/deploy.lua 的 swap 等价）
package.preload["examples.base_defence.host_mock"] = function() return require("src.adapter.host") end
package.preload["examples.base_defence.eui_mock"] = function() return require("src.adapter.eui") end
package.preload["examples.base_defence.input_mock"] = function() return require("src.adapter.input") end
package.preload["examples.host_mock"] = function() return require("src.adapter.host_base") end

local stub = require("tools.headless.se_stub")
local checks, fails = 0, 0
local real_print = print
local function check(cond, msg)
  checks = checks + 1
  real_print((cond and "  ok   " or "  FAIL ") .. msg)
  if not cond then fails = fails + 1 end
end

-- 静音业务/适配层日志（VERBOSE=1 打开）
local verbose = os.getenv("VERBOSE") == "1"
print = function(...) if verbose then real_print(...) end end
assert(loadfile("src/server/main.lua"))()
local host = require("src.adapter.host")
local root = _G.bd.root
local bi = root.board_interactions
local gs = root.game_state

local function entities_of(prefab)
  local n = 0
  for _, e in ipairs(host.entity.all()) do if e.prefab == prefab then n = n + 1 end end
  return n
end
local function last_state(path)
  for i = #stub.sent, 1, -1 do
    local m = stub.sent[i]
    if m.nodes and m.nodes[path] then return m.nodes[path] end
  end
end
local function ring_unit(path)
  local n = host.eui.nodes[path]
  return n and n._shape and n._shape.unit
end

real_print("== Pregame")
stub.client_send({ kind = "client_ready" })
local full = stub.sent[#stub.sent]
check(full.kind == "full", "握手返回全量快照")
local t = full.nodes["panel/build/turret"]
check(t ~= nil, "全量快照含 panel/build/turret")
check(t and t.text == "Turret $100", "按钮文本 'Turret $100'（实际 " .. tostring(t and t.text) .. "）")
check(t and t.visible == false, "Pregame 按钮不可见")
check(full.nodes["panel/cancel"].visible == false, "Pregame 取消不可见")
stub.client_send({ kind = "input", itype = "place", key = "turret" })
check(bi.placing:now() == nil, "Pregame 收到 place 不置位")

real_print("== 进入 Playing")
stub.steps(100)                     -- 3.3s，越过 AUTO_START_AT
check(gs.mode:now() == "Playing", "自动 start → Playing")
check(host.eui.nodes["panel/build/relay"].visible == true, "Playing 按钮可见")
check(last_state("panel/build/relay") and last_state("panel/build/relay").visible == true, "可见变化进了增量快照")
local money0 = gs.money:now()
check(money0 == 100, "初始 money=100（实际 " .. tostring(money0) .. "）")
check(host.eui.nodes["panel/build/turret"].color.r == 1, "turret $100 可买 → 白")
check(host.eui.nodes["panel/build/turret"].color.g == 1, "turret 可买 → 白(g)")

real_print("== place 意图 + 预览")
stub.client_send({ kind = "input", itype = "place", key = "bogus" })
check(bi.placing:now() == nil, "未知 key 拒绝")
stub.client_send({ kind = "input", itype = "place", key = "turret" })
check(bi.placing:now() == root.building_specs.turret, "place(turret) → placing 置位")
stub.step()
check(host.eui.nodes["panel/cancel"].visible == true, "placing 时取消按钮可见")
check(host.eui.nodes["panel/build/turret"].color.g < 1 and host.eui.nodes["panel/build/turret"].color.r == 1, "选中项 → 黄")
stub.client_send({ kind = "input", itype = "hover", x = 8, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == false, "hover (8,0) 电网外 → 无效")
local fp = ring_unit("board/placement_footprint")
check(fp ~= nil, "放置 footprint 圈已就地渲为 EffectUnit")
local fpc = last_state("board/placement_footprint")
check(fpc and fpc.fx == "fx_board_placement_footprint" and fpc.color.r == 1 and fpc.color.g == 0, "无效 → 快照带 fx 名 + 红色")
check(fp.EnableColor == nil and fp.DiffuseColor == nil, "服务端不再写 EffectUnit 颜色属性")
local power_rings = {}
for path in pairs(host.eui.nodes) do
  if path:match("^board/placement_power") and ring_unit(path) then power_rings[#power_rings + 1] = path end
end
check(#power_rings >= 1, "电网覆盖圈已渲（" .. table.concat(power_rings, ",") .. "）")
stub.client_send({ kind = "input", itype = "hover", x = 3, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == true, "hover (3,0) 电网内 → 有效")
fpc = last_state("board/placement_footprint")
check(fpc and fpc.color.g == 1 and fpc.color.r == 0, "有效 → 快照绿色")
check(fp and fp.Position.x == 3, "圈随触点移动 (x=3)")

real_print("== tap 放置")
stub.client_send({ kind = "input", itype = "tap", x = 8, z = 0 })
stub.steps(4)
check(entities_of("turret") == 0, "tap 无效点不放置")
check(bi.placing:now() ~= nil, "无效 tap 后仍在放置模式")
stub.client_send({ kind = "input", itype = "tap", x = 3, z = 0 })
stub.steps(4)
check(entities_of("turret") == 1, "tap (3,0) → turret 落位")
check(gs.money:now() <= money0 - 100 + 5, "扣钱 100（实际 " .. tostring(gs.money:now()) .. "）")
check(bi.placing:now() == nil, "落位后 placing 清空")
stub.step()
check(host.eui.nodes["panel/cancel"].visible == false, "取消按钮隐藏")
check(host.eui.nodes["panel/build/turret"].color.r < 1, "余额不足 → turret 灰")
check(host.eui.nodes["board/placement_footprint"] == nil, "footprint 节点已回收")

real_print("== cancel 意图")
stub.client_send({ kind = "input", itype = "place", key = "relay" })
check(bi.placing:now() == root.building_specs.relay, "place(relay) 置位（$50 可买）")
stub.client_send({ kind = "input", itype = "cancel" })
stub.steps(4)
check(bi.placing:now() == nil, "cancel → placing 清空")

real_print("== GM 面")
_G.bd.place("radar")
check(bi.placing:now() ~= nil or gs.money:now() < 75, "GM place 走同一入口")
_G.bd.cancel(); stub.steps(4)
_G.bd.placing(); _G.bd.status(); _G.bd.dump_nodes()

real_print(string.format("\n%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
