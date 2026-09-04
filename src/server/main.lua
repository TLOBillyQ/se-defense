-- #10 真机烟测（服务端）：spoke 运行时在 SE 启动。
-- 票面：试玩中 tick 计数增长、受控 fault 被三层错误边界捕获、探针子集结论。
-- 日志前缀 [smoke][server]，供 `$CLI log grep smoke` 提取。
--
-- 烟测点：
--   S1 require 根语义探针（#6 移交 / #7-A5）：工作区根直接 require src.* / examples.*
--   S2 Heartbeat 固定步长积累驱动 GameTick(1/30) + 最小 Auto 树 tick 计数 + SpokeRuntime.batch
--   S3 三层错误边界：tick 150 受控注入 fault（effect 内 error），观察 tree.fault 与日志
--   S4 RemoteEvent 快照通道 + client_ready 握手 + 突发窗口（送达率/乱序探针）
--   S5 Unit 复制探针（#7-P1 / realm F18）：Kinematic WorldUnit 每 tick 写 Position + Destroy；染色（#9-P1）
--   S6 服务端 EffectUnit 复制 + 特效半径缩放（#9-P3）+ Attach 跟随（#9-P4）
--   S7 Heartbeat 实测间隔统计（含负载脉冲下的抖动）
--   S8 dispose：_G.smoke_dispose 注入执行（试玩中验证拆树）

-- 环境事实：SE 服务端 Lua 沙盒缺少标准库 `rawequal` 的问题已由 spoke-lua
-- upstream 在 epoch_cursor / introspect_labels 中兜底（spoke-lua #53 / #54）。
-- se-defense 不再注入全局 polyfill。
local World = game:GetService("World")
local RunService = game:GetService("RunService")

local function log(fmt, ...)
  print("[smoke][server] " .. string.format(fmt, ...))
end

local function try(tag, fn)
  local ok, err = pcall(fn)
  if not ok then log("%s 失败: %s", tag, tostring(err)) end
  return ok
end

