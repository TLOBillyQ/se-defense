-- src/client/main.lua — 客户端入口（SE realm：client/main.lua 自动执行）。
-- 接上服务端快照通道，交给哑镜像渲染器。
local eui_render = require("client.eui_render")

eui_render.connect(RemoteEvent.New("bd"))
