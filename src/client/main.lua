-- #19 垂直切片（客户端）：哑镜像渲染 + 固定俯视相机 + 棋盘输入捕获。
--
-- 架构（#7/#8/#18 决议）：
--   - 客户端零 spoke 树（#7-A6）：RemoteEvent 快照 → eui_render 差分应用；
--   - 先挂 OnClientEvent 再发 client_ready 握手，重试至首快照（F11 文档范式）；
--     seq 缺口 → resync 请求全量重同步（#18 决策 1）；
--   - 相机：透视固定正俯视，CameraMode.NONE + ManualRefresh
--     （#8 D4；#10 探针 P5/P6 通过），初值高度 60 / 俯仰 +90° / FOV 45°；
--   - 输入：全屏透明 EUIImage 捕获层（#8 D1，Opacity=0 命中 #10 探针 P4 通过）
--     → tap → EUI 画布坐标换算为相机屏幕坐标 → ScreenPointToRay
--     → 棋盘平面 y=0 求交（#8 D2）→ FireServer 意图。
--
-- 真机标定事实（#19 2026-09-04 探针，探针脚本见票内评论）：
--   - CameraUnit.Pitch 正值 = 俯视（+90 垂直向下；-90 是看天）。Yaw 0 时屏幕上方 = 世界 +z，
--     右方 = +x；业务 South 波次在 -z，恰在屏幕下方。
--   - CameraService 的「屏幕像素」空间 = 真实渲染视口（本机 1100×841），原点左上、y 向下，
--     FieldOfView 是垂直视场角；EUI 画布（GetDeviceResolution，本机 1920×1468）原点左下、
--     y 向上，两者同宽高比、按比例缩放。触摸回调坐标与 ScreenGui:SimulateTap 都在 EUI 画布空间。
--     换算：cam_x = eui_x * k，cam_y = (res.Y - eui_y) * k，k 由 WorldToScreenPoint 运行时标定
--     （相机正下方世界点投影到视口中心 → 视口尺寸 = 2×中心）。
--   - ViewportPointToRay 无视入参（三种入参返回同一射线），不可用。
--   - UserInputService:GetMouseLocation 在编辑器试玩里返回 (0,0)，视为无鼠标。
--
-- 切片边界：不建放置按钮/取消按钮（「建筑与放置」下一片）；PC 右键/Escape
-- 取消意图已接通（业务侧无 placing 时无害）。
--
-- 日志前缀 [bd][client]。

local Players = game:GetService("Players")
local World = game:GetService("World")
local RunService = game:GetService("RunService")
local CameraService = game:GetService("CameraService")
local UIS = game:GetService("UserInputService")

local Renderer = require("src.adapter.eui_render")

local function log(fmt, ...)
  print("[bd][client] " .. string.format(fmt, ...))
end

local function try(tag, fn)
  local ok, err = pcall(fn)
  if not ok then log("%s 失败: %s", tag, tostring(err)) end
  return ok
end

local elapsed = 0
local screen_res = nil

-- 相机常量（#8 D4；#17 集中可调）
local CAM_HEIGHT = 60
local CAM_PITCH = 90 -- 正值俯视（真机标定，见文件头）
local CAM_FOV = 45

-- EUI 画布 → 相机屏幕像素的比例，运行时标定；nil = 未标定（此前 tap 一律无交点）
local cam_scale = nil

-- ── RemoteEvent 通道 ────────────────────────────────────────────────
local re = RemoteEvent.New("bd_game")
local last_seq = 0
local got_first = false
local resync_cooldown = 0

local renderer = Renderer.new({
  log = log,
  get_res = function() return screen_res end,
})

re.OnClientEvent:Connect(function(msg)
  if type(msg) ~= "table" then return end
  local kind = msg.kind
  if kind == "full" or kind == "reset" then
    last_seq = msg.seq or last_seq
    got_first = true
    renderer:replace_all(msg.nodes)
    log("全量快照应用 kind=%s seq=%s", kind, tostring(msg.seq))
  elseif kind == "delta" then
    got_first = true
    if type(msg.seq) == "number" and last_seq > 0 and msg.seq ~= last_seq + 1 then
      -- 序号缺口：请求全量重同步（#18 决策 1），1s 冷却防风暴
      if elapsed >= resync_cooldown then
        resync_cooldown = elapsed + 1
        log("快照缺口 %d → %d，请求 resync", last_seq, msg.seq)
        re:FireServer({ kind = "resync" })
      end
    end
    if type(msg.seq) == "number" then last_seq = msg.seq end
    renderer:apply(msg.nodes, msg.removed)
  end
end)
re:FireServer({ kind = "client_ready" })
log("client_ready 已发送（先监听后握手）")

-- ── EUI 根 + 捕获层（PlayerGui 就绪后创建）──────────────────────────
local capture = nil
local eui_ready = false

