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
-- #21 建筑与放置：放置/取消按钮归适配层（server/adapter/build_panel.lua 投影为
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
-- 规则与数值真源：docs/gdd/（世界常量在 server/game/world.lua）。
local STEP = 1 / 30        -- 对齐宿主 30fps 逻辑帧（#7-A2，#10 实测通过）
local MAX_CATCHUP = 4      -- 积累上限 4 步/帧，超限丢弃（#7-A1，#10 实测通过）

-- 波次节奏（GDD 07：预算/层级/间隔/方向）在 server/game/wave_cycle.lua；
-- 敌人三层级（血量/足迹/成本）在 world.enemy_tiers。
local WorldData = require("server.game.world")

-- 矿点布局（GDD 00）：27 个预置矿点，每个剩余量 300、足迹 0.5、收电圈 0.5、
-- 采集节奏 0.8 秒 1 单位；开局恰好 3 个接入 Core 供电圈，其余 24 个需 Relay 外扩。
local RESOURCES = {}
for _, site in ipairs(WorldData.sites) do
  RESOURCES[#RESOURCES + 1] = {
    position = { x = site.x, y = 0, z = site.z },
    start_resources = WorldData.site_remaining,
    radius = WorldData.specs.Site.footprint,
    receive_range = WorldData.specs.Site.receive,
    collect_time = WorldData.harvest_interval,
  }
end

local tick = GameTick.new(STEP)

-- 同一份 config 贯穿整局与每次重开（session.lua 语义：restart 用同一 config 重建）。
local GAME_CONFIG = {
  host = host,
  game_tick = tick,
  game_state = {
    core_position = { x = 0, y = 0, z = 0 },
    dimensions = { x = 40, z = 40 },
    start_money = WorldData.starting_money,
    core_max_hp = WorldData.specs.Core.health,
  },
  core = { radius = WorldData.specs.Core.footprint },
  wave_director = {},
  enemy = {},
  resources = RESOURCES,
}

-- 会话壳（#28）：Auto 树 + GameRootFull 组合根；restart() 拆树 → 清场 → 重建。
local session = Session.spawn(GAME_CONFIG, "Auto", GameRootFull)
local root = session.root
local tree = session.tree
log("Auto 树 spawn 完成 fault=%s detached=%s", tostring(tree.fault), tostring(tree.is_detached))

-- 树之外、每局都要随 root 重建的适配层挂件：棋盘边界（#8 D2）+ 放置面板（#21）。
local panel

-- 初始布局收敛（rewrite power_grid._settle_initial 同义）：树 spawn 后、仍在
-- Pregame（t=0）时显式采样一次供电圈并令其 flush 收敛，Core 圈内的矿点因此在
-- 开局瞬间即通电（去抖只约束开局后的通断电变化，GDD 03 R8）。重开后同样收敛。
local function settle_initial_power(r)
  if r.game_state.power_zone then
    r.game_state.power_zone:tick()
  end
end

local function mount_adapter(r)
  host.input.set_bounds(r.game_state:level_bounds())
  panel = BuildPanel.create(host, r)
  BuildPanel.update(panel)
  settle_initial_power(r)
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

-- GDD 01 R2：只有玩家主动「开始对局」才从 Pregame 进 Playing（无自动开局）。
local uptime = 0

