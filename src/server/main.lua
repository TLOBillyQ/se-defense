-- #19 垂直切片 + #21 建筑与放置（服务端）：GameRootFull + Core + 单波敌人 + HUD + 放置面板。
--
-- 架构（#7 决议）：
--   - 服务端一棵 Auto 树（GameRootFull 全业务组合根，业务零改动经 swap 接入适配层）；
--   - RunService.Heartbeat 固定步长积累驱动 GameTick(1/30)，整帧派发由
--     SpokeRuntime.batch 合并成一次 flush（#10 实测 30fps 稳定、jitter=0）；
--   - host.eui 快照出口每帧 dirty 即发（#18 决策 2），client_ready 握手 /
--     seq 缺口 resync 走全量（#18 决策 1）；
--   - 输入反向通道：客户端捕获层 → FireServer 意图 → host.input 队列（#7 决策 2、#8 D5）。
--
-- #21 建筑与放置：放置/取消按钮归适配层（src/server/adapter/build_panel.lua 投影为
--   快照节点 panel/*，客户端渲成 EUIButton），点击回流 place/cancel 意图；
--   放置预览由业务 board_display 的 ring 双路由承担。
-- #23 电网与辅助建筑：业务零改动；覆盖圈 6044 / 连线与光束 4506 的分派、
--   雷达横杆天线、断电 tint 透传都在适配层（eui.lua / entity.lua）。
--   GM 新增 money/damage/dump_shapes/buildings 供集成测试编排。
-- #26 波次与经济：递增波次阶梯（WAVE_LADDER，按波号生成、任意波号有定义）+
--   三档敌人 prefab 键（enemy / enemy_heavy / enemy_boss → entity.lua 视觉表）+
--   矿点 4 内 2 外（外圈超出 Core 供电范围，需 relay 外扩才能采）。
--   GM 新增 wave/enemies/kill_enemies/resources/lull。
--
-- #28 胜负与重开：Victory/GameOver 由业务 game_state 判定、SideBar banner 经快照
--   可见；Restart 走业务 session.lua（dispose → host:reset_scene() → 同 config 重建
--   GameRootFull），适配层随后重建放置面板、重注入棋盘边界、丢弃重建期间增量并
--   广播 "reset" 全量快照（gen+1，客户端整树替换）；Restart 按钮归适配层
--   （panel/restart，终局可见）。GM 新增 restart/mine_out/kill_core。
--
-- 日志前缀 [bd][server]，供 `$CLI log grep` 提取。GM 面见文件底部 _G.bd。

local World = game:GetService("World")
local RunService = game:GetService("RunService")

local function log(fmt, ...)
  print("[bd][server] " .. string.format(fmt, ...))
end

-- SE 服务端沙盒的 package 库不完整（接入指南：package/io/os/debug 被移除），
-- 而业务 game_root_full.lua 在惰性加载 Enemy 时会写 package.loaded（清测试 stub
-- 缓存）。真机部署不存在 stub 污染，注入最小 shim 使该写法无害化即可，
-- 业务保持零改动。shim 语义：宿主 require 自管缓存时 shim 是死代码；
-- 宿主 require 走 package.loaded 时 shim 从头缓存（无 stub 可清，等价）。
if type(_G.package) ~= "table" then
  _G.package = {}
end
if type(_G.package.loaded) ~= "table" then
  _G.package.loaded = {}
  log("package.loaded 不存在，已注入最小 shim（兼容 game_root_full 的缓存复位写法）")
end

local host = require("server.adapter.host")
local spoke = require("common.spoke")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local GameTick = require("server.game.game_tick")
local GameRootFull = require("server.game.game_root_full")
local Session = require("server.game.session")
local BuildPanel = require("server.adapter.build_panel")

-- ── 切片配置 ────────────────────────────────────────────────────────
-- 棋盘 40×40、Core 置世界原点、单位 1:1（#8 D2 假设）。
local STEP = 1 / 30        -- 对齐宿主 30fps 逻辑帧（#7-A2，#10 实测通过）
local MAX_CATCHUP = 4      -- 积累上限 4 步/帧，超限丢弃（#7-A1，#10 实测通过）
local AUTO_START_AT = 3    -- 试玩开局 3s 后自动进入 Playing（Pregame 可观察 HUD）

-- 波次阶梯（#26）：业务 WaveDirector 按 `waves[number]` 取每波配置、缺项回退
-- 全局；这里不写死有限几波，而是按波号生成，任意波号都有定义（无限递增）。
-- 三档敌人：1-2 波 enemy（小快）、3-5 波 enemy_heavy（中厚）、6+ 波 enemy_boss
-- （大慢重击）；同档内数量递增、间隔递减。数值只求「肉眼可见的递增」，
-- 不做平衡（打磨阶段）。
local ENEMY_TIERS = {
  { prefab = "enemy",       max_hp = 10, move_speed = 3,   stop_distance = 1.5, fire_rate = 1, damage = 5,  radius = 0.5 },
  { prefab = "enemy_heavy", max_hp = 30, move_speed = 2,   stop_distance = 1.8, fire_rate = 1, damage = 12, radius = 0.7 },
  { prefab = "enemy_boss",  max_hp = 80, move_speed = 1.5, stop_distance = 2.2, fire_rate = 1, damage = 25, radius = 1.0 },
}
local function wave_config(n)
  local tier, count
  if n <= 2 then
    tier, count = 1, 4 + n            -- 5, 6
  elseif n <= 5 then
    tier, count = 2, 1 + n            -- 4, 5, 6
  else
    tier, count = 3, math.min(2 + (n - 5), 8) -- 3, 4, … 封顶 8
  end
  return {
    enemy_count = count,
    spawn_interval = math.max(0.5, 1.1 - 0.1 * n), -- 1.0, 0.9, … 下限 0.5
    enemy = ENEMY_TIERS[tier],
  }
end
-- 惰性表：业务读 waves[n] 时经 __index 生成（表本身空，业务零改动）。
local WAVE_LADDER = setmetatable({}, { __index = function(_, n)
  if type(n) == "number" then return wave_config(n) end
end })

-- 矿点布局（#26）：4 个内圈矿点在 Core 供电范围内（默认位置，开局即采）；
-- 2 个外圈矿点距 Core 7（> provide_range 4），必须放 relay 外扩才通电，
-- 让「电网扩张 → 经济增长」在真机可见。全采空 = Victory（后续片挂 banner）。
local RESOURCES = {
  { position = { x = -2.5, y = 0, z = 2.5 },  start_resources = 20 },
  { position = { x = 2.5,  y = 0, z = 2.5 },  start_resources = 20 },
  { position = { x = -2.5, y = 0, z = -2.5 }, start_resources = 20 },
  { position = { x = 2.5,  y = 0, z = -2.5 }, start_resources = 20 },
  { position = { x = 7,    y = 0, z = 0 },    start_resources = 30 },
  { position = { x = -7,   y = 0, z = 0 },    start_resources = 30 },
}

local tick = GameTick.new(STEP)

-- 同一份 config 贯穿整局与每次重开（session.lua 语义：restart 用同一 config 重建）。
local GAME_CONFIG = {
  host = host,
  game_tick = tick,
  game_state = {
    core_position = { x = 0, y = 0, z = 0 },
    dimensions = { x = 40, z = 40 },
    start_money = 100,
    core_max_hp = 50,
  },
  wave_director = {
    lull_duration = 30,  -- #21：每波前 30s 放置/采集窗口（原 8）
    front_reveal_time = 3,
    spawn_interval = 1,
    enemy_count = 5,
    waves = WAVE_LADDER,
  },
  enemy = ENEMY_TIERS[1], -- 全局兜底（阶梯每波都给全量 enemy 表，实际不会回退到这里）
  resources = RESOURCES,
}

-- 会话壳（#28）：Auto 树 + GameRootFull 组合根；restart() 拆树 → 清场 → 重建。
local session = Session.spawn(GAME_CONFIG, "Auto", GameRootFull)
local root = session.root
local tree = session.tree
log("Auto 树 spawn 完成 fault=%s detached=%s", tostring(tree.fault), tostring(tree.is_detached))

-- 树之外、每局都要随 root 重建的适配层挂件：棋盘边界（#8 D2）+ 放置面板（#21）。
local panel
local function mount_adapter(r)
  host.input.set_bounds(r.game_state:level_bounds())
  panel = BuildPanel.create(host, r)
  BuildPanel.update(panel)
end
mount_adapter(root)

-- ── RemoteEvent 通道（bd_game）：快照下行 + 输入/握手上行 ─────────────
local re = RemoteEvent.New("bd_game")
local seq = 0

local function send(kind, payload)
  seq = seq + 1
  local msg = payload or {}
  msg.kind = kind
  msg.seq = seq
  msg.gen = host.eui.generation
  re:FireAllClients(msg)
end

local function send_full()
  send("full", { nodes = host.eui.full() })
end

-- 开局计时：uptime 到点自动 start_game；nil = 已开局。重开后重新计时（回 Pregame 可观察 banner）。
local uptime = 0
local start_at = AUTO_START_AT

-- Restart（#28）：业务 session.lua 三步（dispose → host:reset_scene() → 重建），
-- 随后适配层重挂、丢弃重建期间攒下的增量、广播 reset 全量（gen 已 +1）。
-- 不在 tick 派发中途调用（RemoteEvent / GM 都在帧间到达）。
local function restart_game(why)
  local old_gen = host.eui.generation
  session:restart()
  root = session.root
  tree = session.tree
  mount_adapter(root)
  start_at = uptime + AUTO_START_AT
  if _G.bd then _G.bd.root = root end
  host.eui.drain()
  send("reset", { nodes = host.eui.full() })
  log("RESTART(%s) gen %d → %d：树重建 fault=%s，entities=%d nodes=%d，%ds 后自动开局",
    tostring(why), old_gen, host.eui.generation, tostring(tree.fault),
    #host.entity.all(), #host.eui.order, AUTO_START_AT)
end

re.OnServerEvent:Connect(function(player, args)
  -- F10：入参按不可信输入校验（类型白名单 + 数值范围）
  if type(args) ~= "table" then return end
  local kind = args.kind
  if kind == "client_ready" or kind == "resync" then
    log("%s 到达，发全量快照（nodes=%d）", kind, #host.eui.order)
    send_full()
  elseif kind == "input" then
    local itype = args.itype
    if itype == "tap" or itype == "hover" then
      local x, z = tonumber(args.x), tonumber(args.z)
      if x and z and math.abs(x) <= 100 and math.abs(z) <= 100 then
        if itype == "tap" then
          log("输入 tap → (%.2f, %.2f)", x, z)
          host.input.intent_tap(x, z)
        else
          host.input.intent_hover(x, z)
        end
      elseif itype == "hover" and args.x == nil then
        host.input.intent_hover(nil, nil) -- 抬指/出界
      end
    elseif itype == "cancel" then
      log("输入 cancel")
      host.input.intent_cancel()
    elseif itype == "place" then
      local key = args.key
      if type(key) == "string" and #key <= 16 then
        local ok, why = BuildPanel.place(panel, key)
        log("输入 place(%s) → %s", key, ok and "placing 置位" or tostring(why))
      end
    elseif itype == "restart" then
      -- 只在终局受理（按钮也只在终局可见）；Playing 中的误发/重放一律忽略
      if BuildPanel.restart_allowed(panel) then
        restart_game("client")
      else
        log("输入 restart 被拒（mode=%s）", tostring(root.game_state.mode:now()))
      end
    end
  end
end)

-- ── Heartbeat 固定步长驱动器（#7 决策 3 + #10 验证姿势）──────────────
local acc = 0
local ticks_total = 0

RunService.Heartbeat:Connect(function(deltaTime)
  uptime = uptime + deltaTime

  if start_at and uptime >= start_at then
    start_at = nil
    root.game_state:start_game()
    log("自动 start_game @%.1fs → Playing", uptime)
  end

  acc = acc + deltaTime
  SpokeRuntime.batch(function()
    local steps = 0
    while acc >= STEP and steps < MAX_CATCHUP do
      host.input.arm_frame()   -- 上帧到达的点击意图举为当帧边沿（见 input.lua 注释）
      tick:tick(STEP)
      host.input.reset_frame() -- "按下只持续一帧"（#8 D5）
      acc = acc - STEP
      steps = steps + 1
      ticks_total = ticks_total + 1
    end
  end)
  if acc >= STEP then
    acc = 0 -- 丢弃多余时间，不做追赶（#7-A1）
  end

  -- 放置面板投影（余额/选中/可见），再取快照增量
  BuildPanel.update(panel)

  -- 快照：每帧派发结束 dirty 即发（#18 决策 2，无额外节流）
  local delta = host.eui.drain()
  if delta then
    send("delta", delta)
  end
end)

-- ── GM 面（$CLI exec --platform server 驱动；自动化验证优先 #1 偏好 2）──
_G.bd = {
  root = root, -- 无头 harness / 自动化直读（tools/headless/run_server.lua）
  status = function()
    local gs = root.game_state
    log("STATUS mode=%s ticks=%d uptime=%.1fs money=%s core_hp=%.2f entities=%d eui_nodes=%d seq=%d gen=%d",
      tostring(gs.mode:now()), ticks_total, uptime,
      tostring(gs.money:now()),
      gs.core and gs.core.health.hp_fraction:now() or -1,
      #host.entity.all(), #host.eui.order, seq, host.eui.generation)
  end,
  start = function()
    if start_at then
      start_at = nil
      root.game_state:start_game()
      log("GM start_game")
    end
  end,
  -- 重开（#28）：与客户端 restart 意图同一路径，但不限终局（集成测试/救场用）
  restart = function()
    restart_game("gm")
  end,
  -- 全部矿点直接采空 → 业务判 Victory（不经供电/采集，秒到终局）
  mine_out = function()
    local n = 0
    for _, r in ipairs(root.resources) do
      if r.remaining:now() > 0 then r.remaining:set(0); n = n + 1 end
    end
    log("GM mine_out → %d 个矿点置空", n)
  end,
  -- 打死 Core → 业务判 GameOver
  kill_core = function()
    root.game_state.core.health:damage(99999)
    log("GM kill_core → alive=%s", tostring(root.game_state.core.health.is_alive:now()))
  end,
  -- 注入一次棋盘点 tap（绕过网络的自动化输入；等价客户端 tap 意图）
  tap = function(x, z)
    local ok = host.input.intent_tap(tonumber(x), tonumber(z))
    log("GM tap(%s,%s) → %s", tostring(x), tostring(z), tostring(ok))
  end,
  cancel = function()
    host.input.intent_cancel()
    log("GM cancel")
  end,
  -- 进入放置模式（与客户端按钮的 place 意图同一入口）
  place = function(key)
    local ok, why = BuildPanel.place(panel, tostring(key))
    log("GM place(%s)：%s", tostring(key), ok and "placing 已置位" or tostring(why))
  end,
  -- 放置流状态一览（集成测试读回）
  placing = function()
    local p = root.board_interactions.placing:now()
    log("PLACING key=%s valid=%s mouse=%s",
      p and p.key or "nil", tostring(root.board_interactions.placement_valid:now()),
      (function() local m = host.input.get_mouse_world_point(); return m and string.format("(%.2f,%.2f)", m.x, m.z) or "nil" end)())
  end,
  -- 直接设余额（集成测试铺建筑用）
  money = function(n)
    root.game_state.money:set(tonumber(n) or 0)
    log("GM money=%s", tostring(root.game_state.money:now()))
  end,
  -- 对某建筑（按实体 id）造成伤害；测试「relay 被毁 → 下游断电」
  damage = function(id, amount)
    local rec = root.pool and root.pool._live_by_entity_id[tonumber(id)]
    local b = rec and rec.epoch and rec.epoch.building
    if not b then log("GM damage：实体 %s 不是 live 建筑", tostring(id)); return end
    b.health:damage(tonumber(amount) or 999)
    log("GM damage(%s,%s) → alive=%s", tostring(id), tostring(amount), tostring(b.health.is_alive:now()))
  end,
  -- live 建筑一览：id / 类型 / 供电 / 血量
  buildings = function()
    for id, rec in pairs(root.pool and root.pool._live_by_entity_id or {}) do
      local b = rec.epoch and rec.epoch.building
      if b then
        local p = rec.entity.position
        log("building #%d %s @(%.1f,%.1f) powered=%s hp=%.2f",
          id, tostring(rec.spec and rec.spec.key), p.x, p.z,
          b.power and tostring(b.power.has_power:now()) or "n/a",
          b.health.hp_fraction:now())
      end
    end
  end,
  -- 形状单位（覆盖圈/连线/光束）一览
  dump_shapes = function()
    for _, sh in ipairs(host.eui.shapes()) do
      log("shape %s kind=%s effect=%s visible=%s%s", sh.path, sh.kind, tostring(sh.effect),
        tostring(sh.visible), sh.radius and string.format(" r=%.2f", sh.radius) or "")
    end
  end,
  -- 当前波次一览 + 任意波号的阶梯配置（集成测试对照）
  wave = function(n)
    local w = root.wave_director.wave:now()
    local cfg = root.wave_director:wave_enemy_config()
    log("WAVE number=%d front=%s starts_in=%d cfg: count=%d interval=%.2f prefab=%s hp=%s",
      w.number, tostring(w.front), w.starts_in, cfg.enemy_count, cfg.spawn_interval,
      tostring(cfg.prefab), tostring(cfg.max_hp))
    if n then
      local c = wave_config(tonumber(n))
      log("LADDER[%d] count=%d interval=%.2f prefab=%s hp=%d", tonumber(n), c.enemy_count, c.spawn_interval, c.enemy.prefab, c.enemy.max_hp)
    end
  end,
  -- 存活敌人一览
  enemies = function()
    local n = 0
    for _, en in ipairs(root.enemies) do
      if en.health and en.health.is_alive:now() then
        n = n + 1
        local p = en.entity.position
        log("enemy #%d %s @(%.1f,%.1f) hp=%.2f", en.entity.id, en.prefab, p.x, p.z, en.health.hp_fraction:now())
      end
    end
    log("ENEMIES alive=%d", n)
  end,
  -- 清场：击杀全部存活敌人（触发 wave_defeated → 下一波倒计时）
  kill_enemies = function()
    local n = 0
    for _, en in ipairs(root.enemies) do
      if en.health and en.health.is_alive:now() then
        en.health:damage(99999)
        n = n + 1
      end
    end
    log("GM kill_enemies → %d", n)
  end,
  -- 矿点一览：id / 位置 / 剩余 / 供电
  resources = function()
    for _, r in ipairs(root.resources) do
      local p = r.entity.position
      log("resource #%d @(%.1f,%.1f) remaining=%d powered=%s", r.entity.id, p.x, p.z,
        r.remaining:now(), r.power and tostring(r.power.has_power:now()) or "n/a")
    end
    log("RESOURCES remaining_sites=%d money=%s rate=%.2f", root.game_state.resources_remaining:now(),
      tostring(root.game_state.money:now()), root.game_state.collect_rate:now())
  end,
  -- 改「下一次」平静期时长（当前倒计时不受影响；集成测试缩短等待用）
  lull = function(sec)
    root.wave_director._config.lull_duration = tonumber(sec) or 30
    log("GM lull_duration=%s（下一波起生效）", tostring(root.wave_director._config.lull_duration))
  end,
  dump_entities = function()
    for _, e in ipairs(host.entity.all()) do
      local p = e.position
      log("entity #%d %s @(%.1f,%.1f,%.1f) active=%s", e.id, tostring(e.prefab), p.x, p.y, p.z, tostring(e.active))
    end
  end,
  dump_nodes = function()
    for _, path in ipairs(host.eui.order) do
      local n = host.eui.nodes[path]
      if n then
        log("node %s text=%q visible=%s fill=%.2f shape=%s",
          path, n.text, tostring(n.visible), n.fill, tostring(n._shape_only == true))
      end
    end
  end,
}

log("服务端挂载完成：Session(GameRootFull) + Heartbeat 驱动 GameTick(1/30) + RemoteEvent(bd_game) + 放置面板/Restart + 波次阶梯/6 矿点")
