-- #30 真机整局验收（服务端注入）。打磨阶段每次改动的回归门；由 tools/integration/run_full.sh 编排。
-- 单独运行：试玩中 `$CLI exec --platform server --file '<Windows 路径>'`，
-- 回读 `$CLI log grep "bd\]\[itf" --play-session <id>`。
--
-- 骨架 = slice4/5 的条件驱动步进器（每步 do → 等 until / 超时 → on_done 断言）。
-- 与分片脚本的区别：客户端真点击与截图由外部编排器代劳——本脚本打 `WAIT <动作;动作>`
-- 后停下等 `_G.bd_it.go()`，编排器看到 WAIT 行就做动作再放行（run_full.sh 的 dispatch）。
--   client:button <path>   客户端 _G.bd_client.tap_button(path)   （真 EUIButton 点击）
--   client:board <x> <z>   客户端 _G.bd_client.tap_board(x, z)    （真捕获层 SimulateTap）
--   shot:<name>            editor-cli 截图 → docs/acceptance/<name>.png
-- 无编排器时 WAIT 会在 timeout 后记 FAIL 并继续（脚本仍能跑完 GM 能做的部分）。
--
-- 剧本（一整局 + 重开后半局）：
--   Pregame → 自动 Playing → money=1000 → 客户端点按钮+点棋盘放 relay/turret/radar/repair
--   → 3 波（配置=阶梯、出齐即清场，第 3 波 enemy_heavy）→ 至少一个矿点自然采空
--   → GM mine_out → Victory [截图] → 客户端点 Restart → gen=1 Pregame [截图]
--   → 自动 Playing → 客户端放 turret（单位名 <id>g1）→ GM kill_core → GameOver [截图]
--   → 客户端点 Restart → gen=2 Pregame。
-- 结束打 "ITF DONE n checks, m failed"。bd.root 每次重开都换对象，全程经访问器取。

local World = game:GetService("World")
local RunService = game:GetService("RunService")
local bd = _G.bd
local function root() return bd.root end
local function gs() return root().game_state end
local function host() return root().host end
local function wd() return root().wave_director end
local function node(path) return host().eui.nodes[path] end

local checks, fails = 0, 0
local function log(fmt, ...) print("[bd][itf] " .. string.format(fmt, ...)) end
local function check(cond, msg)
  checks = checks + 1
  log("CHECK %s %s", cond and "ok" or "FAIL", msg)
  if not cond then fails = fails + 1 end
end
local function count(prefab)
  local n = 0
  for _, e in ipairs(host().entity.all()) do if e.prefab == prefab then n = n + 1 end end
  return n
end
local function node_count()
  local n = 0
  for _ in pairs(host().eui.nodes) do n = n + 1 end
  return n
end
local function hp_bars()
  local n = 0
  for path in pairs(host().eui.nodes) do if path:match("_hp$") then n = n + 1 end end
  return n
