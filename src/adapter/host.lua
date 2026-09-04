-- 适配层组合根：组装业务模块依赖的 host 表。
--
-- 部署时经 src/adapter/swap/host_mock.lua 同路径替换到
-- examples/base_defence/host_mock.lua，业务 require 路径不变（零改动机制）。
-- 本票为最小 stub：只保证部署树可加载；四域真实现由后续票迭代
-- （eui→表现映射 #9，input→交互决策 #8，entity/reset_scene→realm 拆分 #7）。

local host = {}

host.eui = require("src.adapter.eui")
host.input = require("src.adapter.input")
host.entity = require("src.adapter.entity")
host.reset_scene = require("src.adapter.reset_scene")

return host
