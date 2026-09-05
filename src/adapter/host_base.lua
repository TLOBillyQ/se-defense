-- 宿主基底：替换 examples/host_mock.lua（mock 的定时器/事件队列/run 泵）。
--
-- #7 决策 4：业务 38 文件对 SetTimeOut / register_trigger_event / host.time
-- 零调用（仅 game_tick.lua 旧注释提及 REPEAT_TIMEOUT）；本模块只需提供
-- 兼容面，真基底是 SE 运行时本身（服务端 RunService.Heartbeat 驱动 GameTick）。
-- 被调到说明出现了契约外使用——按断言失败暴露，不静默吞掉。

local host_base = {}

host_base.time = 0
host_base.EVENT = { REPEAT_TIMEOUT = "REPEAT_TIMEOUT" }

function host_base.SetTimeOut(_delay, _fn)
  error("host_base.SetTimeOut：SE 部署不支持旧 ECA 定时面（业务应无此调用，见 #7 决策 4）", 2)
end

function host_base.register_trigger_event(_spec, _fn)
  error("host_base.register_trigger_event：SE 部署用 RunService.Heartbeat 驱动（见 #7 决策 3）", 2)
end

function host_base.log(fmt, ...)
  print("[bd][host] " .. string.format(fmt, ...))
end

return host_base
