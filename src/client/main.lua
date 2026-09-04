-- #10 真机烟测（客户端）：快照→EUI 最小回路 + 移交探针观察端。
-- #7 决策：客户端 v1 零 spoke 树（哑镜像），本文件不 require src.spoke。
-- 日志前缀 [smoke][client]，供 `$CLI log grep smoke` 提取。
--
-- 观察点：
--   C1 RemoteEvent 通道：先监听后握手（client_ready 重试至首快照），快照序号缺口、突发送达计数
--   C2 快照 → EUI 文本（双端通道最小回路）
--   C3 Unit 复制观察（#7-P1）：mover 首见/采样/消失时刻；染色读回（#9-P1）；EffectUnit 可见性
--   C4 相机探针（#8-P5/P6/P7）：Mode=NONE 定点俯视、ManualRefresh 必要性、ORTHOGRAPHIC 试验
--   C5 输入探针（#8-P2/P4/P1）：透明 EUIImage 捕获层 + UserInputService.InputBegan + SimulateTap

local Players = game:GetService("Players")
local World = game:GetService("World")
local RunService = game:GetService("RunService")
local CameraService = game:GetService("CameraService")
local UIS = game:GetService("UserInputService")

local function log(fmt, ...)
  print("[smoke][client] " .. string.format(fmt, ...))
end

elapsed = 0 -- 客户端本地时钟（秒），事件回调与主循环共享

local function try(tag, fn)
  local ok, err = pcall(fn)
  if not ok then log("%s 失败: %s", tag, tostring(err)) end
  return ok
end

-- ── C1 RemoteEvent 通道（先监听后握手，F11 文档范式）─────────────────
local re = RemoteEvent.New("bd_smoke")
local stats = {
  snapshots = 0, last_seq = 0, gaps = 0,
  burst = 0, burst_expected = 100, burst_seen = {},
  retries = 0, got_hello = false, first_snapshot_at = nil,
}

re.OnClientEvent:Connect(function(args)
  if type(args) ~= "table" then return end
  if args.kind == "snapshot" or args.kind == "hello_after_ready" then
    stats.snapshots = stats.snapshots + 1
    if stats.first_snapshot_at == nil then
      stats.first_snapshot_at = elapsed
      log("首快照到达 @%.2fs（本地时钟）tick=%s seq=%s server_up=%ss",
        elapsed, tostring(args.tick), tostring(args.seq), tostring(args.up))
    end
    if args.kind == "hello_after_ready" then stats.got_hello = true end
    if stats.last_seq > 0 and args.seq ~= stats.last_seq + 1 then
      local lost = args.seq - stats.last_seq - 1
      if lost > 0 then
        stats.gaps = stats.gaps + lost
        log("快照序号缺口: %d -> %d（丢 %d）", stats.last_seq, args.seq, lost)
      end
    end
    stats.last_seq = args.seq
    if label then
      try("更新 EUI 文本", function()
        label.Text = string.format("smoke tick=%s seq=%s up=%ss",
          tostring(args.tick), tostring(args.seq), tostring(args.up))
      end)
    end
  elseif args.kind == "burst" then
    if not stats.burst_seen[args.seq] then
      stats.burst_seen[args.seq] = true
      stats.burst = stats.burst + 1
    end
  end
end)
re:FireServer({ kind = "client_ready" })
log("client_ready 已发送（先监听后握手）")

-- ── C2/C5 EUI：快照文本 + 透明捕获层（PlayerGui 就绪后创建）────────
local label, capture
local screen_res

local function setup_eui()
  local localPlayer = Players.LocalPlayer
  if not localPlayer or not localPlayer.PlayerGui then return false end
  local mgr = localPlayer.PlayerGui.EuiManager
  if not mgr then return false end
  local root = mgr:GetRootNode()
  local res = mgr:GetDeviceResolution()
  if not root or not res then return false end
  screen_res = res

  try("创建快照文本", function()
    label = World:CreateUnit("EUITextLabel", {
      Parent = root,
      Name = "smoke_label",
      Position = Vector2.New(res.X / 2, res.Y - 80),
      Size = Vector2.New(900, 70),
      FontSize = 36,
      Text = "smoke: waiting snapshot...",
      TextColor = Color.New(255, 255, 255, 255),
      OutlineEnabled = true,
      OutlineColor = Color.New(0, 0, 0, 255),
      OutlineWidth = 4,
    })
    log("EUI 快照文本已创建 res=%s,%s", tostring(res.X), tostring(res.Y))
  end)

  -- 全屏透明捕获层：Opacity=0 命中探针（#8-P4）+ 触摸等价（#8-P2）
  try("创建透明捕获层", function()
    capture = World:CreateUnit("EUIImage", {
      Parent = root,
      Name = "smoke_capture",
      Position = Vector2.New(res.X / 2, res.Y / 2),
      Size = Vector2.New(res.X, res.Y),
      Opacity = 0,
      Color = Color.New(255, 255, 255, 255),
      TouchEnabled = true,
      SwallowTouchEnabled = true,
      LocalZOrder = -100,
    })
    capture.OnTouchBegan:Connect(function(info)
      log("PROBE touch-began id=%s began=(%s,%s) [P4: Opacity=0 命中? P2: 鼠标触发?]",
        tostring(info.TouchID), tostring(info.BeganPosition.X), tostring(info.BeganPosition.Y))
    end)
    capture.OnTouchEnded:Connect(function(info)
      log("PROBE touch-ended id=%s ended=(%s,%s)",
        tostring(info.TouchID), tostring(info.EndedPosition.X), tostring(info.EndedPosition.Y))
    end)
    log("透明捕获层已创建（Opacity=0, TouchEnabled, Swallow）")
  end)
  return true
