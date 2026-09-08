-- 服务端入口：装配 Session(GameRootFull) + Heartbeat 固定步长驱动 + 网络/GM 面。
--
-- 架构决策见 docs/adr/（0001 双端与节拍、0002 快照协议、0003 形状双路由、
-- 0004 上帝视角输入、0006 ring 改走快照——取代 0003 里 ring 就地渲染的那半）。
--   server/match/         组合根（GameRootFull）与对局流程
--   server/{ui,board,power,economy,defense,waves,units,kernel}/  业务包（spoke 树）
--   server/host/          宿主层：host 表（eui/input/entity/reset_scene）+ scene/convert
--   server/ui/            表现层 + 放置面板 / 操作日志
--   server/net.lua        RemoteEvent bd_game：快照下行、握手/意图上行
--   server/gm.lua         _G.bd（$CLI exec / 集成测试编排面）
--
-- 规则与数值真源：docs/gdd/（世界常量在 server/kernel/world_data.lua）。
-- 日志前缀 [bd][server]，供 `$CLI log grep` 提取。

local RunService = game:GetService("RunService")

local function log(fmt, ...)
  print("[bd][server] " .. string.format(fmt, ...))
end

local host = require("server.host")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local GameTick = require("server.kernel.game_tick")
local GameRootFull = require("server.match.game_root_full")
local Session = require("server.match.session")
local WorldData = require("server.kernel.world_data")
local BuildPanel = require("server.ui.build_panel")
local OperationLog = require("server.ui.operation_log")
local Net = require("server.net")
local GM = require("server.gm")

-- ── 对局配置 ────────────────────────────────────────────────────────
-- 棋盘 40×40、Core 置世界原点、单位 1:1。
local STEP = 1 / 30        -- 对齐宿主 30fps 逻辑帧（ADR 0001）
local MAX_CATCHUP = 4      -- 积累上限 4 步/帧，超限丢弃（ADR 0001）

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

-- 实时操作日志：与放置面板同为适配层挂件，跨整局/重开持同一对象，
-- 业务（board_interactions）经组合根注入其 push 接口；重开时 host.eui.reset()
-- 清空节点，由挂载流程 op_log:reset() 重建。
local op_log = OperationLog.create(host)

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
  op_log = op_log,
}

-- ── 会话：Auto 树 + GameRootFull 组合根；restart() 拆树 → 清场 → 重建 ──
local session = Session.spawn(GAME_CONFIG, "Auto", GameRootFull)
local root = session.root
local tree = session.tree
log("Auto 树 spawn 完成 fault=%s detached=%s", tostring(tree.fault), tostring(tree.is_detached))

-- 树之外、每局都要随 root 重建的适配层挂件：棋盘边界 + 放置面板。
local panel

local function mount_adapter(r)
  host.input.set_bounds(r.game_state:level_bounds())
  op_log:reset()
  panel = BuildPanel.create(host, r, op_log)
  BuildPanel.update(panel)
  if r.game_state.settle_power then r.game_state:settle_power() end -- 初始布局收敛（GDD 03 R8）
end
mount_adapter(root)

-- 运行时静态场景（草地地面 + 外围晶石点缀）：仅视觉，不进 entity.by_id，
-- 不参与 host:reset_scene()，因此只在加载时构建一次，不随 restart 重建。
-- 棋盘半径由此处注入：适配层不许反向依赖 server.kernel.world_data。
require("server.host.scene").build(WorldData.board.max)

local net

-- Restart（#28）：业务 session.lua 三步（dispose → host:reset_scene() → 重建），
-- 随后适配层重挂、广播 reset 全量。不在 tick 派发中途调用（RemoteEvent / GM 都在帧间到达）。
local function restart_game(why)
  local old_gen = host.eui.generation
  session:restart()
  root = session.root
  tree = session.tree
  mount_adapter(root)
  op_log:push("system", "重新开始对局")
  if _G.bd then _G.bd.root = root end
  net:send_reset()
  log("RESTART(%s) gen %d → %d：树重建 fault=%s，entities=%d nodes=%d，回 Pregame 等待开始对局",
    tostring(why), old_gen, host.eui.generation, tostring(tree.fault),
    #host.entity.all(), #host.eui.order)
end

net = Net.create({
  host = host, log = log,
  root = function() return root end,
  panel = function() return panel end,
  op_log = function() return op_log end,
  restart = restart_game,
})

-- ── Heartbeat 固定步长驱动器（ADR 0001）─────────────────────────────
local uptime = 0
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
      host.input.reset_frame() -- "按下只持续一帧"
      acc = acc - STEP
      steps = steps + 1
      ticks_total = ticks_total + 1
    end
  end)
  if acc >= STEP then
    acc = 0 -- 丢弃多余时间，不做追赶
  end

  -- 放置面板投影（余额/选中/可见），再取快照增量下发
  BuildPanel.update(panel)
  net:flush_delta()
end)

-- ── GM 面（$CLI exec --platform server 驱动）──────────────────────────
_G.bd = GM.create({
  host = host,
  root = function() return root end,
  panel = function() return panel end,
  restart = restart_game,
  stats = function() return { ticks = ticks_total, uptime = uptime, seq = net.seq } end,
  log = log,
})

log("服务端挂载完成：Session(GameRootFull) + Heartbeat 驱动 GameTick(1/30) + RemoteEvent(bd_game) + 放置面板/Restart")
