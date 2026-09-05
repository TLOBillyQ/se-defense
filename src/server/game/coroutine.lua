-- 05_BaseDefence 的 s:coroutine() EffectBuilder 扩展（示例本地，不进核心库）。
--
-- 忠实对应上游 SpokeExtensions.cs 的 s.Coroutine()：在 effect 生命周期内运行一个
-- Lua 原生 coroutine，effect 卸载时停止。yield 协议仅两种：
--   yield()        -- 下一 game tick 恢复
--   wait_seconds(n) -- n 秒游戏时间后恢复
--
-- 用法：
--   s:coroutine(game_tick, function(yield, wait_seconds)
--     while true do
--       wait_seconds(1)
--       spawn_wave()
--     end
--   end)
--
-- 也支持直接传入 coroutine.create 得到的线程作为第二个参数。

local EffectBuilder = require("vendor.spoke.reactive.effect_builder")

-- 把 Lua thread 或 function 统一成 thread。
local function ensure_thread(body)
  if type(body) == "thread" then
    return body
  end
  if type(body) == "function" then
    return coroutine.create(body)
  end
  error("s:coroutine expects a function or coroutine thread", 3)
end

-- 扩展 EffectBuilder。
function EffectBuilder:coroutine(game_tick, body)
  self:effect("Coroutine", function(s)
    local co = ensure_thread(body)
    local deadline
    local unlisten

    local function yield()
      deadline = nil
      coroutine.yield()
    end

    local function wait_seconds(seconds)
      deadline = game_tick:time() + seconds
      coroutine.yield()
    end

    local function resume()
      if not co or coroutine.status(co) == "dead" then
        if unlisten then unlisten() end
        return
      end
      if deadline and game_tick:time() < deadline then
        return
      end
      local ok, err = coroutine.resume(co, yield, wait_seconds)
      if not ok then
        if unlisten then unlisten() end
        co = nil
        error(err, 0)
      end
    end

    unlisten = game_tick:listen(resume)
    resume()

    s:on_cleanup(function()
      if unlisten then unlisten() end
      unlisten = nil
      co = nil
    end)
  end)
end
