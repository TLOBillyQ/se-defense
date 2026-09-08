-- host.input 域真实现（服务端半）：意图队列 → 业务轮询面。
--
-- 依据 #8 D5：
--   - 业务轮询面与 input_mock 1:1：get_mouse_world_point / get_mouse_button_down(0/1) /
--     reset_frame。
--   - tap 边沿 → 左键；取消（专用按钮/PC 右键/Escape）→ 右键；触点 → 世界点。
--   - reset_frame 由 GameTick 驱动器在每个固定步长边界调用（#7 决策 3）。
--   - 界外点 → nil（#8 D2）：bounds 由 server/main.lua 在树 spawn 后注入
--     （game_state:level_bounds()）。
--
-- 输入来源：客户端捕获层经 RemoteEvent 发来意图（server/main.lua 校验后调用
-- intent_*）；GM/自动化可经 _G.bd.tap(x, z) 直接注入（验证自动化优先，#1 偏好 2）。

local input = {
  _left_down = false,
  _right_down = false,
  _pending_left = 0,   -- tap 边沿倒计时（固定步长数），见 arm_frame 注释
  _pending_right = 0,
  _mouse_world = nil,
  _bounds = nil, -- { min = {x,z}, max = {x,z} }，level_bounds 注入
}

local function in_bounds(p)
  local b = input._bounds
  if not b then return true end -- 未注入前不过滤（树 spawn 前的 GM 注入可用）
  return p.x >= b.min.x and p.x <= b.max.x and p.z >= b.min.z and p.z <= b.max.z
end

-- ── 业务轮询面（1:1 mock 语义）───────────────────────────────────────

function input.get_mouse_button_down(button)
  if button == 0 then return input._left_down end
  if button == 1 then return input._right_down end
  return false
end

function input.get_mouse_world_point()
  return input._mouse_world
end

-- 每个固定步长结束后由驱动器调用：清当帧按下边沿（"按下只持续一帧"）。
function input.reset_frame()
  input._left_down = false
  input._right_down = false
end

-- 每个固定步长开始前由驱动器调用：把点击意图举为当帧边沿。
--
-- 为什么延迟两个步长（#19 无头实测发现）：BoardInteractions 的点击响应读
-- is_valid Memo，而 Memo 只在 flush 时重算（spoke memo.lua：now() 读内部
-- State，不惰性重算）。点击边沿要想读到「新触点」的有效性，必须等：
--   步长 N：触点已就位 → 碰撞区采样 → flush 重算 is_valid；
--   步长 N+1：边沿举起 → 订阅者读到新鲜 is_valid。
-- 业务自己的 e2e（place_at）也是「置鼠标点 → 走两个 tick → 点击」的顺序，
-- 本倒计时即复刻该顺序。66ms 延迟对放置交互无感；PC 悬停本就持续先行，
-- 只有触摸/GM 的单发 tap 依赖此兜底。
local TAP_DELAY_STEPS = 2

function input.arm_frame()
  if input._pending_left > 0 then
    input._pending_left = input._pending_left - 1
    if input._pending_left == 0 then
      input._left_down = true
    end
  end
  if input._pending_right > 0 then
    input._pending_right = input._pending_right - 1
    if input._pending_right == 0 then
      input._right_down = true
    end
  end
end

-- ── 适配器侧注入面（非业务合约；server/main.lua 与 GM 用）─────────────

function input.set_bounds(bounds)
  input._bounds = bounds
end

-- tap：触点立即生效 + 左键边沿按倒计时举起；界外 → 触点置 nil、不记边沿。
function input.intent_tap(x, z)
  local p = { x = x, y = 0, z = z }
  if not in_bounds(p) then
    input._mouse_world = nil
    return false
  end
  input._mouse_world = p
  input._pending_left = TAP_DELAY_STEPS
  return true
end

-- 悬停：只更新触点（无边沿）；界外/抬指 → nil。
function input.intent_hover(x, z)
  if x == nil or z == nil then
    input._mouse_world = nil
    return
  end
  local p = { x = x, y = 0, z = z }
  input._mouse_world = in_bounds(p) and p or nil
end

-- 取消：右键边沿按倒计时举起（与 tap 同理）。
function input.intent_cancel()
  input._pending_right = TAP_DELAY_STEPS
end

-- reset_scene 用。
function input.reset_all()
  input._left_down = false
  input._right_down = false
  input._pending_left = 0
  input._pending_right = 0
  input._mouse_world = nil
end

return input
