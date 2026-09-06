-- src/server/main.lua — 服务端入口（SE realm：server/main.lua 自动执行）。
-- 建局并交给宿主适配层接管节拍与玩家意图。
local match_flow = require("server.game.match_flow")
local host = require("server.adapter.host")

host.boot(match_flow.new())
