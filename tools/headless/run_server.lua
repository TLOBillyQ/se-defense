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
check(fp ~= nil, "放置 footprint 圈已就地渲为单位")
check(fp and fp.RenderMeshId == "official://mesh/59273", "footprint 渲为圆盘 WorldUnit（可变色）")
check(fp and fp.ModelColor1 and fp.ModelColor1.r == 255 and fp.ModelColor1.g == 0, "无效 → 圆盘红（ModelColor1）")
-- 注：节点注册在 set_ring 之前时首帧会带 text/visible 进快照（客户端 recipe=none，无害），
-- 此处只断言颜色不再经快照下发。
local fpc = last_state("board/placement_footprint")
check(fpc == nil or fpc.fx == nil, "环颜色不再经快照下发")
local power_rings = {}
for path in pairs(host.eui.nodes) do
  if path:match("^board/placement_power") and ring_unit(path) then power_rings[#power_rings + 1] = path end
end
check(#power_rings >= 1, "电网覆盖圈已渲（" .. table.concat(power_rings, ",") .. "）")
stub.client_send({ kind = "input", itype = "hover", x = 3, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == true, "hover (3,0) 电网内 → 有效")
check(fp and fp.ModelColor1.g == 255 and fp.ModelColor1.r == 0, "有效 → 圆盘绿")
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

-- ═══ #23 切片 3：电网与辅助建筑 ═══
local function shapes_with(prefix)
  local out = {}
  for _, sh in ipairs(host.eui.shapes()) do
    if sh.path:sub(1, #prefix) == prefix then out[#out + 1] = sh end
  end
  return out
end
local function building_of(prefab)
  for id, rec in pairs(root.pool._live_by_entity_id) do
    if rec.spec.key == prefab and rec.epoch.building.health.is_alive:now() then return id, rec.epoch.building, rec.entity end
  end
end
local function hover_clear() stub.client_send({ kind = "input", itype = "hover" }); stub.steps(3) end

real_print("== 切片 3：电网外放置被拒")
_G.bd.money(1000)
_G.bd.place("radar")
stub.client_send({ kind = "input", itype = "hover", x = 0, z = 6 })
stub.steps(3)
check(bi.placement_valid:now() == false, "(0,6) 距 Core 6 > provide_range 4 → 无效")
local pr = shapes_with("board/placement_power")
check(#pr == 1, "电网覆盖圈仅 Core 一圈（实际 " .. #pr .. "）")
check(pr[1] and pr[1].effect == "official://effect/6044", "覆盖圈特效 6044（实际 " .. tostring(pr[1] and pr[1].effect) .. "）")
check(pr[1] and pr[1].radius == 4, "Core 覆盖圈半径 4")
stub.client_send({ kind = "input", itype = "tap", x = 0, z = 6 })
stub.steps(4)
check(entities_of("radar") == 0, "电网外 tap → 不放置")
_G.bd.cancel(); hover_clear()

real_print("== 切片 3：Relay 外扩")
stub.steps(10)
local links0 = #shapes_with("board/power_links") -- 基线：资源点也是 PowerNode，Core 范围内的有连线
_G.bd.place("relay")
stub.client_send({ kind = "input", itype = "hover", x = 0, z = 3 })
stub.steps(3)
check(bi.placement_valid:now() == true, "(0,3) 电网内 → 有效")
stub.client_send({ kind = "input", itype = "tap", x = 0, z = 3 })
stub.steps(4)
check(entities_of("relay") == 1, "relay 落位 (0,3)")
hover_clear(); stub.steps(10)
local links = shapes_with("board/power_links")
check(#links == links0 + 1, "空闲态电力连线新增 relay→Core 一条（基线 " .. links0 .. " → " .. #links .. "）")
check(links[1] and links[1].effect == "official://effect/4506", "连线特效 4506")
check(links[1] and links[1].visible == true, "连线可见")
local relay_id, relay_b = building_of("relay")
check(relay_b and relay_b.power.has_power:now() == true, "relay 有电")

real_print("== 切片 3：电网内放置成功（经 relay）")
_G.bd.place("radar")
stub.client_send({ kind = "input", itype = "hover", x = 0, z = 6 })
stub.steps(3)
check(bi.placement_valid:now() == true, "(0,6) 距 relay 3 < 4 → 有效")
pr = shapes_with("board/placement_power")
check(#pr == 2, "电网覆盖圈 Core + relay 两圈（实际 " .. #pr .. "）")
stub.client_send({ kind = "input", itype = "tap", x = 0, z = 6 })
stub.steps(4)
check(entities_of("radar") == 1, "radar 落位 (0,6)")
hover_clear(); stub.steps(10)
check(#shapes_with("board/power_links") == links0 + 2, "连线再增一条 radar→relay")
local radar_id, radar_b, radar_e = building_of("radar")
check(radar_b and radar_b.power.has_power:now() == true, "radar 经 relay 有电")

real_print("== 切片 3：雷达天线")
check(entities_of("RadarDish") == 1, "天线实体已生成")
local dish
for _, e in ipairs(host.entity.all()) do if e.prefab == "RadarDish" then dish = e end end
check(dish and dish._unit.Position.y == 1.45 and dish._unit.Scale.x == 1.6, "天线=横杆架在底座顶（y=1.45）")
local rot0 = dish and dish._unit.Rotation and dish._unit.Rotation.y or 0
stub.steps(15)
local rot1 = dish and dish._unit.Rotation.y or 0
check(rot1 ~= rot0 and rot1 >= 0 and rot1 < 360, string.format("天线绕 Y 旋转（%.1f° → %.1f°，归一 [0,360)）", rot0, rot1))
local base = radar_e._unit.ModelColor1
check(base and base.r == 153 and base.g == 153 and base.b == 230, "radar 有电 = 底色 (153,153,230)")

real_print("== 切片 3：relay 被毁 → 断电反馈")
_G.bd.damage(relay_id, 999)
stub.steps(3)
check(relay_b.health.is_alive:now() == false, "relay 死亡")
stub.steps(12) -- 0.15s debounce + 余量
check(radar_b.power.has_power:now() == false, "radar 断电")
local dim = radar_e._unit.ModelColor1
check(dim and dim.r == 54 and dim.b == 80, "断电 tint 0.35 → ModelColor1 (54,54,80)（实际 " .. tostring(dim and dim.r) .. "）")
check(entities_of("RadarDish") == 0, "断电 → 天线停转销毁")
check(#shapes_with("board/power_links") == links0, "relay→Core、radar→relay 两条连线随 relay 消失")

real_print("== 切片 3：Repair 光束 + 治疗")
local turret_id, turret_b = building_of("turret")
_G.bd.damage(turret_id, 10)
check(turret_b.health.hp_fraction:now() < 1, "turret 受损 hp<1")
_G.bd.place("repair")
stub.client_send({ kind = "input", itype = "hover", x = 0, z = -3 })
stub.steps(3)
stub.client_send({ kind = "input", itype = "tap", x = 0, z = -3 })
stub.steps(4)
check(entities_of("repair") == 1, "repair 落位 (0,-3)，距 turret 4.2 < range 5")
hover_clear(); stub.steps(5)
local beams = shapes_with("repair_")
check(#beams == 1 and beams[1].kind == "line", "维修光束 line 已渲")
check(beams[1] and beams[1].visible == true, "维修中光束可见")
check(beams[1] and beams[1].effect == "official://effect/4506", "光束特效 4506")
local beam_node = host.eui.nodes[beams[1].path]
check(beam_node._shape.line.a.Position.y == 0.8, "光束离地 0.8")
stub.steps(90) -- 3s × repair_rate 5 ≥ 10 hp
check(turret_b.health.hp_fraction:now() >= 1, "turret 修满")
check(beam_node.visible == false and beam_node._shape.line.fx.Visible == false, "修满 → 光束隐藏")
_G.bd.buildings(); _G.bd.dump_shapes()

real_print("== GM 面")
_G.bd.place("radar")
check(bi.placing:now() ~= nil or gs.money:now() < 75, "GM place 走同一入口")
_G.bd.cancel(); stub.steps(4)
_G.bd.placing(); _G.bd.status(); _G.bd.dump_nodes()

real_print(string.format("\n%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
