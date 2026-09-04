-- 宿主基底：替换 examples/host_mock.lua（mock 的定时器/事件队列/run 泵）。
-- 真基底是 SE 运行时本身（服务端 RunService.Heartbeat，见 research/realm-model），
-- 形态待 realm 拆分决策（#7）；本票只占位。

local host_base = {}

return host_base
