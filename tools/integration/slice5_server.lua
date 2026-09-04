-- #28 真机集成：胜负与重开（服务端注入）。
-- 运行：试玩中 `$CLI exec --platform server --file '<Windows 路径>'`，
-- 回读 `$CLI log grep "bd\]\[it5" --play-session <id>`。
-- 条件驱动步进（同 slice4）。每步打 CHECK ok/FAIL；结束打 "IT5 DONE n checks, m failed"。
--
-- 剧本：Playing 中 panel/restart 隐藏 → GM mine_out 全部矿点 → Victory（banner +
--       Restart 可见）→ GM restart → 新树 / Pregame / 7 实体 / gen=1 / 单位名 1g1 /
--       旧单位消失 → 3s 自动 Playing → 放 turret 可用（单位名 8g1）→ GM kill_core →
--       GameOver。结束时留在 GameOver，供客户端侧点 Restart 按钮
--       （`_G.bd_client.tap_button("panel/restart")`）做 HITL 收尾。
--
-- 注意：bd.root 每次重开都换对象，全程经访问器取，不缓存 root/gs。

local World = game:GetService("World")
local RunService = game:GetService("RunService")
local bd = _G.bd
local function root() return bd.root end
local function gs() return root().game_state end
local function host() return root().host end
local function node(path) return host().eui.nodes[path] end

local checks, fails = 0, 0
local function log(fmt, ...) print("[bd][it5] " .. string.format(fmt, ...)) end
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

local steps = {}
local function step(t) steps[#steps + 1] = t end

local root0, nodes0, core_unit0

step({ name = "START", ["do"] = function()
  if gs().mode:now() ~= "Playing" then bd.start() end
  bd.kill_enemies()
  root0 = root()
  nodes0 = node_count()
  core_unit0 = gs().core.entity._unit
  log("START mode=%s gen=%d entities=%d nodes=%d", tostring(gs().mode:now()),
    host().eui.generation, #host().entity.all(), nodes0)
  check(host().eui.generation == 0, "首局 gen=0")
  check(core_unit0 and core_unit0.Name == "1", "首局 Core 单位名 '1'")
  check(node("panel/restart") and node("panel/restart").visible == false, "Playing 中 panel/restart 隐藏")
  check(node("sidebar/victory").visible == false and node("sidebar/gameover").visible == false, "终局 banner 均隐藏")
end, ["until"] = function() return gs().mode:now() == "Playing" end, timeout = 2 })

step({ name = "矿点采空 → Victory", ["do"] = function() bd.mine_out() end,
  -- mine_out 在本回调内同步触发 Victory（响应式，不经 tick），面板投影要等下一帧 → 条件连面板一起等
  ["until"] = function() return gs().mode:now() == "Victory" and node("panel/restart").visible == true end, timeout = 3,
  on_done = function(ok)
    check(gs().mode:now() == "Victory", "mode=Victory")
    check(gs().resources_remaining:now() == 0, "resources_remaining=0")
    check(node("sidebar/victory").visible == true, "sidebar/victory 可见")
    check(node("panel/restart").visible == true, "panel/restart 终局可见")
    check(node("hud/mode").text == "Mode: Victory", "hud/mode = Mode: Victory")
    check(count("Resource") == 0, "矿点实体全部消失")
  end })

step({ name = "Victory 停留 2s（目视 banner + Restart）", ["until"] = function() return false end, timeout = 2,
  on_done = function() end })

step({ name = "GM restart", ["do"] = function() bd.restart() end,
  ["until"] = function() return root() ~= root0 end, timeout = 2,
  on_done = function(ok)
    check(ok, "root 换新对象")
    check(gs().mode:now() == "Pregame", "重开后回 Pregame")
    check(#host().entity.all() == 7, "实体重建 7（实际 " .. #host().entity.all() .. "）")
    check(hp_bars() == 7 and not has_node_prefix("enemy_"), "血条节点 7 条、无残留 enemy_ 节点（节点总数 " .. node_count() .. "）")
    check(host().eui.generation == 1 and host().entity.generation == 1, "gen=1")
    check(gs().core.entity._unit.Name == "1g1", "新 Core 单位名 '1g1'")
    check(World:FindFirstChild("1", true) == nil, "旧单位 '1' 已从 World 消失")
    check(World:FindFirstChild("1g1", true) ~= nil, "World 中可寻到 '1g1'")
    check(node("panel/restart").visible == false and node("sidebar/pregame").visible == true, "panel/restart 隐藏 / sidebar/pregame 可见")
    check(count("Resource") == 6, "6 个矿点重建")
  end })

step({ name = "等待自动开局", ["until"] = function() return gs().mode:now() == "Playing" end, timeout = 5,
  on_done = function(ok)
    check(ok, "重开后自动 Playing")
    check(gs().money:now() == 100, "money 回到 100")
    bd.kill_enemies()
    bd.place("turret")
    host().input.intent_hover(3, 0)
  end })

step({ name = "放 turret", ["until"] = function() return root().board_interactions.placement_valid:now() == true end, timeout = 2,
  on_done = function(ok) check(ok, "(3,0) 有效"); bd.tap(3, 0) end })

step({ name = "turret 落位", ["until"] = function() return count("turret") == 1 end, timeout = 2,
  on_done = function(ok)
    check(ok, "重开后 turret 落位")
    local e = host().entity.by_id[8]
    check(e and e._unit.Name == "8g1", "新建筑单位名 '8g1'")
    check(node("building_8_hp") ~= nil, "血条节点 building_8_hp 存在（客户端按 8g1 寻单位）")
    host().input.intent_hover(nil, nil)
  end })

step({ name = "kill_core → GameOver", ["do"] = function() bd.kill_core() end,
  ["until"] = function() return gs().mode:now() == "GameOver" and node("panel/restart").visible == true end, timeout = 3,
  on_done = function(ok)
    check(gs().mode:now() == "GameOver", "mode=GameOver")
    check(node("sidebar/gameover").visible == true, "sidebar/gameover 可见")
    check(node("panel/restart").visible == true, "panel/restart 可见")
    check(node("hud/mode").text == "Mode: GameOver", "hud/mode = Mode: GameOver")
  end })

step({ name = "DONE", ["do"] = function()
  bd.status()
  log("IT5 DONE %d checks, %d failed（留在 GameOver；客户端点 Restart 收尾：_G.bd_client.tap_button('panel/restart')）", checks, fails)
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
    if st["do"] then
      local ok, err = pcall(st["do"])
      if not ok then log("STEP ERROR [%s] %s", st.name, tostring(err)) end
    end
  end
  local done, timed_out = false, false
  if st["until"] then
    local okc, r = pcall(st["until"])
    done = okc and r == true
    if not done and t - cur_t0 > (st.timeout or 5) then timed_out = true end
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
log("已排程 %d 步（条件驱动）", #steps)