-- Restart（#28）：业务 session.lua 三步（dispose → host:reset_scene() → 重建），
-- 随后适配层重挂、丢弃重建期间攒下的增量、广播 reset 全量（gen 已 +1）。
-- 不在 tick 派发中途调用（RemoteEvent / GM 都在帧间到达）。
local function restart_game(why)
  local old_gen = host.eui.generation
  session:restart()
  root = session.root
  tree = session.tree
  mount_adapter(root)
  if _G.bd then _G.bd.root = root end
  host.eui.drain()
  send("reset", { nodes = host.eui.full() })
  log("RESTART(%s) gen %d → %d：树重建 fault=%s，entities=%d nodes=%d，回 Pregame 等待开始对局",
    tostring(why), old_gen, host.eui.generation, tostring(tree.fault),
    #host.entity.all(), #host.eui.order)
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
    if itype == "start" then
      -- GDD 01 R2：玩家主动开始对局（Pregame 外无效，业务侧守卫）
      if root.game_state.mode:now() == "Pregame" then
        root.game_state:start_game()
        log("输入 start → Playing")
      end
    elseif itype == "tap" or itype == "hover" then
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

-- 按坐标找矿点（验收编排用；EPS 容差）。
local function find_site(x, z)
  for _, r in ipairs(root.resources) do
    local p = r.entity.position
    if math.abs(p.x - x) < 1e-6 and math.abs(p.z - z) < 1e-6 then return r end
  end
  return nil
end

-- 按类型 + 坐标找 live 建筑（pool 记录；Core 单独看 game_state.core）。
local function find_building(kind, x, z)
  kind = tostring(kind)
  if kind == "Core" then
    local core = root.game_state.core
    local p = core and core.entity.position
    if core and p and math.abs(p.x - x) < 1e-6 and math.abs(p.z - z) < 1e-6
      and core.health.is_alive:now() then
      return core, nil
    end
    return nil
  end
  local key = string.lower(kind)
  for _, rec in pairs(root.pool and root.pool._live_by_entity_id or {}) do
    if rec.spec and rec.spec.key == key then
      local p = rec.entity.position
      if math.abs(p.x - x) < 1e-6 and math.abs(p.z - z) < 1e-6 then
        return rec.epoch and rec.epoch.building, rec
      end
    end
  end
  return nil
end

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
  -- 采空前 n 个未采空矿点（验收编排「采空N个矿点」）
  mine_n = function(n)
    n = tonumber(n) or 0
    local done = 0
    for _, r in ipairs(root.resources) do
      if done >= n then break end
      if r.remaining:now() > 0 then r.remaining:set(0); done = done + 1 end
    end
    log("GM mine_n(%d) → %d", n, done)
  end,
  -- 设定某坐标矿点剩余量（0 即离场；验收编排）
  set_site = function(x, z, remaining)
    local site = find_site(tonumber(x), tonumber(z))
    if not site then log("GM set_site：(%s,%s) 处没有矿点", tostring(x), tostring(z)); return end
    site.remaining:set(tonumber(remaining) or 0)
  end,
  -- 打死 Core → 碎裂 2 秒离场后业务判 GameOver（GDD 01 R5）
  kill_core = function()
    root.game_state.core.health:damage(99999)
    log("GM kill_core → alive=%s", tostring(root.game_state.core.health.is_alive:now()))
  end,
  -- 「X死亡」编排：杀死场上第一个该类型建筑（验收步骤用）
  kill = function(kind)
    kind = tostring(kind)
    if kind == "Core" then return _G.bd.kill_core() end
    local key = string.lower(kind)
    for _, rec in pairs(root.pool and root.pool._live_by_entity_id or {}) do
      local b = rec.epoch and rec.epoch.building
      if b and rec.spec and rec.spec.key == key and b.health.is_alive:now() then
        b.health:damage(99999)
        return
      end
    end
    log("GM kill(%s)：场上没有该类型建筑", kind)
  end,
  -- 「一座已建好的 X 位于 (x,z)」编排：直接造好（不扣费、不经放置校验），
  -- 可选 hp 把血量置为指定值（验收「一座血量为 N 的 X」）。
  spawn_building = function(kind, x, z, hp)
    local key = string.lower(tostring(kind))
    local spec = root.building_specs and root.building_specs[key]
    if not spec then log("GM spawn_building：未知类型 %s", tostring(kind)); return end
    local inst = root.pool:spawn(spec, { x = tonumber(x), y = 0, z = tonumber(z) })
    local b = inst.epoch and inst.epoch.building
    if b then
      b.pool_instance = inst
      if hp then
        local max_hp = b.health.max_hp:now()
        b.health:damage(math.max(0, max_hp - tonumber(hp)))
      end
    end
    log("GM spawn_building(%s, %s, %s, %s)", tostring(kind), tostring(x), tostring(z), tostring(hp))
  end,
  -- 「位于 (x,z) 的 X 被摧毁」编排：摧毁即离场（不经碎裂、不扣费）。
  destroy_at = function(kind, x, z)
    local b, rec = find_building(kind, tonumber(x), tonumber(z))
    if not b then log("GM destroy_at：(%s,%s) 处没有 %s", tostring(x), tostring(z), tostring(kind)); return end
    if rec then
      root.pool:despawn(rec)
    elseif b.entity and b.entity.destroy then
      b.entity:destroy()
    end
  end,
  -- 「位于 (x,z) 的 X 受到炸弹伤害 N」编排：直接扣血（死亡走 2 秒碎裂）。
  bomb_damage = function(kind, x, z, dmg)
    local b = find_building(kind, tonumber(x), tonumber(z))
    if not b then log("GM bomb_damage：(%s,%s) 处没有 %s", tostring(x), tostring(z), tostring(kind)); return end
    b.health:damage(tonumber(dmg) or 0)
  end,
  -- 「设定当前波次为 N」编排：波号置 N、倒计时 30、方向未知（重抽）。
  set_wave = function(n)
    root.wave_director:set_wave(tonumber(n) or 1)
  end,
  -- 「随机源固定为最大值」编排：每次随机抽取都取上界，并重抽未公布的方向。
  fix_rng_max = function()
    root.wave_director.rng01 = function() return 1 end
    root.wave_director:reroll_direction()
  end,
  -- 「进入进攻期」编排：直接切换进攻期标志（不生成敌人）。
  enter_assault = function()
    root.wave_director:set_assault(true)
  end,
  -- 「本波全灭」编排：杀死本波全部敌人并退出进攻期。
  wave_cleared = function()
    root.wave_director:kill_all()
    root.wave_director:set_assault(false)
  end,
  -- 「在 (x,z) 生成一个航线朝<方向>的<T>型敌人」编排：计入本波。
  spawn_enemy_at = function(x, z, dir_name, tier)
    local dir = WorldData.direction(tostring(dir_name))
    if not dir then log("GM spawn_enemy_at：未知方向 %s", tostring(dir_name)); return end
    root.wave_director:spawn({
      x = tonumber(x), z = tonumber(z),
      tier = tonumber(tier) or 1,
      heading = { x = dir.x, z = dir.z },
    })
  end,
  -- 「第 N 个敌人死亡」编排。
  kill_enemy_nth = function(n)
    local e = root.enemies[tonumber(n)]
    if e and e.health then e.health:damage(99999) end
  end,
  -- 「位于 (x,z) 的 Turret 枪口朝<方向>」编排：立即设定枪口朝向
  -- （entity 朝向与 target_direction 同步；验收设定初始朝向用）。
  aim_turret = function(x, z, dir_name)
    local dir = WorldData.direction(tostring(dir_name))
    if not dir then log("GM aim_turret：未知方向 %s", tostring(dir_name)); return end
    local b, rec = find_building("Turret", tonumber(x), tonumber(z))
    if not b or not rec then log("GM aim_turret：(%s,%s) 处没有 Turret", tostring(x), tostring(z)); return end
    local turret = rec.epoch
    turret.target_direction = { x = dir.x, z = dir.z }
    turret.muzzle_pinned = true -- 编排设定的朝向保持到首次接敌（见 TurretBehaviour.idle）
    turret.entity:set_rotation(math.atan(dir.z, dir.x))
    log("GM aim_turret(%s,%s) → %s", tostring(x), tostring(z), tostring(dir_name))
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
  -- 当前波次一览（GDD 07 状态：倒计时/方向/进攻期/预算/生成簿记）
  wave = function()
    local w = root.wave_director.wave:now()
    log("WAVE number=%d countdown=%.2f assault=%s front=%s budget_left=%.2f spawned=%d cost_sum=%.2f",
      w.number, w.countdown, tostring(w.assault), tostring(w.front),
      w.budget_left, w.spawned, w.cost_sum)
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
