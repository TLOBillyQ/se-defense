-- 客户端入口（#19 垂直切片 + #21 放置 + #28 重开）：只做装配与 Heartbeat 驱动。
--
-- 架构（#7/#8/#18 决议）：客户端零 spoke 树（#7-A6），哑镜像。
--   client/channel.lua      RemoteEvent bd_game：快照下行 → 渲染器；握手/resync/意图上行
--   client/eui_render.lua   快照 → 真 EUI/SceneGui 节点差分应用（recipe 表）
--   client/camera.lua       固定正俯视相机 + EUI 画布 ↔ 棋盘坐标换算与标定
--   client/board_input.lua  透明捕获层触摸 → hover/tap 意图；PC 右键/Escape 取消；悬停轮询
--   client/gm.lua           _G.bd_client（集成测试注入面）
--
-- 日志前缀 [bd][client]。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Renderer = require("client.eui_render")
local Channel = require("client.channel")
local Camera = require("client.camera")
local BoardInput = require("client.board_input")
local GM = require("client.gm")

local function log(fmt, ...)
  print("[bd][client] " .. string.format(fmt, ...))
end

local elapsed = 0
local screen_res = nil
local function now() return elapsed end
local function get_res() return screen_res end

local channel
local renderer = Renderer.new({
  log = log,
  get_res = get_res,
  -- 按钮点击回流（#21/#28）：panel/build/<key> → place，panel/cancel → cancel，
  -- panel/restart → restart（服务端只在终局受理）
  on_click = function(path)
    local key = path:match("^panel/build/(%a+)$")
    if key then
      channel:send({ kind = "input", itype = "place", key = key })
    elseif path == "panel/cancel" then
      channel:send({ kind = "input", itype = "cancel" })
    elseif path == "panel/restart" then
      channel:send({ kind = "input", itype = "restart" })
    end
  end,
})
channel = Channel.new({ log = log, renderer = renderer, now = now })

local camera = Camera.new({ log = log, get_res = get_res })
local board_input = BoardInput.new({
  log = log, camera = camera, now = now,
  send = function(msg) channel:send(msg) end,
})

-- EUI 根就绪后（PlayerGui.EuiManager 可用）挂渲染器根与捕获层；成功返回 true
local eui_ready = false
local function setup_eui()
  local localPlayer = Players.LocalPlayer
  if not localPlayer or not localPlayer.PlayerGui then return false end
  local mgr = localPlayer.PlayerGui.EuiManager
  if not mgr then return false end
  local root = mgr:GetRootNode()
  local res = mgr:GetDeviceResolution()
  if not root or not res then return false end
  screen_res = res
  renderer:set_root(root)
  board_input:setup(root, res)
  return true
end

RunService.Heartbeat:Connect(function(deltaTime)
  elapsed = elapsed + deltaTime

  if not eui_ready then
    eui_ready = setup_eui()
    if eui_ready then log("EUI 就绪 @%.2fs", elapsed) end
  end

  channel:tick(deltaTime)
  camera:tick(deltaTime, elapsed)
  board_input:tick(deltaTime, screen_res)
  renderer:tick(deltaTime)
end)

_G.bd_client = GM.create({ log = log, renderer = renderer, camera = camera, channel = channel })

log("客户端挂载完成：快照渲染 + 放置面板按钮 + 固定俯视相机 + 棋盘捕获层")