end
local function has_node_prefix(prefix)
  for path in pairs(host().eui.nodes) do if path:sub(1, #prefix) == prefix then return true end end
  return false
end
local function alive_enemies()
  local list = {}
  for _, en in ipairs(root().enemies) do
    if en.health and en.health.is_alive:now() then list[#list + 1] = en end
  end
  return list
end
local function assaulting() return wd().wave:now().starts_in == 0 end

-- 全局波次记录（运行器每帧喂）：不依赖当前在哪一步，来袭撞上放置也能记全。
-- number → { cfg, ladder, front, ids={id=true}, seen, sample={prefab,max_hp} }
-- root.enemies 会保留上一波的尸体，故用全局 id 集：首次出现在第 n 波来袭期间的 id 归第 n 波。
local wave_stats = {}
local known_enemy_ids = {}
local function track_waves()
  if not assaulting() then return end
  local w = wd().wave:now()
  local ws = wave_stats[w.number]
  if not ws then
    ws = { cfg = wd():wave_enemy_config(), ladder = wd()._waves[w.number], front = w.front, seen = 0 }
    wave_stats[w.number] = ws
  end
  for _, en in ipairs(root().enemies) do
    local id = en.entity and en.entity.id
    if id and not known_enemy_ids[id] then
      known_enemy_ids[id] = true
      ws.seen = ws.seen + 1
      ws.sample = ws.sample or { prefab = en.prefab, max_hp = en.max_hp }
    end
  end
end
-- 清场只在本波出齐之后（否则记录不全）
local function spawn_complete()
  local ws = wave_stats[wd().wave:now().number]
  return ws ~= nil and ws.seen >= ws.cfg.enemy_count
end
local function near(a, b, tol) return math.abs(a - b) <= tol end
local function building_by_key(key)
  for id, rec in pairs(root().pool._live_by_entity_id) do
    if rec.spec and rec.spec.key == key and rec.epoch and rec.epoch.building then return id, rec end
  end
end

-- ── 步骤定义 ────────────────────────────────────────────────────────
-- { name, do=fn, until=fn→bool, timeout=s|timeout_fn, poll=fn(t), auto_clear=bool, on_done=fn(ok) }
local steps = {}
local function step(t) steps[#steps + 1] = t end

-- 编排器握手：打 WAIT 后等 go()
local go_flag = false
_G.bd_it = {
  go = function() go_flag = true; log("GO") end,
}
local function wait_step(actions, timeout)
  step({ name = "WAIT " .. actions, ["do"] = function() go_flag = false; log("WAIT %s", actions) end,
    ["until"] = function() return go_flag end, timeout = timeout or 90,
    on_done = function(ok) if not ok then check(false, "编排器未在时限内响应 WAIT " .. actions) end end })
end

local root0, gen_after_victory
local placed_cost = 0

-- ── 第一局 ─────────────────────────────────────────────────────────
step({ name = "START", ["do"] = function()
  root0 = root()
  local mode = gs().mode:now()
  log("START mode=%s gen=%d entities=%d nodes=%d money=%s", tostring(mode),
    host().eui.generation, #host().entity.all(), node_count(), tostring(gs().money:now()))
  check(mode == "Pregame" or mode == "Playing", "注入时 mode ∈ {Pregame, Playing}（实际 " .. tostring(mode) .. "）")
  check(host().eui.generation == 0, "首局 gen=0")
  check(#host().entity.all() == 7, "开局 7 实体（Core + 6 矿点）")
  check(count("Resource") == 6, "6 个 Resource 实体")
  check(hp_bars() == 7, "血条节点 7 条")
  check(gs().core.entity._unit.Name == "1", "首局 Core 单位名 '1'")
  check(node("panel/restart") and node("panel/restart").visible == false, "panel/restart 隐藏")
end, ["until"] = function() return gs().mode:now() == "Playing" end, timeout = 6,
  on_done = function(ok)
    check(ok, "自动开局 → Playing")
    check(gs().money:now() >= 100, "开局 money ≥ 100（注入时可能已开采，实际 " .. tostring(gs().money:now()) .. "）")
    check(node("panel/build/turret").visible == true, "Playing 放置按钮可见")
    bd.lull(6)      -- 第 2 波起平静期 6s（首波倒计时不受影响）
    bd.money(1000)  -- 四种建筑各放一座需 305，GM 直接给足
  end })

-- 四种建筑各放一座，全走客户端真点击（按钮 + 棋盘）。位置绕 Core 3.5 格、避开内圈矿点 (±2.5,±2.5)。
local PLACEMENTS = {
  { key = "relay",  x = 3.5,  z = 0 },
  { key = "turret", x = 0,    z = 3.5 },
  { key = "radar",  x = -3.5, z = 0 },
  { key = "repair", x = 0,    z = -3.5 },
}
for _, p in ipairs(PLACEMENTS) do
  wait_step(string.format("client:button panel/build/%s; client:board %g %g", p.key, p.x, p.z))
  step({ name = "落位 " .. p.key, ["until"] = function() return count(p.key) == 1 end, timeout = 5, auto_clear = true,
    on_done = function(ok)
      local id, rec = building_by_key(p.key)
      local pos = rec and rec.entity.position
      check(ok and pos and near(pos.x, p.x, 0.3) and near(pos.z, p.z, 0.3),
        string.format("客户端点击放 %s @(%g,%g)（实际 %s）", p.key, p.x, p.z,
          pos and string.format("(%.2f,%.2f)", pos.x, pos.z) or "未落位"))
      if rec then
        placed_cost = placed_cost + (rec.spec.cost or 0)
        local b = rec.epoch.building
        check(b.power == nil or b.power.has_power:now() == true, p.key .. " 通电")
        check(node("building_" .. id .. "_hp") ~= nil, p.key .. " 血条节点存在")
        check(rec.entity._unit and rec.entity._unit.Name == tostring(id), p.key .. " 单位名 '" .. id .. "'")
      end
      check(root().board_interactions.placing:now() == nil, "落位后退出放置模式")
    end })
end

step({ name = "四建筑就位", ["do"] = function()
  -- 放置期间内圈矿点持续采集，只能断下界：money ≥ 1000 − 造价合计
  check(placed_cost == 305 and gs().money:now() >= 1000 - placed_cost,
    string.format("造价合计 %d（=305）且 money ≥ 1000 − 305（实际 %s）", placed_cost, tostring(gs().money:now())))
  local outer_powered = 0
  for _, r in ipairs(root().resources) do
    if math.abs(r.entity.position.x) == 7 and r.power.has_power:now() then outer_powered = outer_powered + 1 end
  end
  check(outer_powered == 1, "relay (3.5,0) 使外圈矿点 (7,0) 通电（外圈通电数 " .. outer_powered .. "）")
  bd.buildings()
end })

-- 三波：第 n 波出齐（记录由运行器全程维护）→ 清场 → 对照阶梯。turret 会击杀敌人，按 id 计数不受影响。
local function wave_round(n)
  step({ name = "第 " .. n .. " 波出齐", auto_clear = true,
    ["until"] = function() local ws = wave_stats[n]; return ws ~= nil and ws.seen >= ws.cfg.enemy_count end,
    timeout = 45,
    on_done = function(ok)
      local ws = wave_stats[n]
      check(ok and ws ~= nil, string.format("第 %d 波来袭并出齐（%s）", n, ws and (ws.seen .. "/" .. ws.cfg.enemy_count .. " front=" .. tostring(ws.front)) or "未见"))
      if not ws then return end
      check(ws.cfg.enemy_count == ws.ladder.enemy_count and ws.cfg.spawn_interval == ws.ladder.spawn_interval
        and ws.cfg.prefab == ws.ladder.enemy.prefab and ws.cfg.max_hp == ws.ladder.enemy.max_hp,
        string.format("第 %d 波配置 = 阶梯（%d 只 / %.2fs / %s hp=%d）", n,
          ws.cfg.enemy_count, ws.cfg.spawn_interval, ws.cfg.prefab, ws.cfg.max_hp))
      check(ws.sample and ws.sample.prefab == ws.cfg.prefab and ws.sample.max_hp == ws.cfg.max_hp,
        string.format("敌人实例 prefab=%s max_hp=%s", tostring(ws.sample and ws.sample.prefab), tostring(ws.sample and ws.sample.max_hp)))
      bd.kill_enemies()
    end })
  step({ name = "第 " .. n .. " 波清场", ["until"] = function() return wd().wave:now().number == n + 1 end, timeout = 3,
    on_done = function(ok) check(ok, string.format("清场 → 第 %d 波倒计时", n + 1)) end })
end
wave_round(1); wave_round(2); wave_round(3)

step({ name = "三波小结", ["do"] = function()
  check(wave_stats[3] and wave_stats[3].cfg.prefab == "enemy_heavy", "第 3 波换档 enemy_heavy")
  check(wave_stats[1] and wave_stats[1].cfg.prefab == "enemy" and wave_stats[2] and wave_stats[2].cfg.prefab == "enemy", "第 1-2 波 enemy")
end })

step({ name = "矿点自然采空 ≥1", ["until"] = function() return gs().resources_remaining:now() <= 5 end, timeout = 45, auto_clear = true,
  on_done = function(ok)
    check(ok, string.format("至少一个矿点自然采空（resources_remaining=%d，money=%s）", gs().resources_remaining:now(), tostring(gs().money:now())))
    bd.resources()
  end })

step({ name = "mine_out → Victory", ["do"] = function() bd.mine_out() end,
  ["until"] = function() return gs().mode:now() == "Victory" and node("panel/restart").visible == true end, timeout = 3,
  on_done = function(ok)
    check(ok, "mode=Victory 且 panel/restart 可见")
    check(gs().resources_remaining:now() == 0, "resources_remaining=0")
    check(node("sidebar/victory").visible == true and node("sidebar/gameover").visible == false, "sidebar/victory 可见 / gameover 隐藏")
    check(node("hud/mode").text == "Mode: Victory", "hud/mode = Mode: Victory")
    check(count("Resource") == 0, "矿点实体全部消失")
  end })

wait_step("shot:victory")

-- ── 重开 → 第二局（Core 被毁）─────────────────────────────────────
wait_step("client:button panel/restart")
step({ name = "重开 gen=1", ["until"] = function() return root() ~= root0 and host().eui.generation == 1 end, timeout = 5,
  on_done = function(ok)
    check(ok, "客户端点 Restart → 树重建 gen=1")
    check(gs().mode:now() == "Pregame", "重开后回 Pregame")
    check(#host().entity.all() == 7, "实体重建 7（实际 " .. #host().entity.all() .. "）")
    -- Core 本身是 building_1_hp；其余 building_*/enemy_* 都该随旧树消失
    local stray = 0
    for path in pairs(host().eui.nodes) do
      if (path:match("^building_") and path ~= "building_1_hp") or path:match("^enemy_") then stray = stray + 1 end
    end
    check(hp_bars() == 7 and stray == 0,
      "血条 7 条（Core building_1_hp + 6 矿点）、无残留 enemy_/building_ 节点（残留 " .. stray .. "，节点总数 " .. node_count() .. "）")
    check(gs().core.entity._unit.Name == "1g1", "新 Core 单位名 '1g1'")
    check(World:FindFirstChild("1", true) == nil and World:FindFirstChild("1g1", true) ~= nil, "World：旧 '1' 消失、'1g1' 可寻")
    check(count("Resource") == 6, "6 个矿点重建")
    check(node("panel/restart").visible == false and node("sidebar/pregame").visible == true, "panel/restart 隐藏 / sidebar/pregame 可见")
  end })

wait_step("shot:pregame")

step({ name = "第二局自动开局", ["until"] = function() return gs().mode:now() == "Playing" end, timeout = 6,
  on_done = function(ok)
    check(ok, "重开后自动 Playing")
    check(gs().money:now() == 100, "money 回到 100")
    bd.kill_enemies()
  end })

wait_step("client:button panel/build/turret; client:board 0 3.5")
step({ name = "第二局落位 turret", ["until"] = function() return count("turret") == 1 end, timeout = 5, auto_clear = true,
  on_done = function(ok)
    local id, rec = building_by_key("turret")
    check(ok and id ~= nil, "重开后客户端点击放 turret（id=" .. tostring(id) .. "）")
    check(rec and rec.entity._unit.Name == id .. "g1", "新建筑单位名 '" .. tostring(id) .. "g1'")
    check(id and node("building_" .. id .. "_hp") ~= nil, "血条节点 building_" .. tostring(id) .. "_hp 存在")
    check(gs().money:now() < 100, "money 扣除 turret 造价 100 后 < 100（实际 " .. tostring(gs().money:now()) .. "）")
  end })

step({ name = "kill_core → GameOver", ["do"] = function() bd.kill_core() end,
  ["until"] = function() return gs().mode:now() == "GameOver" and node("panel/restart").visible == true end, timeout = 3,
  on_done = function(ok)
    check(ok, "mode=GameOver 且 panel/restart 可见")
    check(node("sidebar/gameover").visible == true and node("sidebar/victory").visible == false, "sidebar/gameover 可见 / victory 隐藏")
    check(node("hud/mode").text == "Mode: GameOver", "hud/mode = Mode: GameOver")
    gen_after_victory = host().eui.generation
  end })

wait_step("shot:gameover")

wait_step("client:button panel/restart")
step({ name = "重开 gen=2", ["until"] = function() return host().eui.generation == 2 end, timeout = 5,
  on_done = function(ok)
    check(ok, "GameOver 后客户端点 Restart → gen=2")
    check(gs().mode:now() == "Pregame" and #host().entity.all() == 7 and hp_bars() == 7, "第三局 Pregame / 7 实体 / 7 血条")
    check(gs().core.entity._unit.Name == "1g2", "Core 单位名 '1g2'")
  end })

step({ name = "DONE", ["do"] = function()
  bd.status()
  log("ITF DONE %d checks, %d failed", checks, fails)
end })

-- ── 运行器 ──────────────────────────────────────────────────────────
local t, i = 0, 1
local cur_started, cur_t0
local conn
conn = RunService.Heartbeat:Connect(function(dt)
  t = t + dt
  local st = steps[i]
  if not st then conn:Disconnect(); return end
  if not cur_started then
    cur_started = true
    cur_t0 = t
    log("[%d/%d] %s", i, #steps, st.name)
    if st["do"] then
      local ok, err = pcall(st["do"])
      if not ok then log("STEP ERROR [%s] %s", st.name, tostring(err)) end
    end
  end
  local ok_poll, err = pcall(function()
    track_waves()
    if st.poll then st.poll(t) end
    if st.auto_clear and assaulting() and spawn_complete() and #alive_enemies() > 0 then
      log("[%s] 撞上来袭（已出齐），自动清场", st.name)
      bd.kill_enemies()
    end
  end)
  if not ok_poll then log("STEP ERROR [%s] %s", st.name, tostring(err)) end

  local done, timed_out = false, false
  if st["until"] then
    local okc, r = pcall(st["until"])
    done = okc and r == true
    local limit = st.timeout_fn and st.timeout_fn() or st.timeout or 5
    if not done and t - cur_t0 > limit then timed_out = true end
  else
    done = true
  end
  if done or timed_out then
    if timed_out then log("[%s] 超时 %.1fs", st.name, t - cur_t0) end
    if st.on_done then
      local okd, e2 = pcall(st.on_done, done)
      if not okd then log("STEP ERROR [%s] on_done %s", st.name, tostring(e2)) end
    end
    i = i + 1
    cur_started = false
  end
end)
log("已排程 %d 步（条件驱动 + 编排器握手）", #steps)
