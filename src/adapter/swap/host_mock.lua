-- 同路径替换文件：部署到 examples/base_defence/host_mock.lua。
-- 业务模块的 require("examples.base_defence.host_mock") 由此落到适配层组合根，
-- require 路径不变是业务零改动的机制。

return require("src.adapter.host")