-- EUI 画布坐标 → 相机屏幕像素 → 射线 → 棋盘平面 y=0 求交（#8 D2）；
-- 未标定/无相机/近平行 → nil
local function screen_to_board(eui_x, eui_y)
  if not cam_scale or not screen_res then return nil end
  local sx = eui_x * cam_scale.x
  local sy = (screen_res.Y - eui_y) * cam_scale.y
  local ok, hit = pcall(function()
    local ray = CameraService:ScreenPointToRay(sx, sy, 0)
    if not ray or not ray.Origin or not ray.Direction then return nil end
    local dy = ray.Direction.y
    if math.abs(dy) < 1e-4 then return nil end
    local t = -ray.Origin.y / dy
    if t < 0 then return nil end
    local p = ray.Origin + ray.Direction * t
    return { x = p.x, z = p.z }
  end)
  if not ok then return nil end
  return hit
end

local function send_tap(sx, sy)
  local p = screen_to_board(sx, sy)
  if p then
    log("tap (%.0f,%.0f) → 棋盘 (%.2f, %.2f)，发送意图", sx, sy, p.x, p.z)
    re:FireServer({ kind = "input", itype = "tap", x = p.x, z = p.z })
  else
    log("tap (%.0f,%.0f) → 射线无交点（%s）", sx, sy, cam_scale and "界外" or "相机未标定")
  end
end

local function setup_eui()
  local localPlayer = Players.LocalPlayer
  if not localPlayer or not localPlayer.PlayerGui then return false end
  local mgr = localPlayer.PlayerGui.EuiManager
  if not mgr then return false end
  local root = mgr:GetRootNode()
  local res = mgr:GetDeviceResolution()
  if not root or not res then return false end
  screen_res = res
  renderer:set_root(root)

  -- 全屏透明捕获层（#8 D1）：只认第一指，tap = 按下/抬起位移 < 阈值
  try("创建透明捕获层", function()
    capture = World:CreateUnit("EUIImage", {
      Parent = root,
      Name = "bd_capture",
      Position = Vector2.New(res.X / 2, res.Y / 2),
      Size = Vector2.New(res.X, res.Y),
      Opacity = 0,
      Color = Color.New(255, 255, 255, 255),
      TouchEnabled = true,
      SwallowTouchEnabled = true,
      LocalZOrder = -100,
    })
    local touch = nil -- { id=, x=, y= } 第一指
    capture.OnTouchBegan:Connect(function(info)
      if touch then return end
      touch = { id = info.TouchID, x = info.BeganPosition.X, y = info.BeganPosition.Y }
      log("touch began id=%s (%.0f,%.0f)", tostring(info.TouchID), touch.x, touch.y)
    end)
    capture.OnTouchEnded:Connect(function(info)
      if not touch or info.TouchID ~= touch.id then return end
      local ex, ey = info.EndedPosition.X, info.EndedPosition.Y
      local dx, dy = ex - touch.x, ey - touch.y
      local touch_x, touch_y = touch.x, touch.y
      touch = nil
      if dx * dx + dy * dy <= 20 * 20 then
        send_tap(ex, ey)
      else
        log("touch 位移过大，非 tap：began=(%.0f,%.0f) ended=(%.0f,%.0f) d=%.0f",
          touch_x, touch_y, ex, ey, math.sqrt(dx * dx + dy * dy))
      end
    end)
    log("透明捕获层已创建 res=%s,%s", tostring(res.X), tostring(res.Y))
  end)
  return true
end

-- PC 辅助：右键/Escape → 取消意图（#8 D3 辅路）
try("挂 InputBegan", function()
  UIS.InputBegan:Connect(function(input, _processed)
    local t = input.UserInputType
    if t == Enums.UserInputType.MouseButton2 then
      re:FireServer({ kind = "input", itype = "cancel" })
    elseif t == Enums.UserInputType.Keyboard
      and input.KeyCode == Enums.KeyCode.Escape then
      re:FireServer({ kind = "input", itype = "cancel" })
    end
  end)
end)

-- ── 相机：固定正俯视（#8 D4）────────────────────────────────────────
local cam_applied = false

local function apply_camera()
  try("写相机", function()
    local cam = World.CurrentCamera
    if not cam then return end
    cam.Mode = Enums.CameraMode.NONE
    -- 不写 Priority：真机实测写入触发宿主 VM 警告
    -- 「set_priority() takes exactly 2 arguments (3 given)」（每 5s 噪音），
    -- 且 #10 探针证明 Mode=NONE 定点无需 Priority 也稳定。
    cam.Position = Vector3.New(0, CAM_HEIGHT, 0)
    cam.Pitch = CAM_PITCH
    cam.Yaw = 0
    cam.FieldOfView = CAM_FOV
    CameraService:ManualRefresh()
  end)
end