-- ── S1 require 根语义探针 ─────────────────────────────────────────────
local probe_results = {}
local function probe_require(path)
  local ok, err = pcall(require, path)
  probe_results[#probe_results + 1] =
    string.format("%s = %s", path, ok and "OK" or ("FAIL " .. tostring(err)))
  return ok
end

local ok_spoke = probe_require("src.spoke")
local ok_runtime = probe_require("src.spoke.runtime.spoke_runtime")
local ok_tickmod = probe_require("examples.base_defence.game_tick")
probe_require("examples.base_defence.game_root") -- 组合根模块链（含 swap 后的 host_mock）
for _, line in ipairs(probe_results) do log("require-probe %s", line) end

if not (ok_spoke and ok_runtime and ok_tickmod) then
  log("FATAL: spoke 运行时 require 失败，烟测无法继续")
  return
end

local spoke = require("src.spoke")
local SpokeRuntime = require("src.spoke.runtime.spoke_runtime")
local GameTick = require("examples.base_defence.game_tick")

-- ── S2/S3 最小 Auto 树（tick 计数 + 受控 fault 注入）────────────────
local STEP = 1 / 30
local MAX_CATCHUP = 4      -- #7 假设 A1：积累上限 4 步/帧，超限丢弃多余时间
local FAULT_AT_TICK = 150  -- 5s 处注入受控 fault

local tick_count_state = spoke.State.new("smoke_tick_count", 0)
local fault_armed_state = spoke.State.new("smoke_fault_armed", false)
local last_rendered_tick = -1
local render_count = 0
local fault_seen = false

local smoke_root = spoke.Effect.new("SmokeRoot", function(s)
  -- 渲染出口：真产品里这里写 EUI 快照登记表；烟测只记录渲染节奏。
  s:effect(function(s)
    last_rendered_tick = s:d(tick_count_state)
    render_count = render_count + 1
  end)
  -- 受控 fault：fault_armed 置位后在 flush 内抛错，验证三层错误边界
  -- （Epoch fault 包装 → 树 faulted 停 flush → SpokeRuntime xpcall 记日志不 rethrow）。
  s:effect(function(s)
    if s:d(fault_armed_state) and not fault_seen then
      fault_seen = true
      error("SMOKE_INJECTED_FAULT 受控故障：验证三层错误边界")
    end
  end)
end)

local tree = spoke.SpokeTree.spawn("smoke-tree", smoke_root)
log("Auto 树 spawn 完成 fault=%s detached=%s 初始渲染 render_count=%d",
  tostring(tree.fault), tostring(tree.is_detached), render_count)

-- ── S4 RemoteEvent 通道 ─────────────────────────────────────────────
local re = RemoteEvent.New("bd_smoke")
local snapshot_seq = 0
local client_ready = false
local client_stats_count = 0

local hb = {
  frames = 0, uptime = 0,
  dt_min = math.huge, dt_max = 0, dt_sum = 0, jitter_max = 0, slow_frames = 0,
  multi_step_frames = 0, dropped_steps = 0,
}
local ticks_total = 0

local function send_snapshot(kind)
  snapshot_seq = snapshot_seq + 1
  re:FireAllClients({
    kind = kind or "snapshot",
    seq = snapshot_seq,
    tick = ticks_total,
    up = math.floor(hb.uptime),
  })
end

re.OnServerEvent:Connect(function(player, args)
  -- F10：入参按不可信输入校验
  if type(args) ~= "table" then
    log("OnServerEvent 拒绝非 table 入参 type=%s", type(args))
    return
  end
  local kind = args.kind
  if kind == "client_ready" then
    if not client_ready then
      client_ready = true
      log("client_ready 握手到达，立即补发最新快照")
    else
      log("client_ready 重发到达（客户端未收到首快照，重试中）")
    end
    send_snapshot("hello_after_ready")
  elseif kind == "client_stats" then
    client_stats_count = client_stats_count + 1
    log("client-stats#%d: snapshots=%s gaps=%s burst=%s/%s mover_first=%ss mover_lost=%ss samples=%s retries=%s",
      client_stats_count,
      tostring(args.snapshots), tostring(args.gaps),
      tostring(args.burst), tostring(args.burst_expected),
      tostring(args.mover_first), tostring(args.mover_lost),
      tostring(args.samples), tostring(args.retries))
  else
    log("OnServerEvent 未知 kind=%s", tostring(kind))
  end
end)

-- ── S5/S6 单位与特效探针 ────────────────────────────────────────────
local mover, ring_small, ring_big, line_a, line_b, line_fx
local mover_destroyed = false
local line_b_moved = false

local function spawn_probe_units()
  try("创建 mover", function()
    mover = World:CreateUnit("WorldUnit", {
      Name = "smoke_mover",
      RenderMeshId = "official://mesh/59268",
      BodyType = Enums.BodyType.Kinematic,
      CanCollide = false,
      Scale = Vector3.New(1, 1, 1),
      Position = Vector3.New(-6, 0.5, 0),
    })
    log("PROBE mover 已创建（Kinematic 立方体 @(-6,0.5,0)）tick=%d", ticks_total)
  end)
  try("创建 ring_small", function()
    ring_small = World:CreateUnit("EffectUnit", {
      Name = "smoke_ring_small",
      EffectId = "official://effect/6079",
      Duration = -1,
      Scale = Vector3.New(1, 1, 1),
      Position = Vector3.New(-2, 0.05, -5),
    })
    log("PROBE ring_small 已创建 Scale=(1,1,1) @(-2,-5)")
  end)
  try("创建 ring_big", function()
    ring_big = World:CreateUnit("EffectUnit", {
      Name = "smoke_ring_big",
      EffectId = "official://effect/6079",
      Duration = -1,
      Scale = Vector3.New(3, 3, 3),
      Position = Vector3.New(3, 0.05, -5),
    })
    log("PROBE ring_big 已创建 Scale=(3,3,3) @(3,-5)")
  end)
  try("创建连线单位", function()
    line_a = World:CreateUnit("WorldUnit", {
      Name = "smoke_line_a",
      RenderMeshId = "official://mesh/59268",
      BodyType = Enums.BodyType.Kinematic,
      CanCollide = false,
      Scale = Vector3.New(0.5, 0.5, 0.5),
      Position = Vector3.New(-4, 0.5, 5),
    })
    line_b = World:CreateUnit("WorldUnit", {
      Name = "smoke_line_b",
      RenderMeshId = "official://mesh/59268",
      BodyType = Enums.BodyType.Kinematic,
      CanCollide = false,
      Scale = Vector3.New(0.5, 0.5, 0.5),
      Position = Vector3.New(4, 0.5, 5),
    })
    line_fx = World:CreateUnit("EffectUnit", {
      Name = "smoke_line",
      EffectId = "official://effect/4506",
      Duration = -1,
      Position = Vector3.New(-4, 0.5, 5),
    })
    local ok1 = pcall(function() line_fx:StartposAttach(line_a, "", Vector3.New(0, 0, 0)) end)
    local ok2 = pcall(function() line_fx:EndposAttach(line_b, "", Vector3.New(0, 0, 0)) end)
    log("PROBE 连线 attach start=%s end=%s（socket=''）", tostring(ok1), tostring(ok2))
  end)
end

-- ── S2 每 tick 逻辑 ─────────────────────────────────────────────────
local tick = GameTick.new(STEP)

tick:listen(function(dt)
  ticks_total = ticks_total + 1
  local t = ticks_total

  -- 计数写入 + 受控 fault 武装：整帧派发由外层 batch 合并成一次 flush
  tick_count_state:set(t)
  if t == FAULT_AT_TICK then
    fault_armed_state:set(true)
    log("FAULT 已武装 @tick=%d（下一次 flush 内 effect 将抛错）", t)
  end

  -- 快照：每 30 tick（1 逻辑秒）一次
  if t % 30 == 0 then send_snapshot("snapshot") end

  -- 突发窗口：tick 151..160 每 tick 10 条（共 100 条）测送达率
  if t >= 151 and t <= 160 then
    for i = 1, 10 do
      re:FireAllClients({ kind = "burst", seq = (t - 151) * 10 + i })
    end
  end

  -- mover：tick 60 创建，60..120 每 tick +0.1x，90 染色，180 Destroy
  if t == 45 then spawn_probe_units() end
  if mover and t >= 60 and t <= 120 then
    local x = -6 + (t - 60) * 0.1
    mover.Position = Vector3.New(x, 0.5, 0)
    if t % 20 == 0 then log("PROBE mover Position 写入 x=%.1f @tick=%d", x, t) end
  end
  if mover and t == 90 then
    try("mover 染色", function()
      mover.ModelColor1 = Color.New(255, 0, 0, 255)
      log("PROBE mover ModelColor1 写红 @tick=90")
    end)
  end
  if mover and t == 180 and not mover_destroyed then
    mover_destroyed = true
    try("mover Destroy", function()
      mover:Destroy()
      log("PROBE mover Destroy @tick=180")
    end)
  end

  -- 连线端点 b 移动（Attach 跟随探针）
  if line_b and t == 240 and not line_b_moved then
    line_b_moved = true
    try("line_b 移动", function()
      line_b.Position = Vector3.New(4, 0.5, 9)
      log("PROBE line_b 移动到 z=9 @tick=240（观察连线是否跟随）")
    end)
  end

  -- fault 后渲染冻结确认
  if t == FAULT_AT_TICK + 30 then
    log("FAULT 后 30tick：tree.fault=%s last_rendered=%d render_count=%d（应停增）",
      tostring(tree.fault), last_rendered_tick, render_count)
  end
end)

-- ── S7/S2 Heartbeat 驱动器（固定步长积累）────────────────────────────
local load_impulse_at = { [240] = true, [540] = true } -- 约 8s/18s 注入负载脉冲
local acc = 0

RunService.Heartbeat:Connect(function(deltaTime)
  hb.frames = hb.frames + 1
  hb.uptime = hb.uptime + deltaTime
  hb.dt_sum = hb.dt_sum + deltaTime
  if deltaTime < hb.dt_min then hb.dt_min = deltaTime end
  if deltaTime > hb.dt_max then hb.dt_max = deltaTime end
  local jitter = math.abs(deltaTime - STEP)
  if jitter > hb.jitter_max then hb.jitter_max = jitter end
  if deltaTime > STEP * 1.5 then hb.slow_frames = hb.slow_frames + 1 end

  -- 负载脉冲：帧内忙等，观察下一帧 deltaTime 与积累追赶
  if load_impulse_at[hb.frames] then
    local n = 0
    for i = 1, 300000 do n = n + math.sqrt(i) end
    log("LOAD 脉冲帧 #%d 已执行（哨兵=%.0f），观察后续 dt", hb.frames, n % 7)
  end

  acc = acc + deltaTime
  local steps = 0
  SpokeRuntime.batch(function()
    while acc >= STEP and steps < MAX_CATCHUP do
      tick:tick(STEP)
      acc = acc - STEP
      steps = steps + 1
    end
  end)
  if acc >= STEP then
    local dropped = math.floor(acc / STEP)
    hb.dropped_steps = hb.dropped_steps + dropped
    acc = 0 -- 丢弃多余时间（#7 决策：单人玩法不做追赶）
  end
  if steps > 1 then hb.multi_step_frames = hb.multi_step_frames + 1 end

  -- 周期统计（每 10s）
  if hb.frames % 300 == 0 then
    log("HB 统计 @%.0fs: frames=%d dt_min=%.4f dt_max=%.4f dt_avg=%.4f jitter_max=%.4f slow=%d 多步帧=%d 丢弃步=%d ticks=%d rendered=%d/%d次",
      hb.uptime, hb.frames, hb.dt_min, hb.dt_max, hb.dt_sum / hb.frames,
      hb.jitter_max, hb.slow_frames, hb.multi_step_frames, hb.dropped_steps,
      ticks_total, last_rendered_tick, render_count)
  end
end)

-- ── S8 dispose / 状态注入点（经 $CLI exec --platform server 调用）────
_G.smoke_status = function()
  log("STATUS ticks=%d frames=%d uptime=%.1fs rendered=%d（%d 次）fault=%s detached=%s snapshots=%d ready=%s",
    ticks_total, hb.frames, hb.uptime, last_rendered_tick, render_count,
    tostring(tree.fault), tostring(tree.is_detached), snapshot_seq, tostring(client_ready))
end

_G.smoke_dispose = function()
  log("DISPOSE 调用前: fault=%s detached=%s render_count=%d",
    tostring(tree.fault), tostring(tree.is_detached), render_count)
  local ok, err = pcall(function() tree:dispose() end)
  log("DISPOSE 结果 ok=%s err=%s detached=%s", tostring(ok), tostring(err), tostring(tree.is_detached))
end

log("服务端烟测挂载完成：Heartbeat 驱动 GameTick(1/30) + Auto 树 + RemoteEvent(bd_smoke)")