end

-- 输入探针：UserInputService.InputBegan（#8-P2 鼠标等价）
try("挂 InputBegan", function()
  UIS.InputBegan:Connect(function(input, processed)
    local t = input.UserInputType
    if t == Enums.UserInputType.MouseButton1
      or t == Enums.UserInputType.MouseButton2
      or t == Enums.UserInputType.Touch
      or t == Enums.UserInputType.Keyboard then
      log("PROBE InputBegan type=%d processed=%s pos=(%s,%s,%s) [P2]",
        t, tostring(processed),
        tostring(input.Position.X), tostring(input.Position.Y), tostring(input.Position.Z))
    end
  end)
end)

-- ── C3 复制单位观察 ─────────────────────────────────────────────────
local probe = {
  mover_first = nil, mover_lost = nil, samples = 0,
  rings_logged = false, line_logged = false, color_logged = {},
}
local sample_acc = 0

local function observe_units(dt)
  local mover = World:FindFirstChild("smoke_mover", true)
  if mover then
    if not probe.mover_first then
      probe.mover_first = elapsed
      log("PROBE mover 首见 @%.2fs pos=(%s,%s,%s)",
        elapsed, tostring(mover.Position.X), tostring(mover.Position.Y), tostring(mover.Position.Z))
    end
    sample_acc = sample_acc + dt
    if sample_acc >= 0.5 then
      sample_acc = 0
      probe.samples = probe.samples + 1
      local c = mover.ModelColor1
      local color_str
      if type(c) == "table" and c.R ~= nil then
        color_str = string.format("(%s,%s,%s,%s)",
          tostring(c.R), tostring(c.G), tostring(c.B), tostring(c.A))
      else
        color_str = tostring(c)
      end
      log("PROBE mover 采样#%d @%.2fs x=%s color=%s",
        probe.samples, elapsed, tostring(mover.Position.X), color_str)
    end
  elseif probe.mover_first and not probe.mover_lost then
    probe.mover_lost = elapsed
    log("PROBE mover 消失（Destroy 复制到达）@%.2fs", elapsed)
  end

  if not probe.rings_logged and elapsed > 3 then
    local rs = World:FindFirstChild("smoke_ring_small", true)
    local rb = World:FindFirstChild("smoke_ring_big", true)
    if rs or rb or elapsed > 8 then
      probe.rings_logged = true
      log("PROBE EffectUnit 复制: ring_small=%s ring_big=%s @%.2fs",
        tostring(rs ~= nil), tostring(rb ~= nil), elapsed)
    end
  end
  if not probe.line_logged and elapsed > 3 then
    local la = World:FindFirstChild("smoke_line_a", true)
    local lb = World:FindFirstChild("smoke_line_b", true)
    local fx = World:FindFirstChild("smoke_line", true)
    if la or fx or elapsed > 8 then
      probe.line_logged = true
      log("PROBE 连线单位复制: line_a=%s line_b=%s line_fx=%s @%.2fs",
        tostring(la ~= nil), tostring(lb ~= nil), tostring(fx ~= nil), elapsed)
    end
  end
end

-- ── C4 相机探针时间线 ───────────────────────────────────────────────
local cam_applied, cam_refreshed, cam_ortho, cam_restored, cam_tapped = false, false, false, false, false
local cam_log_acc = 0

local function apply_camera(refresh)
  local cam = World.CurrentCamera
  if not cam then log("相机探针: 无 CurrentCamera"); return end
  try("写相机属性", function()
    cam.Mode = Enums.CameraMode.NONE
    cam.Priority = 100
    cam.Position = Vector3.New(0, 60, 0)
    cam.Pitch = -90
    cam.Yaw = 0
    cam.FieldOfView = 45
    if refresh then CameraService:ManualRefresh() end
    log("相机探针: 属性已写入 refresh=%s 读回 pos=%s pitch=%s mode=%s",
      tostring(refresh), tostring(cam.Position), tostring(cam.Pitch), tostring(cam.Mode))
  end)
  try("读 LiveCamera", function()
    local live = CameraService.LiveCamera
    if live then
      log("相机探针: LiveCamera pos=%s pitch=%s active=%s",
        tostring(live.Position), tostring(live.Pitch), tostring(live.IsActive))
    else
      log("相机探针: LiveCamera 为 nil")
    end
  end)
