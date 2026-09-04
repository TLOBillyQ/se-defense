-- #19 垂直切片（服务端）：GameRootFull + Core + 单波敌人 + 最简 HUD。
--
-- 架构（#7 决议）：
--   - 服务端一棵 Auto 树（GameRootFull 全业务组合根，业务零改动经 swap 接入适配层）；
--   - RunService.Heartbeat 固定步长积累驱动 GameTick(1/30)，整帧派发由
--     SpokeRuntime.batch 合并成一次 flush（#10 实测 30fps 稳定、jitter=0）；
--   - host.eui 快照出口每帧 dirty 即发（#18 决策 2），client_ready 握手 /
--     seq 缺口 resync 走全量（#18 决策 1）；
--   - 输入反向通道：客户端捕获层 → FireServer 意图 → host.input 队列（#7 决策 2、#8 D5）。
--
-- 切片边界（票面 + #9 D4 垂直切片基线）：
--   单波次配置（waves 不升级）、不挂放置 UI/取消按钮（「建筑与放置」是下一片）、
--   不挂 Restart（「胜负与重开」后续片，reset_scene 适配器已备好）。
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

local host = require("src.adapter.host")
local spoke = require("src.spoke")
local SpokeRuntime = require("src.spoke.runtime.spoke_runtime")
local GameTick = require("examples.base_defence.game_tick")
local GameRootFull = require("examples.base_defence.game_root_full")

-- ── 切片配置 ────────────────────────────────────────────────────────
-- 棋盘 40×40、Core 置世界原点、单位 1:1（#8 D2 假设）。
-- 单波：waves 只定义第 1 波，后续波沿用全局同配置（不升级 = 「单波敌人」）。
local STEP = 1 / 30        -- 对齐宿主 30fps 逻辑帧（#7-A2，#10 实测通过）
local MAX_CATCHUP = 4      -- 积累上限 4 步/帧，超限丢弃（#7-A1，#10 实测通过）
local AUTO_START_AT = 3    -- 试玩开局 3s 后自动进入 Playing（Pregame 可观察 HUD）

local tick = GameTick.new(STEP)

local root = GameRootFull.new({
  host = host,
  game_tick = tick,
  game_state = {
    core_position = { x = 0, y = 0, z = 0 },
    dimensions = { x = 40, z = 40 },
    start_money = 100,
    core_max_hp = 50,
  },
  wave_director = {
    lull_duration = 8,
    front_reveal_time = 3,
    spawn_interval = 1,
    enemy_count = 5,
    waves = {
      [1] = { enemy_count = 5, spawn_interval = 1, enemy = { prefab = "enemy" } },
    },
  },
  enemy = {
    prefab = "enemy",
    max_hp = 10,
    move_speed = 3,
    stop_distance = 1.5,
    fire_rate = 1,
    damage = 5,
  },
})

local tree = spoke.SpokeTree.spawn(root)
log("Auto 树 spawn 完成 fault=%s detached=%s", tostring(tree.fault), tostring(tree.is_detached))

-- 棋盘边界注入输入适配层（#8 D2：界外点 → nil）
host.input.set_bounds(root.game_state:level_bounds())

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
          host.input.intent_tap(x, z)
        else
          host.input.intent_hover(x, z)
        end
      elseif itype == "hover" and args.x == nil then
        host.input.intent_hover(nil, nil) -- 抬指/出界
      end
    elseif itype == "cancel" then
      host.input.intent_cancel()
    end
  end
end)

-- ── Heartbeat 固定步长驱动器（#7 决策 3 + #10 验证姿势）──────────────
local acc = 0
local uptime = 0
local ticks_total = 0
local started = false

RunService.Heartbeat:Connect(function(deltaTime)
  uptime = uptime + deltaTime

  if not started and uptime >= AUTO_START_AT then
    started = true
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

  -- 快照：每帧派发结束 dirty 即发（#18 决策 2，无额外节流）
  local delta = host.eui.drain()
  if delta then
    send("delta", delta)
  end
end)

-- ── GM 面（$CLI exec --platform server 驱动；自动化验证优先 #1 偏好 2）──
_G.bd = {
  status = function()
    local gs = root.game_state
    log("STATUS mode=%s ticks=%d uptime=%.1fs money=%s core_hp=%.2f entities=%d eui_nodes=%d seq=%d gen=%d",
      tostring(gs.mode:now()), ticks_total, uptime,
      tostring(gs.money:now()),
      gs.core and gs.core.health.hp_fraction:now() or -1,
      #host.entity.all(), #host.eui.order, seq, host.eui.generation)
  end,
  start = function()
    if not started then
      started = true
      root.game_state:start_game()
      log("GM start_game")
    end
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
  -- 进入放置模式（「建筑与放置」片的预验口；本切片不挂 UI 按钮）
  place = function(key)
    local spec = root.building_specs and root.building_specs[key]
    if spec then
      root.board_interactions.placing:set(spec)
      log("GM place(%s)：placing 已置位", tostring(key))
    else
      log("GM place(%s)：未知 spec", tostring(key))
    end
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

log("垂直切片服务端挂载完成：GameRootFull + Heartbeat 驱动 GameTick(1/30) + RemoteEvent(bd_game)")
