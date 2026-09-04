-- #23 真机集成：电网与辅助建筑（服务端注入）。
-- 运行：试玩中 `$CLI exec --platform server --file '<Windows 路径>'`，
-- 回读 `$CLI log grep "bd\]\[it3" --play-session <id>`。
-- 编排与 tools/headless/run_server.lua 切片 3 段同构：按 uptime 排程调 _G.bd GM，
-- 每步打 CHECK ok/FAIL；结束打 "IT3 DONE n checks, m failed"。
--
-- 剧本：钱 → 电网外放 radar 被拒 → relay (0,3) 外扩 → radar (0,6) 经 relay 成功 →
--       天线转 → 打死 relay → radar 断电变暗停转 → turret 受损 → repair 光束治疗。

local RunService = game:GetService("RunService")
local bd = _G.bd
local root = bd.root
local host = root.host
local gs = root.game_state
local bi = root.board_interactions

local checks, fails = 0, 0
local function check(cond, msg)
  checks = checks + 1
  print(string.format("[bd][it3] CHECK %s %s", cond and "ok" or "FAIL", msg))
  if not cond then fails = fails + 1 end
end
local function count(prefab)
  local n = 0
  for _, e in ipairs(host.entity.all()) do if e.prefab == prefab then n = n + 1 end end
  return n
end
local function shapes_with(prefix)
  local out = {}
  for _, sh in ipairs(host.eui.shapes()) do
    if sh.path:sub(1, #prefix) == prefix then out[#out + 1] = sh end
  end
  return out
end
local function building_of(key)
  for id, rec in pairs(root.pool._live_by_entity_id) do
    if rec.spec.key == key and rec.epoch.building.health.is_alive:now() then
      return id, rec.epoch.building, rec.entity
    end
  end
end
local function hover(x, z) host.input.intent_hover(x, z) end

local links0, relay_id, radar_b, radar_e, turret_id, turret_b, beam_path
local steps = {
  { 0.0, function()
    if gs.mode:now() ~= "Playing" then bd.start() end
    bd.money(1000)
    print("[bd][it3] START mode=" .. tostring(gs.mode:now()))
  end },
  { 0.5, function() bd.place("radar"); hover(0, 6) end },
  { 1.0, function()
    check(bi.placement_valid:now() == false, "(0,6) 电网外 → 无效")
    local pr = shapes_with("board/placement_power")
    check(#pr == 1, "电网覆盖圈仅 Core 一圈（" .. #pr .. "）")
    check(pr[1] and pr[1].effect == "official://effect/6044", "覆盖圈特效 6044")
    bd.tap(0, 6)
  end },
  { 1.5, function()
    check(count("radar") == 0, "电网外 tap 不放置")
    bd.cancel()
  end },
  { 2.0, function() hover(nil, nil) end },
  { 2.5, function() links0 = #shapes_with("board/power_links"); bd.place("relay"); hover(0, 3) end },
  { 3.0, function()
    check(bi.placement_valid:now() == true, "(0,3) 电网内 → 有效")
    bd.tap(0, 3)
  end },
  { 3.5, function() check(count("relay") == 1, "relay 落位"); hover(nil, nil) end },
  { 4.0, function()
    local links = shapes_with("board/power_links")
    check(#links == links0 + 1, "连线 +1（" .. links0 .. "→" .. #links .. "）")
    check(links[1] and links[1].effect == "official://effect/4506", "连线特效 4506")
    local id, b = building_of("relay")
    relay_id = id
    check(b and b.power.has_power:now() == true, "relay 有电")
    bd.place("radar"); hover(0, 6)
  end },
  { 4.5, function()
    check(bi.placement_valid:now() == true, "(0,6) 经 relay → 有效")
    check(#shapes_with("board/placement_power") == 2, "覆盖圈 Core+relay 两圈")
    bd.tap(0, 6)
  end },
  { 5.0, function() check(count("radar") == 1, "radar 落位 (0,6)"); hover(nil, nil) end },
  { 6.0, function()
    check(#shapes_with("board/power_links") == links0 + 2, "连线 +2")
    local _, b, e = building_of("radar")
    radar_b, radar_e = b, e
    check(b and b.power.has_power:now() == true, "radar 经 relay 有电")
    check(count("RadarDish") == 1, "天线实体存在")
    local dish
    for _, x in ipairs(host.entity.all()) do if x.prefab == "RadarDish" then dish = x end end
    check(dish and dish.rotation > 0, string.format("天线旋转累加中 rot=%.2f", dish and dish.rotation or -1))
    local c = radar_e._unit.ModelColor1
    print(string.format("[bd][it3] radar 有电色 (%s,%s,%s)", tostring(c.r), tostring(c.g), tostring(c.b)))
    bd.damage(relay_id, 999)
  end },
  { 7.0, function()
    check(radar_b.power.has_power:now() == false, "relay 死 → radar 断电")
    local c = radar_e._unit.ModelColor1
    print(string.format("[bd][it3] radar 断电色 (%s,%s,%s)", tostring(c.r), tostring(c.g), tostring(c.b)))
    check(c.r == 54 and c.b == 80, "断电 tint 0.35 → (54,54,80)")
    check(count("RadarDish") == 0, "断电 → 天线销毁")
    check(#shapes_with("board/power_links") == links0, "两条连线随 relay 消失")
    bd.place("turret"); hover(3, 0)
  end },
  { 7.5, function() bd.tap(3, 0) end },
  { 8.0, function()
    check(count("turret") == 1, "turret 落位 (3,0)")
    hover(nil, nil)
    turret_id, turret_b = building_of("turret")
    bd.damage(turret_id, 10)
    check(turret_b.health.hp_fraction:now() < 1, "turret 受损")
    bd.place("repair"); hover(0, -3)
  end },
  { 8.5, function() bd.tap(0, -3) end },
  { 9.0, function() check(count("repair") == 1, "repair 落位 (0,-3)"); hover(nil, nil) end },
  { 9.5, function()
    local beams = shapes_with("repair_")
    check(#beams == 1 and beams[1].visible == true, "维修光束可见")
    beam_path = beams[1] and beams[1].path
  end },
  { 13.0, function()
    check(turret_b.health.hp_fraction:now() >= 1, string.format("turret 修满 hp=%.2f", turret_b.health.hp_fraction:now()))
    local n = beam_path and host.eui.nodes[beam_path]
    check(n and n.visible == false, "修满 → 光束隐藏")
    bd.buildings(); bd.dump_shapes(); bd.status()
    print(string.format("[bd][it3] IT3 DONE %d checks, %d failed", checks, fails))
  end },
}

local t, i = 0, 1
local conn
conn = RunService.Heartbeat:Connect(function(dt)
  t = t + dt
  while steps[i] and t >= steps[i][1] do
    local ok, err = pcall(steps[i][2])
    if not ok then print("[bd][it3] STEP ERROR @" .. steps[i][1] .. ": " .. tostring(err)) end
    i = i + 1
  end
  if not steps[i] then conn:Disconnect() end
end)
print("[bd][it3] 已排程 " .. #steps .. " 步")
