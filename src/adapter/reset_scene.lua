-- host.reset_scene 域真实现（服务端）：无场景重载的宿主等价物。
-- 业务侧对应 session.lua 的 Restart 语义（dispose → host:reset_scene() → 重建）。
--
-- #7 决策 3：真实现 = 销毁适配器 spawn 的全部 WorldUnit + 重置快照注册表 +
-- 输入队列清零。客户端清理由 server/main.lua 的 reset 快照广播承担
-- （垂直切片不挂 Restart 入口——「胜负与重开」是后续片；本函数备好供其使用）。
--
-- 注意：session.lua 以 host:reset_scene() 方法调用（会传入 host 表），
-- 本函数首参忽略。

local entity = require("src.adapter.entity")
local eui = require("src.adapter.eui")
local input = require("src.adapter.input")

local function reset_scene(_self)
  entity.reset()
  eui.reset()
  input.reset_all()
end

return reset_scene
