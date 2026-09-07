-- 无头验证：SE 桩 + 真适配层 + GameRootFull 跑服务端 main.lua。
-- 冒烟断言对齐 GDD 现实（docs/gdd/）：Pregame 手动开局、初始 100 资金、
-- 27 矿点、放置流（预览/非法/扣费）、采集、胜利/败北与重开代际。
-- 运行（仓库根）：lua5.4 tools/headless/run_server.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

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
assert(loadfile("server/main.lua"))()
local host = require("server.adapter.host")
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

real_print("== Pregame（手动开局，GDD 01 R2）")
stub.client_send({ kind = "client_ready" })
local full = stub.sent[#stub.sent]
check(full.kind == "full", "握手返回全量快照")
local t = full.nodes["panel/build/turret"]
check(t ~= nil, "全量快照含 panel/build/turret")
check(t and t.text == "Turret - $50", "按钮文本 'Turret - $50'（实际 " .. tostring(t and t.text) .. "）")
check(full.nodes["panel/build/relay"].text == "Relay - $10", "按钮文本 'Relay - $10'")
check(t and t.visible == false, "Pregame 按钮不可见")
check(#host.entity.all() == 28, "初始实体 = Core + 27 矿点 = 28（实际 " .. #host.entity.all() .. "）")
check(gs.mode:now() == "Pregame", "开局 mode=Pregame")
check(gs.money:now() == 0, "Pregame 资金未发（0）")
stub.client_send({ kind = "input", itype = "place", key = "turret" })
stub.steps(2)
check(bi.placing:now() == nil, "Pregame 收到 place 不置位")

real_print("== 开始对局")
stub.client_send({ kind = "input", itype = "start" })
stub.steps(3)
check(gs.mode:now() == "Playing", "start → Playing")
check(gs.money:now() == 100, "初始资金 100（实际 " .. tostring(gs.money:now()) .. "）")
check(last_state("panel/build/turret") and last_state("panel/build/turret").visible == true, "Playing 按钮可见")

real_print("== place 意图 + 预览")
stub.client_send({ kind = "input", itype = "place", key = "bogus" })
check(bi.placing:now() == nil, "未知 key 拒绝")
stub.client_send({ kind = "input", itype = "place", key = "turret" })
stub.steps(3)
check(bi.placing:now() ~= nil and bi.placing:now().key == "turret", "place(turret) → placing 置位")
check(host.eui.nodes["panel/cancel"].visible == true, "placing 时取消按钮可见")
stub.client_send({ kind = "input", itype = "hover", x = 8, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == false, "hover (8,0) 电网外 → 无效")
local fp = ring_unit("board/placement_footprint")
check(fp ~= nil, "放置预览圆已就地渲为单位")
stub.client_send({ kind = "input", itype = "hover", x = 3, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == true, "hover (3,0) 电网内 → 有效")

real_print("== tap 放置（GDD 04）")
stub.client_send({ kind = "input", itype = "tap", x = 8, z = 0 })
stub.steps(4)
check(entities_of("turret") == 0, "tap 无效点不放置")
check(bi.placing:now() ~= nil, "无效 tap 后仍在放置模式（R10）")
stub.client_send({ kind = "input", itype = "tap", x = 3, z = 0 })
stub.steps(4)
check(entities_of("turret") == 1, "tap (3,0) → turret 落位")
check(gs.money:now() == 50, "扣钱 50（实际 " .. tostring(gs.money:now()) .. "）")
check(bi.placing:now() == nil, "落位后 placing 清空")

real_print("== cancel 意图")
stub.client_send({ kind = "input", itype = "place", key = "relay" })
stub.steps(3)
check(bi.placing:now() ~= nil and bi.placing:now().key == "relay", "place(relay) 置位（$10 可买）")
stub.client_send({ kind = "input", itype = "cancel" })
stub.steps(3)
check(bi.placing:now() == nil, "cancel → placing 清空")

real_print("== 经济（GDD 02 R3：每 0.8s 每通电矿点 +1）")
stub.steps(24) -- 0.8s
local gained = gs.money:now() - 50
check(gained >= 3 and gained % 3 == 0, "3 个初始通电矿点按 3 的倍数进账（实际 +" .. tostring(gained) .. "）")

real_print("== Playing 中 restart 被拒")
local root_before = _G.bd.root
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(2)
check(_G.bd.root == root_before, "Playing 中客户端 restart 意图被拒（root 未变）")

real_print("== 矿点采空 → Victory（GDD 01 R4）")
_G.bd.mine_out(); stub.steps(3)
check(gs.mode:now() == "Victory", "mode=Victory")
check(gs.resources_remaining:now() == 0, "resources_remaining=0")
check(last_state("sidebar/victory").visible == true, "sidebar/victory 可见")

real_print("== Restart → 树重建 + reset gen=1")
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(2)
local root2 = _G.bd.root
check(root2 ~= root_before, "Restart 后 root 为新对象")
gs = root2.game_state; bi = root2.board_interactions
check(gs.mode:now() == "Pregame", "重开后回 Pregame")
check(#host.entity.all() == 28, "实体重建 = 28（实际 " .. #host.entity.all() .. "）")
local reset_msg
for i = #stub.sent, 1, -1 do
  if stub.sent[i].kind == "reset" then reset_msg = stub.sent[i] break end
end
check(reset_msg and reset_msg.gen == 1, "重开后 reset gen=1")
check(gs.core.entity._unit.Name == "1g1", "新 Core 单位名 '1g1'")

real_print("== Core 被毁 → 碎裂 2 秒 → GameOver（GDD 01 R5）")
stub.client_send({ kind = "input", itype = "start" }); stub.steps(3)
check(gs.mode:now() == "Playing", "重开后 start → Playing")
_G.bd.kill_core(); stub.steps(70) -- 2s 碎裂 + 余量
check(gs.mode:now() == "GameOver", "mode=GameOver（实际 " .. tostring(gs.mode:now()) .. "）")
check(last_state("sidebar/gameover") and last_state("sidebar/gameover").visible == true, "sidebar/gameover 可见")

real_print("== 第二次重开 gen=2")
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(2)
check(_G.bd.root ~= root2, "第二次重开：新 root")
check(#stub.sent > 0 and stub.sent[#stub.sent].kind == "reset" and stub.sent[#stub.sent].gen == 2, "reset gen=2")
check(#host.entity.all() == 28 and _G.bd.root.game_state.core.entity._unit.Name == "1g2", "28 实体、Core 名 '1g2'")
check(#stub.units_of(function(u) return u.Name:match("g1$") end) == 0, "g1 代单位全部销毁")

real_print(string.format("\n%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
