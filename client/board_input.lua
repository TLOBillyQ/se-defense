-- 棋盘输入捕获（#8 D1/D3/D5，#21）：全屏透明 EUIImage 捕获层 + PC 辅路。
--
-- 输入语义（本文件决定）：
--   - 捕获层触摸：按下/移动 → hover 意图（预览圈随手指走、有效绿/无效红），
--     松手 → tap 意图（放置）。**不设位移阈值**：本图无相机平移手势（Out of scope），
--     长拖 = 拖着预览再松手放置，正是触摸放置的自然语义；位移只记日志供标定。
--   - PC 右键 = 取消；右键抬起也会触发捕获层 OnTouchEnded，按时间窗压掉那一次 tap，
--     否则「右键取消」会被随后的 tap 当成放置。Escape 同样取消。
--   - PC 悬停轮询：UserInputService:GetMouseLocation 在编辑器试玩里返回 (0,0)，视为无鼠标；
--     调用抛错（触屏环境）则永久停用轮询。
--
-- 坐标换算全部委托 client/camera.lua；意图经 deps.send 发往服务端。

local World = game:GetService("World")
local UIS = game:GetService("UserInputService")

local M = {}
local B = {}
B.__index = B

-- deps: log、camera（client.camera 实例）、send(msg)、now() → 客户端已运行秒数
function M.new(deps)
  local self = setmetatable({
    log = deps.log,
    camera = deps.camera,
    send = deps.send,
    now = deps.now,
    capture = nil,
    suppress_tap_until = -1, -- 右键窗口：其间捕获层 ended 不当 tap
    last_tap_at = -1,
    hover_sent_at = 0,
    last_touch_hover = nil,
    -- PC 悬停轮询
    hover_acc = 0,
    last_hover = nil,
    mouse_ok = true,
  }, B)
  self:_hook_pc_cancel()
  return self
end

-- 触摸悬停 → hover 意图；force=按下时立即发，移动时节流
function B:_send_hover(sx, sy, force)
  local t = self.now()
  if not force and t - self.hover_sent_at < 0.08 then return end
  self.hover_sent_at = t
  local p = self.camera:screen_to_board(sx, sy)
  local last = self.last_touch_hover
  if p then
    if force or not last or math.abs(p.x - last.x) > 0.2 or math.abs(p.z - last.z) > 0.2 then
      self.last_touch_hover = p
      self.send({ kind = "input", itype = "hover", x = p.x, z = p.z })
    end
  elseif last then
    self.last_touch_hover = nil
    self.send({ kind = "input", itype = "hover" })
  end
end

function B:_send_tap(sx, sy)
  local p = self.camera:screen_to_board(sx, sy)
  if p then
    self.log("tap (%.0f,%.0f) → 棋盘 (%.2f, %.2f)，发送意图", sx, sy, p.x, p.z)
    self.send({ kind = "input", itype = "tap", x = p.x, z = p.z })
  else
    self.log("tap (%.0f,%.0f) → 射线无交点（%s）", sx, sy, self.camera.scale and "界外" or "相机未标定")
  end
end

-- 在 EUI 根下创建全屏透明捕获层（#8 D1）：只认第一指
function B:setup(root, res)
  local ok, err = pcall(function()
    local capture = World:CreateUnit("EUIImage", {
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
    self.capture = capture
    local touch = nil -- { id=, x=, y=, t= } 第一指
    capture.OnTouchBegan:Connect(function(info)
      if touch then return end
      touch = { id = info.TouchID, x = info.BeganPosition.X, y = info.BeganPosition.Y, t = self.now() }
      self.log("touch began id=%s (%.0f,%.0f)", tostring(info.TouchID), touch.x, touch.y)
      self:_send_hover(touch.x, touch.y, true)
    end)
    capture.OnTouchMoved:Connect(function(info)
      if not touch or info.TouchID ~= touch.id then return end
      self:_send_hover(info.MovedPosition.X, info.MovedPosition.Y, false)
    end)
    capture.OnTouchEnded:Connect(function(info)
      if not touch or info.TouchID ~= touch.id then return end
      local ex, ey = info.EndedPosition.X, info.EndedPosition.Y
      local dx, dy = ex - touch.x, ey - touch.y
      local t = self.now()
      local held = t - touch.t
      touch = nil
      local d = math.sqrt(dx * dx + dy * dy)
      if t < self.suppress_tap_until then
        self.log("touch ended (%.0f,%.0f) d=%.0f held=%.2fs：右键窗口内，忽略", ex, ey, d, held)
        return
      end
      self.log("touch ended (%.0f,%.0f) d=%.0f held=%.2fs → tap", ex, ey, d, held)
      self.last_tap_at = t
      self:_send_tap(ex, ey)
    end)
    -- 诊断：宿主自己的「点击」判定与我们的 ended→tap 是否一致（标定用，不驱动逻辑）
    capture.OnClicked:Connect(function()
      self.log("capture OnClicked（距上次 tap %.2fs）", self.now() - self.last_tap_at)
    end)
    self.log("透明捕获层已创建 res=%s,%s", tostring(res.X), tostring(res.Y))
  end)
  if not ok then self.log("创建透明捕获层 失败: %s", tostring(err)) end
end

-- PC 辅助：右键/Escape → 取消意图（#8 D3 辅路）
function B:_hook_pc_cancel()
  local ok, err = pcall(function()
    UIS.InputBegan:Connect(function(input, _processed)
      local t = input.UserInputType
      if t == Enums.UserInputType.MouseButton2 then
        self.suppress_tap_until = self.now() + 0.5
        self.log("右键 → cancel（0.5s 内忽略捕获层 tap）")
        self.send({ kind = "input", itype = "cancel" })
      elseif t == Enums.UserInputType.Keyboard
        and input.KeyCode == Enums.KeyCode.Escape then
        self.send({ kind = "input", itype = "cancel" })
      end
    end)
  end)
  if not ok then self.log("挂 InputBegan 失败: %s", tostring(err)) end
end

-- PC 悬停轮询（0.1s 节流；GetMouseLocation 不可用时自动停用）。res 为 nil 时跳过。
function B:tick(dt, res)
  if not self.mouse_ok or not res then return end
  self.hover_acc = self.hover_acc + dt
  if self.hover_acc < 0.1 then return end
  self.hover_acc = 0
  local ok, err = pcall(function()
    local loc = UIS:GetMouseLocation()
    -- 编辑器试玩里恒为 (0,0)（真机实测）：视为无鼠标，不发假悬停
    if not loc or (loc.X == 0 and loc.Y == 0) then return end
    local p = self.camera:screen_to_board(loc.X, loc.Y)
    local last = self.last_hover
    if p == nil then
      if last ~= nil then
        self.last_hover = nil
        self.send({ kind = "input", itype = "hover" })
      end
      return
    end
    if not last or math.abs(p.x - last.x) > 0.5 or math.abs(p.z - last.z) > 0.5 then
      self.last_hover = p
      self.send({ kind = "input", itype = "hover", x = p.x, z = p.z })
    end
  end)
  if not ok then
    self.mouse_ok = false -- GetMouseLocation 不可用（触屏环境），停用 PC 悬停轮询
    self.log("GetMouseLocation 不可用，停用悬停轮询: %s", tostring(err))
  end
end

return M
