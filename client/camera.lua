-- 固定俯视相机 + EUI 画布 ↔ 棋盘坐标换算（#8 D4 / #8 D2）。
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
--
-- 写入节奏（tick）：1s 后首写，此后每 5s 重申（防宿主覆写；#10 探针显示无覆写，保底）。
-- 真机事实：与 Mode 切换同帧写入的 Yaw/Pitch 不生效，宿主用旧朝向充数（回读 yaw=180 /
-- 0.0085 等残值，画面南北颠倒或歪 20°，直到 5s 重申才归正）。故首写后连写 2 帧。
-- 相机写入后要等宿主刷新矩阵，故标定延后数帧。

local World = game:GetService("World")
local CameraService = game:GetService("CameraService")

-- 相机常量（#8 D4；#17 集中可调）
local CAM_HEIGHT = 60
local CAM_PITCH = 90 -- 正值俯视（真机标定，见文件头）
local CAM_FOV = 45

local M = {}
local C = {}
C.__index = C

-- deps: log(fmt, ...)、get_res() → EUI 画布分辨率或 nil
function M.new(deps)
  return setmetatable({
    log = deps.log,
    get_res = deps.get_res,
    scale = nil, -- EUI 画布 → 相机屏幕像素的比例；nil = 未标定（此前 tap 一律无交点）
    applied = false,
    settle = 0, -- 首写后再连写 N 帧
    calib_pending = 0, -- 相机写入后延 N 帧标定
  }, C)
end

function C:apply()
  local ok, err = pcall(function()
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
  if not ok then self.log("写相机 失败: %s", tostring(err)) end
end

-- EUI 画布坐标 → 相机屏幕像素 → 射线 → 棋盘平面 y=0 求交；未标定/无相机/近平行 → nil
function C:screen_to_board(eui_x, eui_y)
  local res = self.get_res()
  if not self.scale or not res then return nil end
  local sx = eui_x * self.scale.x
  local sy = (res.Y - eui_y) * self.scale.y
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

-- 棋盘坐标 → EUI 画布坐标；未标定 → nil, "相机未标定"；不在视口内 → nil, "世界点不在视口内"。
-- 反向换算：WorldToScreenPoint 给视口像素（左上原点），除以标定比例 k 回画布（左下原点）。
function C:board_to_screen(bx, bz)
  local res = self.get_res()
  if not self.scale or not res then return nil, "相机未标定" end
  local s, on = CameraService:WorldToScreenPoint(Vector3.New(bx, 0, bz))
  if not on or not s then return nil, "世界点不在视口内" end
  return s.x / self.scale.x, res.Y - s.y / self.scale.y
end

-- 标定 EUI→相机像素比例：相机正下方的世界原点投影到视口中心，视口尺寸 = 2×中心。
-- 比例变化 >1% 才重新记录。
function C:calibrate()
  local res = self.get_res()
  if not res then return end
  local ok, err = pcall(function()
    local s, on = CameraService:WorldToScreenPoint(Vector3.New(0, 0, 0))
    if not on or not s or s.x <= 0 or s.y <= 0 then return end
    local kx, ky = 2 * s.x / res.X, 2 * s.y / res.Y
    if self.scale and math.abs(kx - self.scale.x) < 0.01 * self.scale.x
      and math.abs(ky - self.scale.y) < 0.01 * self.scale.y then
      return
    end
    self.scale = { x = kx, y = ky }
    local p = self:screen_to_board(res.X / 2, res.Y / 2)
    self.log("相机标定：视口≈%.0fx%.0f k=(%.4f,%.4f) 画布中心→棋盘 (%s)",
      2 * s.x, 2 * s.y, kx, ky, p and string.format("%.2f,%.2f", p.x, p.z) or "无交点")
    if math.abs(kx - ky) > 0.02 * ky then
      self.log("警告：EUI 画布与视口宽高比不一致 kx=%.4f ky=%.4f，点击换算可能偏斜", kx, ky)
    end
  end)
  if not ok then self.log("相机标定失败: %s", tostring(err)) end
end

-- 每帧调用：写入节奏 + 延帧标定（见文件头）
function C:tick(dt, elapsed)
  if not self.applied and elapsed >= 1 then
    self.applied = true
    self:apply()
    self.settle = 2
    self.calib_pending = 3
    self.log("相机已固定：pos=(0,%d,0) pitch=%d fov=%d", CAM_HEIGHT, CAM_PITCH, CAM_FOV)
  elseif self.settle > 0 then
    self.settle = self.settle - 1
    self:apply()
  elseif self.applied and elapsed % 5 < dt then
    self:apply()
    self.calib_pending = 2
  end
  if self.calib_pending > 0 then
    self.calib_pending = self.calib_pending - 1
    if self.calib_pending == 0 then self:calibrate() end
  end
end

function C:scale_text()
  return self.scale and string.format("(%.4f,%.4f)", self.scale.x, self.scale.y) or "未标定"
end

return M
