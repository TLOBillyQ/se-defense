-- #26 真机集成：波次与经济（服务端注入）。
-- 运行：试玩中 `$CLI exec --platform server --file '<Windows 路径>'`，
-- 回读 `$CLI log grep "bd\]\[it4" --play-session <id>`。
-- 与 slice3 不同：步骤按「条件满足」推进而非固定秒数（脚本注入时刻相对
-- 30s 平静期不可控）；经济类步骤若撞上来袭，自动清场再继续（auto_clear）。
-- 每步打 CHECK ok/FAIL；结束打 "IT4 DONE n checks, m failed"。
--
-- 剧本：6 矿点（外圈无电）→ relay (3.5,0) 外扩 → 外圈矿点通电采集、money 涨、
--       血条出现 → 矿点采空消失 → Core 受击闪红 → 连打 3 波：每波配置 = 阶梯、
--       出怪间隔 ≈ spawn_interval、第 3 波换档 enemy_heavy（大一号、紫红）。
--       结束时留第 4 波自然来袭供目视。

local RunService = game:GetService("RunService")
local bd = _G.bd
local root = bd.root
local host = root.host
local gs = root.game_state
local bi = root.board_interactions
local wd = root.wave_director

local checks, fails = 0, 0
local function log(fmt, ...) print("[bd][it4] " .. string.format(fmt, ...)) end
local function check(cond, msg)
  checks = checks + 1
  log("CHECK %s %s", cond and "ok" or "FAIL", msg)
  if not cond then fails = fails + 1 end
end
local function count(prefab)
  local n = 0
  for _, e in ipairs(host.entity.all()) do if e.prefab == prefab then n = n + 1 end end
  return n
end
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
local function assaulting() return wd.wave:now().starts_in == 0 end
local function hover(x, z) host.input.intent_hover(x, z) end
local function near(a, b, tol) return math.abs(a - b) <= tol end

