-- 无头验证：SE 桩 + 真适配层 + GameRootFull 跑服务端 main.lua，断言 #21 放置流。
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

-- ═══ #26 切片 4：波次与经济 ═══
local wd = root.wave_director
local function resource_at(x, z)
  for _, r in ipairs(root.resources) do
    local p = r.entity.position
    if p.x == x and p.z == z then return r end
  end
end
local function alive_enemies()
  local list = {}
  for _, en in ipairs(root.enemies) do
    if en.health and en.health.is_alive:now() then list[#list + 1] = en end
  end
  return list
end
-- 推进到条件成立（上限 max_ticks），返回用掉的 tick 数或 nil
local function step_until(pred, max_ticks)
  for i = 1, max_ticks do
    stub.step()
    if pred() then return i end
  end
  return nil
end

real_print("== 切片 4：矿点布局与供电")
check(#root.resources == 6, "6 个矿点（4 内 + 2 外）")
local inner = resource_at(2.5, 2.5)
local outer = resource_at(-7, 0)
check(inner and inner.power.has_power:now() == true, "内圈矿点 (2.5,2.5) 经 Core 有电")
check(outer and outer.power.has_power:now() == false, "外圈矿点 (-7,0) 距 Core 7 > 4 → 无电")
check(outer and outer.remaining:now() == 30, "外圈矿点未采：remaining=30")
check(inner and inner.remaining:now() < 20, "内圈矿点已在采：remaining<20（实际 " .. tostring(inner and inner.remaining:now()) .. "）")
local inner_bar = host.eui.nodes["resource_" .. inner.entity.id .. "_hp"]
check(inner_bar and inner_bar.visible == true and inner_bar.fill < 1, "内圈矿点血条可见且 fill<1")
check(gs.resources_remaining:now() == 6, "resources_remaining=6")

real_print("== 切片 4：relay 外扩到外圈矿点 → 采集 → money 增长")
_G.bd.money(1000)
_G.bd.place("relay")
stub.client_send({ kind = "input", itype = "hover", x = -3.5, z = 0 })
stub.steps(3)
check(bi.placement_valid:now() == true, "(-3.5,0) 电网内 → 有效")
stub.client_send({ kind = "input", itype = "tap", x = -3.5, z = 0 })
stub.steps(4)
check(entities_of("relay") == 1, "relay 落位 (-3.5,0)")
hover_clear(); stub.steps(10)
check(outer.power.has_power:now() == true, "外圈矿点经 relay 通电")
local money_before, outer_before = gs.money:now(), outer.remaining:now()
stub.steps(62) -- collect_time 2s = 60 tick + 余量
check(outer.remaining:now() == outer_before - 1, "外圈矿点 2s 后 remaining -1")
check(gs.money:now() > money_before, "money 增长（" .. money_before .. " → " .. gs.money:now() .. "）")
local outer_bar = host.eui.nodes["resource_" .. outer.entity.id .. "_hp"]
check(outer_bar and outer_bar.visible == true, "外圈矿点血条随采集出现")
check(gs.collect_rate:now() > 0, "collect_rate>0")

real_print("== 切片 4：矿点采空消失")
local victim = resource_at(-2.5, -2.5)
local victim_id = victim.entity.id
victim.remaining:set(1)
stub.steps(62)
check(victim.remaining:now() == 0, "remaining 归零")
check(host.entity.by_id[victim_id] == nil, "采空 → 实体销毁")
check(gs.resources_remaining:now() == 5, "resources_remaining=5")
local vb = host.eui.nodes["resource_" .. victim_id .. "_hp"]
check(vb == nil or vb.visible == false, "采空 → 血条隐藏/回收")

real_print("== 切片 4：Core 受击闪红")
local core_e = gs.core.entity
gs.core.health:damage(1)
stub.step()
local c = core_e._unit.ModelColor1
check(c.r == 255 and c.g == 0 and c.b == 0, "受击 → ModelColor1 (255,0,0)")
stub.steps(5) -- 0.1s = 3 tick 后恢复
c = core_e._unit.ModelColor1
check(c.r == 255 and c.g == 214 and c.b == 0, "0.1s 后恢复底色 (255,214,0)（实际 " .. c.r .. "," .. c.g .. "," .. c.b .. "）")

real_print("== 切片 4：第 1 波（阶梯 5 只 / 1s / enemy）")
_G.bd.lull(5) -- 下一波起平静期 5s
local w = wd.wave:now()
check(w.number == 1 and w.starts_in > 0, "仍在第 1 波平静期 starts_in=" .. w.starts_in)
local used = step_until(function() return wd.wave:now().starts_in == 0 end, 1000)
check(used ~= nil, "第 1 波来袭（等了 " .. tostring(used) .. " tick）")
stub.steps(2)
check(gs.collect_rate:now() == 0, "来袭期间采集暂停 collect_rate=0")
local cfg1 = wd:wave_enemy_config()
check(cfg1.enemy_count == 5 and cfg1.spawn_interval == 1 and cfg1.prefab == "enemy", "第 1 波配置 5/1s/enemy")
stub.steps(4 * 30 + 20)
local e1 = alive_enemies()
check(#e1 == 5, "第 1 波 5 只出齐（实际 " .. #e1 .. "）")
check(e1[1] and e1[1].prefab == "enemy" and e1[1].entity._unit.Scale.x == 0.8, "enemy 视觉 scale 0.8")
_G.bd.enemies()
_G.bd.kill_enemies()
-- 清场判定 = done_spawning ∧ remaining==0；最后一只出生后还要等一个 spawn_interval 才置 done
used = step_until(function() return wd.wave:now().number == 2 end, 60)
w = wd.wave:now()
check(used and w.starts_in == 5, "清场 → 第 2 波倒计时 5s（number=" .. w.number .. " starts_in=" .. w.starts_in .. "，等 " .. tostring(used) .. " tick）")
check(gs.collect_rate:now() > 0, "平静期采集恢复")

real_print("== 切片 4：第 2 波（阶梯 6 只 / 0.9s）出怪间隔与配置一致")
used = step_until(function() return wd.wave:now().starts_in == 0 end, 200)
check(used ~= nil and used <= 5 * 30 + 3, "第 2 波 5s 后来袭（" .. tostring(used) .. " tick）")
local cfg2 = wd:wave_enemy_config()
check(cfg2.enemy_count == 6 and math.abs(cfg2.spawn_interval - 0.9) < 1e-9 and cfg2.prefab == "enemy", "第 2 波配置 6/0.9s/enemy")
-- 记录每只出生的 tick，验证间隔
local spawn_ticks, last_n = {}, 0
for i = 1, 5 * 27 + 20 do
  stub.step()
  local n = #alive_enemies()
  if n > last_n then spawn_ticks[#spawn_ticks + 1] = i; last_n = n end
end
check(#spawn_ticks == 6, "第 2 波 6 只出齐（实际 " .. #spawn_ticks .. "）")
local gaps_ok = true
for i = 2, #spawn_ticks do
  local gap = spawn_ticks[i] - spawn_ticks[i - 1]
  if gap < 26 or gap > 28 then gaps_ok = false end
end
check(gaps_ok, "出怪间隔 0.9s ≈27 tick（" .. table.concat(spawn_ticks, ",") .. "）")
_G.bd.kill_enemies()
check(step_until(function() return wd.wave:now().number == 3 end, 60) ~= nil, "→ 第 3 波")

real_print("== 切片 4：第 3 波换档 enemy_heavy")
used = step_until(function() return wd.wave:now().starts_in == 0 end, 200)
local cfg3 = wd:wave_enemy_config()
check(cfg3.enemy_count == 4 and cfg3.prefab == "enemy_heavy" and cfg3.max_hp == 30 and math.abs(cfg3.spawn_interval - 0.8) < 1e-9, "第 3 波配置 4/0.8s/enemy_heavy/hp30")
stub.steps(3 * 24 + 20)
local e3 = alive_enemies()
check(#e3 == 4, "第 3 波 4 只出齐")
check(e3[1] and e3[1].prefab == "enemy_heavy" and e3[1].max_hp == 30, "敌人实例 prefab=enemy_heavy max_hp=30")
check(e3[1] and e3[1].entity._unit.Scale.x == 1.3 and e3[1].entity._unit.ModelColor1.b == 140, "enemy_heavy 视觉 scale 1.3 / 底色 b=140")
_G.bd.kill_enemies()
check(step_until(function() return wd.wave:now().number == 4 end, 60) ~= nil, "→ 第 4 波")

real_print("== 切片 4：阶梯任意波号有定义")
local L = wd._waves
check(L[6].enemy.prefab == "enemy_boss" and L[6].enemy_count == 3, "第 6 波 enemy_boss ×3")
check(L[12].enemy_count == 8 and L[12].spawn_interval == 0.5, "第 12 波数量封顶 8 / 间隔下限 0.5")
check(L[99] ~= nil, "第 99 波仍有定义")
_G.bd.wave(6); _G.bd.resources()

real_print("== GM 面")
_G.bd.place("radar")
check(bi.placing:now() ~= nil or gs.money:now() < 75, "GM place 走同一入口")
_G.bd.cancel(); stub.steps(4)
_G.bd.placing(); _G.bd.status(); _G.bd.dump_nodes()


-- ── 切片 5：胜负与重开（#28）────────────────────────────────────────────
local function count_keys(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function last_sent() return stub.sent[#stub.sent] end
local initial_node_count = count_keys(full.nodes)

real_print("== 切片 5：Playing 中 restart 被拒 + panel/restart 隐藏")
check(gs.mode:now() == "Playing", "前置：仍在 Playing")
check(last_state("panel/restart").visible == false, "panel/restart 初始隐藏")
local root_before = _G.bd.root
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(2)
check(_G.bd.root == root_before, "Playing 中客户端 restart 意图被拒（root 未变）")

real_print("== 切片 5：矿点采空 → Victory")
_G.bd.mine_out(); stub.steps(3)
check(gs.mode:now() == "Victory", "mode=Victory")
check(gs.resources_remaining:now() == 0, "resources_remaining=0")
check(last_state("sidebar/victory").visible == true, "sidebar/victory 可见")
check(last_state("panel/restart").visible == true, "panel/restart 终局可见")
check(last_state("hud/mode").text == "Mode: Victory", "hud/mode 文本 Mode: Victory")

real_print("== 切片 5：Restart → 树重建 + reset 全量 + gen 后缀")
local old_units = stub.units_of(function(u) return u.Name == "1" end)
check(#old_units == 1, "重开前 Core 单位名 '1'")
local sent_before = #stub.sent
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(1)
local root2 = _G.bd.root
check(root2 ~= root_before, "Restart 后 root 为新对象")
gs = root2.game_state; bi = root2.board_interactions; wd = root2.wave_director
check(gs.mode:now() == "Pregame", "重开后回 Pregame")
check(#host.entity.all() == 7, "实体重建 = 7（Core + 6 矿点，实际 " .. #host.entity.all() .. "）")
check(count_keys(host.eui.nodes) == initial_node_count, "节点数与首局一致（" .. count_keys(host.eui.nodes) .. " vs " .. initial_node_count .. "）")
local reset_msg = stub.sent[sent_before + 1]
check(reset_msg and reset_msg.kind == "reset" and reset_msg.gen == 1, "重开后首条消息 kind=reset gen=1")
check(reset_msg and count_keys(reset_msg.nodes) == initial_node_count, "reset 全量节点数等于当前树")
check(host.eui.generation == 1 and host.entity.generation == 1, "eui/entity generation 同步 = 1")
check(#stub.units_of(function(u) return u.Name == "1" end) == 0 and old_units[1]._destroyed, "旧单位已 Destroy（名 '1' 不复存在）")
check(gs.core.entity._unit.Name == "1g1", "新 Core 单位名 '1g1'")
check(host.entity.unit_name(1, 0) == "1" and host.entity.unit_name(5, 2) == "5g2", "unit_name 约定：首局裸 id，重开后 <id>g<gen>")
check(last_state("panel/restart").visible == false and last_state("sidebar/pregame").visible == true, "重开后 panel/restart 隐藏、sidebar/pregame 可见")
check(_G.bd.root == root2, "GM root 已指向新树")

real_print("== 切片 5：重开后 3s 自动 Playing + 放置可用")
stub.steps(3 * 30 + 2)
check(gs.mode:now() == "Playing", "重开后自动 Playing")
check(gs.money:now() == 100, "金钱回到 start_money 100（start_game 时重置）")
_G.bd.place("turret"); stub.steps(1)
check(bi.placing:now() ~= nil, "重开后 GM place 置位")
stub.client_send({ kind = "input", itype = "tap", x = 3, z = 0 }); stub.steps(4)
check(entities_of("turret") == 1, "重开后放下 turret（新树的 board_interactions）")
check(host.entity.by_id[8] and host.entity.by_id[8]._unit.Name == "8g1", "新建筑单位名带 g1 后缀")

real_print("== 切片 5：Core 被毁 → GameOver → 再重开 gen=2")
_G.bd.kill_core(); stub.steps(3)
check(gs.mode:now() == "GameOver", "mode=GameOver")
check(last_state("sidebar/gameover").visible == true and last_state("panel/restart").visible == true, "sidebar/gameover + panel/restart 可见")
check(last_state("hud/mode").text == "Mode: GameOver", "hud/mode 文本 Mode: GameOver")
stub.client_send({ kind = "input", itype = "restart" }); stub.steps(1)
check(_G.bd.root ~= root2 and last_sent().kind == "reset" and last_sent().gen == 2, "第二次重开：新 root + reset gen=2")
check(#host.entity.all() == 7 and _G.bd.root.game_state.core.entity._unit.Name == "1g2", "第二次重开 7 实体、Core 名 '1g2'")
check(#stub.units_of(function(u) return u.Name:match("g1$") end) == 0, "g1 代单位全部销毁")
check(_G.bd.root.game_state.mode:now() == "Pregame", "第二次重开回 Pregame")
_G.bd.status()

real_print(string.format("\n%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
