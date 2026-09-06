-- src/server/adapter/host.lua — 宿主适配层：把 SE 宿主接到规则层。
-- 职责：持有一局 match_flow，用 RunService.Heartbeat 以宿主固定步长
-- （1/30 秒，CONTEXT.md「GameTick」）驱动规则层；把客户端经 RemoteEvent
-- 上行的玩家意图（开始对局 / 重开 / 放置）路由给规则层。
-- 无头验证时本模块原样运行在 tools/headless/se_stub.lua 提供的 SE 全局上。
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local eui = require("server.adapter.eui")

local M = { FIXED_DT = 1 / 30 }

-- SE 全局 game 与规则层对局对象同名易混，宿主服务统一经此取。
local function se(name)
  return _G.game:GetService(name)
end

-- 玩家意图路由：msg = { action = "start" | "restart" | "place" |
-- "select" | "confirm" | "cancel", ... }。place 是「选择待建 + 确认」的复合。
function M.handle(match, msg)
  if type(match) ~= "table" or type(msg) ~= "table" then return end
  if msg.action == "start" then
    match:start()
  elseif msg.action == "restart" then
    match:restart()
  elseif msg.action == "place" then
    match:place(msg.kind, msg.x, msg.z)
  elseif msg.action == "select" then
    match:select(msg.kind)
  elseif msg.action == "confirm" then
    match:confirm(msg.x, msg.z)
  elseif msg.action == "cancel" then
    match:cancel()
  end
end

-- 启动一局：match 可由入口注入（默认新建）。返回对局对象，同时挂在 M.match
-- （M.presenter 为表现层显示状态）供无头 harness 经真入口启动后取回。
-- 每拍：推进规则层 → 推进表现层 → 快照经 eui 路由推给客户端；
-- 客户端 client_ready 上行触发全量重同步。
function M.boot(match)
  match = match or match_flow.new()
  local pres = presenter.new(match)
  local channel = RemoteEvent.New("bd")
  local router = eui.new(channel)
  se("RunService").Heartbeat:Connect(function(dt)
    dt = dt or M.FIXED_DT
    match:advance(dt)
    pres:tick(dt)
    router:push(pres:snapshot())
  end)
  channel.OnServerEvent:Connect(function(_, msg)
    if type(msg) == "table" and msg.action == "client_ready" then
      router:client_ready()
    else
      M.handle(match, msg)
    end
  end)
  M.match = match
  M.presenter = pres
  return match
end

return M
