-- 适配层组合根：组装业务模块依赖的 host 表。
--
-- 部署时经 src/adapter/swap/host_mock.lua 同路径替换到
-- examples/base_defence/host_mock.lua，业务 require 路径不变（零改动机制）。
--
-- 四域真实现（#19 垂直切片）：
--   eui         服务端快照出口 + ring/line 双路由（#18）
--   input       意图队列 → 业务轮询面（#8 D5）
--   entity      WorldUnit 映射（#9 D1），Name = 业务实体 id（#18 决策 4）
--   reset_scene 销毁适配器单位 + 重置注册表（#7 决策 3）

local host = {}

host.eui = require("src.adapter.eui")
host.input = require("src.adapter.input")
host.entity = require("src.adapter.entity")
host.reset_scene = require("src.adapter.reset_scene")

return host
