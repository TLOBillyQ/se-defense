-- 05_BaseDefence 矿点采集（Resource 的采集 phase 部分）。
--
-- 职责：Playing 期间、有电且非空袭时按 collect_time 产出金钱并消耗资源。
-- 上游靠 GameState 的 Time.timeScale = 0 冻结非 Playing 的模拟；本端口
-- 没有全局 timeScale，因此把同一个语义显式放进 can_harvest。
-- Resource 组件在 server.economy.resource 中挂载本 phase。

-- 注册 s:coroutine() 扩展（采集协程）。
require("server.kernel.spoke_coroutine")

local Phase = require("common.spoke.reactive.phase")

local ResourceHarvest = {}

-- 挂载采集 phase（has_resources 为真时进入）。
-- ctx: has_resources / power / director / game_state / game_tick /
-- collect_time；resource 为 Resource 组件实例（读取 remaining）。
function ResourceHarvest.install(s, resource, ctx)
  local has_resources = ctx.has_resources
  local power = ctx.power
  local director = ctx.director
  local game_state = ctx.game_state
  local game_tick = ctx.game_tick
  local collect_time = ctx.collect_time

  s:call(Phase.new("Resource.harvest", has_resources, function(s2)
    local wave_signal = director and director.wave or nil
    local mode_signal = game_state.mode
    local can_harvest_deps = { power.has_power }
    if wave_signal then
      can_harvest_deps[#can_harvest_deps + 1] = wave_signal
    end
    if mode_signal then
      can_harvest_deps[#can_harvest_deps + 1] = mode_signal
    end
    local can_harvest = s2:memo("Resource.can_harvest", function(s3)
      local playing = not mode_signal or s3:d(mode_signal) == "Playing"
      local has_power = s3:d(power.has_power)
      local assaulting = false
      if wave_signal then
        local wave = s3:d(wave_signal)
        assaulting = wave and wave.assault == true
      end
      return playing and has_power and not assaulting
    end, can_harvest_deps)

    s2:call(Phase.new("Resource.can_harvest", can_harvest, function(s3)
      game_state.collect_rate:update(function(x)
        return x + 1 / collect_time
      end)
      s3:on_cleanup(function()
        game_state.collect_rate:update(function(x)
          return x - 1 / collect_time
        end)
      end)

      s3:coroutine(game_tick, function(_, wait_seconds)
        while true do
          wait_seconds(collect_time)
          -- 在 Phase cleanup 实际运行前 guard 一次，避免多扣一格。
          if resource.remaining:now() <= 0 then
            break
          end
          game_state.money:update(function(x)
            return x + 1
          end)
          resource.remaining:update(function(x)
            return x - 1
          end)
        end
      end)
    end))
  end))
end

return ResourceHarvest