-- 标定 EUI→相机像素比例：相机正下方的世界原点投影到视口中心，视口尺寸 = 2×中心。
-- 相机写入后要等宿主刷新矩阵，故在下一帧调用；比例变化 >1% 才重新记录。
local function calibrate_camera()
  if not screen_res then return end
  local ok, err = pcall(function()
    local s, on = CameraService:WorldToScreenPoint(Vector3.New(0, 0, 0))
    if not on or not s or s.x <= 0 or s.y <= 0 then return end
    local kx, ky = 2 * s.x / screen_res.X, 2 * s.y / screen_res.Y
    if cam_scale and math.abs(kx - cam_scale.x) < 0.01 * cam_scale.x
      and math.abs(ky - cam_scale.y) < 0.01 * cam_scale.y then
      return
    end
    cam_scale = { x = kx, y = ky }
    local p = screen_to_board(screen_res.X / 2, screen_res.Y / 2)
    log("相机标定：视口≈%.0fx%.0f k=(%.4f,%.4f) 画布中心→棋盘 (%s)",
      2 * s.x, 2 * s.y, kx, ky, p and string.format("%.2f,%.2f", p.x, p.z) or "无交点")
    if math.abs(kx - ky) > 0.02 * ky then
      log("警告：EUI 画布与视口宽高比不一致 kx=%.4f ky=%.4f，点击换算可能偏斜", kx, ky)
    end
  end)
  if not ok then log("相机标定失败: %s", tostring(err)) end
end

-- ── PC 悬停轮询（节流；GetMouseLocation 不可用时自动停用）────────────
local hover_acc = 0
local last_hover = nil
local mouse_ok = true

local function poll_hover(dt)
  if not mouse_ok or not screen_res then return end
  hover_acc = hover_acc + dt
  if hover_acc < 0.1 then return end
  hover_acc = 0
  local ok, err = pcall(function()
    local loc = UIS:GetMouseLocation()
    -- 编辑器试玩里恒为 (0,0)（真机实测）：视为无鼠标，不发假悬停
    if not loc or (loc.X == 0 and loc.Y == 0) then return end
    local p = screen_to_board(loc.X, loc.Y)
    if p == nil then
      if last_hover ~= nil then
        last_hover = nil
        re:FireServer({ kind = "input", itype = "hover" })
      end
      return
    end
    if not last_hover or math.abs(p.x - last_hover.x) > 0.5 or math.abs(p.z - last_hover.z) > 0.5 then
      last_hover = p
      re:FireServer({ kind = "input", itype = "hover", x = p.x, z = p.z })
    end
  end)
  if not ok then
    mouse_ok = false -- GetMouseLocation 不可用（触屏环境），停用 PC 悬停轮询
    log("GetMouseLocation 不可用，停用悬停轮询: %s", tostring(err))
  end
end

-- ── 主循环 ──────────────────────────────────────────────────────────
local ready_retry_acc = 0
local calib_pending = 0 -- 相机写入后延 N 帧标定

RunService.Heartbeat:Connect(function(deltaTime)
  elapsed = elapsed + deltaTime

  if not eui_ready then
    eui_ready = setup_eui()
    if eui_ready then log("EUI 就绪 @%.2fs", elapsed) end
  end

  -- client_ready 重试至首快照（F11）
  if not got_first then
    ready_retry_acc = ready_retry_acc + deltaTime
    if ready_retry_acc >= 2 then
      ready_retry_acc = 0
      re:FireServer({ kind = "client_ready" })
    end
  end

  -- 相机：1s 后写入，此后每 5s 重申（防宿主覆写；#10 探针显示无覆写，保底）
  if not cam_applied and elapsed >= 1 then
    cam_applied = true
    apply_camera()
    calib_pending = 2
    log("相机已固定：pos=(0,%d,0) pitch=%d fov=%d", CAM_HEIGHT, CAM_PITCH, CAM_FOV)
  elseif cam_applied and elapsed % 5 < deltaTime then
    apply_camera()
    calib_pending = 2
  end
  if calib_pending > 0 then
    calib_pending = calib_pending - 1
    if calib_pending == 0 then calibrate_camera() end
  end

  poll_hover(deltaTime)
  renderer:tick(deltaTime)
end)

-- ── GM 面（$CLI exec --platform client 驱动）────────────────────────
_G.bd_client = {
  -- 在 EUI 画布坐标注入一次点击（走真实捕获层 → tap → 意图链路；集成测试用）
  sim_tap = function(x, y)
    local sg = Players.LocalPlayer and Players.LocalPlayer.PlayerGui.ScreenGui
    if not sg then log("sim_tap：ScreenGui 不可用") return end
    sg:SimulateTap(Vector2.New(tonumber(x), tonumber(y)))
    log("sim_tap(%s,%s) 已注入", tostring(x), tostring(y))
  end,
  -- 画布坐标 → 棋盘坐标（不发意图，只打印换算结果）
  probe = function(x, y)
    local p = screen_to_board(tonumber(x), tonumber(y))
    log("probe(%s,%s) → %s k=%s", tostring(x), tostring(y),
      p and string.format("棋盘 (%.2f,%.2f)", p.x, p.z) or "无交点",
      cam_scale and string.format("(%.4f,%.4f)", cam_scale.x, cam_scale.y) or "未标定")
  end,
  stats = function()
    local s = renderer:stats()
    log("CSTATS live_state=%d labels=%d hp_bars=%d none=%d pending_hp=%d seq=%d got_first=%s",
      s.state, s.labels, s.bars, s.none, s.pending, last_seq, tostring(got_first))
  end,
}

log("垂直切片客户端挂载完成：快照渲染 + 固定俯视相机 + 棋盘捕获层")