end

local function camera_timeline(dt)
  if not cam_applied and elapsed >= 2 then
    cam_applied = true
    apply_camera(false) -- 先不 ManualRefresh：验证属性写入是否即时生效（P7）
  end
  if not cam_refreshed and elapsed >= 5 then
    cam_refreshed = true
    CameraService:ManualRefresh()
    log("相机探针: ManualRefresh 已调用（P7 对照）")
    apply_camera(true)
  end
  if not cam_ortho and elapsed >= 16 then
    cam_ortho = true
    try("ORTHOGRAPHIC 试验", function()
      local cam = World.CurrentCamera
      cam.ProjectionType = Enums.CameraProjection.ORTHOGRAPHIC
      CameraService:ManualRefresh()
      log("相机探针: ProjectionType=ORTHOGRAPHIC（P6 试验）")
    end)
  end
  if not cam_restored and elapsed >= 20 then
    cam_restored = true
    try("恢复透视", function()
      local cam = World.CurrentCamera
      cam.ProjectionType = Enums.CameraProjection.PERSPECTIVE
      CameraService:ManualRefresh()
      log("相机探针: 恢复 PERSPECTIVE")
    end)
  end
  -- P5 稳定性：每 3s 记录一次相机状态是否被覆写（脱离蛋仔跟随是否保持）
  cam_log_acc = cam_log_acc + dt
  if cam_applied and cam_log_acc >= 3 then
    cam_log_acc = 0
    try("相机稳定性采样", function()
      local cam = World.CurrentCamera
      if cam then
        log("相机探针[稳定性] @%.2fs pos=%s pitch=%s mode=%s proj=%s",
          elapsed, tostring(cam.Position), tostring(cam.Pitch),
          tostring(cam.Mode), tostring(cam.ProjectionType))
      end
    end)
  end
end

-- ── 主循环 ──────────────────────────────────────────────────────────
local eui_ready = false
local ready_retry_acc = 0
local report_acc = 0

RunService.Heartbeat:Connect(function(deltaTime)
  elapsed = elapsed + deltaTime

  if not eui_ready then
    eui_ready = setup_eui()
    if eui_ready then log("EUI 就绪 @%.2fs", elapsed) end
  end

  -- client_ready 重试：直到收到首快照（送达可靠性补偿，F11）
  if stats.first_snapshot_at == nil then
    ready_retry_acc = ready_retry_acc + deltaTime
    if ready_retry_acc >= 2 then
      ready_retry_acc = 0
      stats.retries = stats.retries + 1
      re:FireServer({ kind = "client_ready" })
      log("client_ready 重试#%d（尚未收到快照）", stats.retries)
    end
  end

  observe_units(deltaTime)
  camera_timeline(deltaTime)

  -- SimulateTap 探针（#8-P2 第 3 问）：24s 处注入一次屏幕中心点击
  if not cam_tapped and elapsed >= 24 and screen_res then
    cam_tapped = true
    try("SimulateTap", function()
      local sg = Players.LocalPlayer.PlayerGui.ScreenGui
      sg:SimulateTap(Vector2.New(screen_res.X / 2, screen_res.Y / 2))
      log("PROBE SimulateTap 已注入屏幕中心（观察是否触发 EUI touch）")
    end)
  end

  -- 每 5s 向服务端回报客户端统计
  report_acc = report_acc + deltaTime
  if report_acc >= 5 then
    report_acc = 0
    try("回报统计", function()
      re:FireServer({
        kind = "client_stats",
        snapshots = stats.snapshots,
        gaps = stats.gaps,
        burst = stats.burst,
        burst_expected = stats.burst_expected,
        mover_first = probe.mover_first and string.format("%.2f", probe.mover_first) or nil,
        mover_lost = probe.mover_lost and string.format("%.2f", probe.mover_lost) or nil,
        samples = probe.samples,
        retries = stats.retries,
      })
    end)
    log("周期统计 @%.2fs: snapshots=%d gaps=%d burst=%d/%d retries=%d mover_first=%s mover_lost=%s",
      elapsed, stats.snapshots, stats.gaps, stats.burst, stats.burst_expected,
      stats.retries, tostring(probe.mover_first), tostring(probe.mover_lost))
  end
end)

log("客户端烟测挂载完成：快照监听 + EUI 渲染 + 探针观察器")
