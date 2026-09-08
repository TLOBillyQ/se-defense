-- 适配层组合根：组装业务模块依赖的 host 表。
--
-- 业务模块（server/game/）直接 require("server.adapter.host")；无头测试用
-- tools/headless/se_stub.lua 提供 SE 全局，不再有 mock 替换。
--
-- 四域真实现（#19 垂直切片）：
--   eui         服务端快照出口 + 形状路由：ring 进快照、line 就地渲（#18；ADR 0006）
--   input       意图队列 → 业务轮询面（#8 D5）
--   entity      WorldUnit 映射（#9 D1），Name = 业务实体 id（#18 决策 4）
--   reset_scene 销毁适配器单位 + 重置注册表（#7 决策 3；#43 由 reset_scene.lua 并入）
--
-- reset_scene 是无场景重载的宿主等价物，对应 session.lua 的 Restart 语义
-- （dispose → host:reset_scene() → 重建）。session.lua 用
-- type(host.reset_scene) == "function" 守卫后以 host:reset_scene() 方法调用
-- （会传入 host 表），所以这里必须保持 function 值并忽略首参。

local eui = require("server.adapter.eui")
local input = require("server.adapter.input")
local entity = require("server.adapter.entity")

local host = {}

host.eui = eui
host.input = input
host.entity = entity

-- 销毁适配器 spawn 的全部 WorldUnit + 重置快照注册表 + 输入队列清零。
-- 客户端清理由 server/main.lua 的 reset 快照广播承担。
function host.reset_scene(_self)
  entity.reset()
  eui.reset()
  input.reset_all()
end

return host
