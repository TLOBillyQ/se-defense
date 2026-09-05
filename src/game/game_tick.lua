-- 05_BaseDefence 游戏节拍驱动器（示例本地，不进核心库）。
--
-- 职责：维护累计游戏时间，向每 tick 监听器派发 dt。无头测试可以手动 step；
-- 真机部署时由宿主的周期性帧回调驱动（user land 驱动器范式见
-- spoke 上游 examples/frame_pacing.lua；SE 宿主为 RunService.Heartbeat 固定步长积累，
-- 不存在 EVENT.REPEAT_TIMEOUT 这类 FS 宿主事件），示意接线如下：
--
--   local tick = GameTick.new(1 / 30)
--   host.on_frame(function(dt)  -- 宿主帧回调，注册方式与签名随宿主而定
--     tick:tick(dt)
--     for _, tree in ipairs(manual_trees) do
--       if tree:has_pending() then tree:flush() end
--     end
--   end)
--
-- CollisionWorld 等需要每帧推进的系统只需 tick:listen(...) 注册为监听器。

local GameTick = {}
GameTick.__index = GameTick

-- 创建驱动器。default_interval 是 advance(seconds) 的默认步长，可省略；
-- 若省略则 advance(seconds) 必须显式传 step_dt。
function GameTick.new(default_interval)
  return setmetatable({
    _time = 0,
    _default_interval = default_interval,
    _listeners = {},
    _next_id = 0,
  }, GameTick)
end

-- 当前累计游戏时间（秒）。
function GameTick:time()
  return self._time
end

-- 默认步长；未设置时返回 nil。
function GameTick:default_interval()
  return self._default_interval
end

-- 注册每 tick 监听器，返回可关闭注册的句柄（多次调用幂等）。
function GameTick:listen(fn)
  local id = self._next_id + 1
  self._next_id = id
  self._listeners[id] = fn
  return function()
    self._listeners[id] = nil
  end
end

-- 手动推进一帧：时间前进 dt 秒，并依次通知所有监听器（当前快照，
-- 本次 dispatch 中新注册的监听器不会立即触发）。
function GameTick:tick(dt)
  self._time = self._time + dt
  local snapshot = {}
  for _, fn in pairs(self._listeners) do
    snapshot[#snapshot + 1] = fn
  end
  for _, fn in ipairs(snapshot) do
    fn(dt)
  end
end

-- 便捷批量推进：从当前时间前进 seconds，按 step_dt（或默认步长）拆成多次 tick。
function GameTick:advance(seconds, step_dt)
  local step = step_dt or self._default_interval
  if not step or step <= 0 then
    error("GameTick:advance requires a positive step_dt or default_interval", 2)
  end
  local remaining = seconds
  while remaining > step do
    self:tick(step)
    remaining = remaining - step
  end
  if remaining > 0 then
    self:tick(remaining)
  end
end

return GameTick