-- ── 步骤定义 ────────────────────────────────────────────────────────
-- { name, do=fn, until=fn→bool, timeout=s, auto_clear=bool, on_done=fn(ok) }
local steps = {}
local function step(t) steps[#steps + 1] = t end

local outer, inner, victim_id, money0, outer0, core_e
local waves_seen = {}

step({ name = "START", ["do"] = function()
  if gs.mode:now() ~= "Playing" then bd.start() end
  bd.lull(6)  -- 之后每波平静期 6s
  bd.money(1000)
  log("START mode=%s wave=%d starts_in=%d", tostring(gs.mode:now()), wd.wave:now().number, wd.wave:now().starts_in)
  check(#root.resources == 6, "6 个矿点")
  inner, outer = resource_at(2.5, 2.5), resource_at(7, 0)
  check(inner and inner.power.has_power:now() == true, "内圈矿点 (2.5,2.5) 有电")
  check(outer and outer.power.has_power:now() == false, "外圈矿点 (7,0) 无电")
  check(outer and outer.remaining:now() == 30, "外圈矿点 remaining=30")
  check(count("Resource") == 6, "6 个 Resource 实体")
end, ["until"] = function() return gs.mode:now() == "Playing" end, timeout = 2 })

step({ name = "放 relay 外扩", ["do"] = function() bd.place("relay"); hover(3.5, 0) end,
  ["until"] = function() return bi.placement_valid:now() == true end, timeout = 2, auto_clear = true,
  on_done = function(ok) check(ok, "(3.5,0) 电网内 → 有效"); bd.tap(3.5, 0) end })

step({ name = "relay 落位", ["until"] = function() return count("relay") == 1 end, timeout = 2,
  on_done = function(ok) check(ok, "relay 落位 (3.5,0)"); hover(nil, nil) end })

step({ name = "外圈通电", ["until"] = function() return outer.power.has_power:now() == true end, timeout = 3,
  on_done = function(ok)
    check(ok, "外圈矿点经 relay 通电")
    money0, outer0 = gs.money:now(), outer.remaining:now()
  end })

step({ name = "外圈采集", ["until"] = function() return outer.remaining:now() <= outer0 - 1 end, timeout = 20, auto_clear = true,
  on_done = function(ok)
    check(ok, string.format("外圈矿点采集 remaining %d → %d", outer0, outer.remaining:now()))
    check(gs.money:now() > money0, string.format("money 增长 %d → %d", money0, gs.money:now()))
    local bar = host.eui.nodes["resource_" .. outer.entity.id .. "_hp"]
    check(bar and bar.visible == true and bar.fill < 1, "外圈矿点血条可见 fill<1")
    local v = resource_at(-2.5, -2.5)
    victim_id = v.entity.id
    v.remaining:set(1)
    log("矿点 #%d remaining 置 1，等采空", victim_id)
  end })

step({ name = "矿点采空", ["until"] = function() return host.entity.by_id[victim_id] == nil end, timeout = 20, auto_clear = true,
  on_done = function(ok)
    check(ok, "采空 → Resource 实体销毁")
    check(gs.resources_remaining:now() == 5, "resources_remaining=5（实际 " .. gs.resources_remaining:now() .. "）")
    core_e = gs.core.entity
    gs.core.health:damage(1)
  end })

step({ name = "Core 闪红", ["until"] = function()
    local c = core_e._unit.ModelColor1; return c.r == 255 and c.g == 0 and c.b == 0
  end, timeout = 0.5,
  on_done = function(ok) check(ok, "Core 受击 → ModelColor1 (255,0,0)") end })

step({ name = "Core 复色", ["until"] = function()
    local c = core_e._unit.ModelColor1; return c.r == 255 and c.g == 214 and c.b == 0
  end, timeout = 1,
  on_done = function(ok) check(ok, "0.1s 后恢复底色 (255,214,0)") end })

-- 连打三波：每波「等来袭 → 对照阶梯 → 数出怪间隔 → 清场」
local function wave_round(idx)
  local rec = {}
  step({ name = "等第 " .. idx .. " 轮来袭", ["until"] = assaulting, timeout = 40,
    on_done = function(ok)
      local w = wd.wave:now()
      rec.number = w.number
      rec.cfg = wd:wave_enemy_config()
      rec.ladder = wd._waves[w.number]
      rec.spawn_t = {}
      rec.seen = 0
      check(ok, string.format("第 %d 波来袭 front=%s", w.number, tostring(w.front)))
      check(rec.cfg.enemy_count == rec.ladder.enemy_count and rec.cfg.spawn_interval == rec.ladder.spawn_interval
        and rec.cfg.prefab == rec.ladder.enemy.prefab,
        string.format("第 %d 波配置 = 阶梯（%d 只 / %.2fs / %s hp=%d）", w.number,
          rec.cfg.enemy_count, rec.cfg.spawn_interval, rec.cfg.prefab, rec.cfg.max_hp))
      check(gs.collect_rate:now() == 0, "来袭期间采集暂停")
    end })
  step({ name = "数第 " .. idx .. " 轮出怪", poll = function(t)
      local n = #alive_enemies()
      if n > rec.seen then rec.seen = n; rec.spawn_t[#rec.spawn_t + 1] = t end
    end,
    ["until"] = function() return rec.seen >= rec.cfg.enemy_count end,
    timeout_fn = function() return rec.cfg.enemy_count * rec.cfg.spawn_interval + 3 end,
    on_done = function(ok)
      check(ok, string.format("第 %d 波 %d 只出齐（实际 %d）", rec.number, rec.cfg.enemy_count, rec.seen))
      local gaps, gaps_ok = {}, true
      for i = 2, #rec.spawn_t do
        local g = rec.spawn_t[i] - rec.spawn_t[i - 1]
        gaps[#gaps + 1] = string.format("%.2f", g)
        if not near(g, rec.cfg.spawn_interval, 0.12) then gaps_ok = false end
      end
      check(gaps_ok and #gaps == rec.cfg.enemy_count - 1,
        string.format("出怪间隔 ≈ %.2fs（%s）", rec.cfg.spawn_interval, table.concat(gaps, ",")))
      local en = alive_enemies()[1]
      check(en and en.prefab == rec.cfg.prefab and en.max_hp == rec.cfg.max_hp,
        string.format("敌人实例 prefab=%s max_hp=%s", tostring(en and en.prefab), tostring(en and en.max_hp)))
      local sc = en and en.entity._unit.Scale
      log("敌人视觉 prefab=%s scale=%s color=%s", tostring(en and en.prefab),
        sc and string.format("%.1f", sc.x) or "?", en and tostring(en.entity._unit.ModelColor1) or "?")
      waves_seen[#waves_seen + 1] = rec
      bd.enemies()
      bd.kill_enemies()
    end })
  step({ name = "第 " .. idx .. " 轮清场", ["until"] = function() return wd.wave:now().number == rec.number + 1 end, timeout = 3,
    on_done = function(ok)
      check(ok, string.format("清场 → 第 %d 波倒计时 %d", wd.wave:now().number, wd.wave:now().starts_in))
    end })
end
wave_round(1); wave_round(2); wave_round(3)

step({ name = "DONE", ["do"] = function()
  local prefabs = {}
  for _, r in ipairs(waves_seen) do prefabs[#prefabs + 1] = r.number .. ":" .. r.cfg.prefab .. "x" .. r.cfg.enemy_count end
  log("三轮波次 %s", table.concat(prefabs, " "))
  local heavy = false
  for _, r in ipairs(waves_seen) do if r.cfg.prefab == "enemy_heavy" then heavy = true end end
  check(heavy or (waves_seen[1] and waves_seen[1].number > 3), "三轮内见到 enemy_heavy 换档（或起始波号已 >3）")
  bd.resources(); bd.wave(6); bd.status()
  log("IT4 DONE %d checks, %d failed（试玩留在运行中，第 %d 波 6s 后来袭供目视）", checks, fails, wd.wave:now().number)
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
  local ok_poll, err = pcall(function()
    if st.poll then st.poll(t) end
    if st.auto_clear and assaulting() and #alive_enemies() > 0 then
      log("[%s] 撞上来袭，自动清场", st.name)
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
log("已排程 %d 步（条件驱动）", #steps)
