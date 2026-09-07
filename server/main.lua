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
-- 日志前缀 [bd][server]，供 `$CLI log grep` 提取。GM 面在 server/adapter/gm.lua（挂 _G.bd）。

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
local GM = require("server.adapter.gm")

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

local function mount_adapter(r)
  host.input.set_bounds(r.game_state:level_bounds())
  panel = BuildPanel.create(host, r)
  BuildPanel.update(panel)
  if r.game_state.settle_power then r.game_state:settle_power() end -- 初始布局收敛（GDD 03 R8）
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
-- 动作与读回都在 server/adapter/gm.lua；这里只交出访问器（root/panel 每次重开换对象）。
_G.bd = GM.create({
  host = host,
  root = function() return root end,
  panel = function() return panel end,
  restart = restart_game,
  stats = function() return { ticks = ticks_total, uptime = uptime, seq = seq } end,
  log = log,
})

log("服务端挂载完成：Session(GameRootFull) + Heartbeat 驱动 GameTick(1/30) + RemoteEvent(bd_game) + 放置面板/Restart + 波次阶梯/6 矿点")
