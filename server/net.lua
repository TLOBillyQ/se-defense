-- RemoteEvent 通道 bd_game 的服务端半（#18）：快照下行 + 握手/意图上行。
--
--   - 下行：full（client_ready / resync 应答）、delta（每帧 dirty 即发，#18 决策 2）、
--     reset（重开后整树替换，#28）；每条带单调 seq 与 host.eui.generation。
--   - 上行 input 意图：start / tap / hover / cancel / place / restart。入参按不可信输入
--     校验（类型白名单、有限数值、字符串长度）；棋盘边界判定不在这里重复，统一交给
--     host.input（set_bounds 注入的 level_bounds），界外 tap 无动作、界外 hover 清指针。
--
-- 与 server/gm.lua 同级：编排业务（root）与适配层（host / BuildPanel），适配层不反向依赖。

local BuildPanel = require("server.adapter.build_panel")

local M = {}
local Net = {}
Net.__index = Net

local function finite_number(v)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

-- ctx：host、log(fmt, ...)、root() 当前组合根、panel() 当前放置面板、restart(why) 整局重开
function M.create(ctx)
  local self = setmetatable({
    host = ctx.host, log = ctx.log,
    root = ctx.root, panel = ctx.panel, restart = ctx.restart,
    re = RemoteEvent.New("bd_game"),
    seq = 0,
  }, Net)
  self.re.OnServerEvent:Connect(function(_player, args) self:_on_message(args) end)
  return self
end

function Net:send(kind, payload)
  self.seq = self.seq + 1
  local msg = payload or {}
  msg.kind = kind
  msg.seq = self.seq
  msg.gen = self.host.eui.generation
  self.re:FireAllClients(msg)
end

function Net:send_full()
  self:send("full", { nodes = self.host.eui.full() })
end

-- 重开后调用：丢弃重建期间攒下的增量，广播 reset 全量（gen 已 +1，客户端整树替换）
function Net:send_reset()
  self.host.eui.drain()
  self:send("reset", { nodes = self.host.eui.full() })
end

-- 每帧派发结束后调用：有 dirty 就发 delta
function Net:flush_delta()
  local delta = self.host.eui.drain()
  if delta then self:send("delta", delta) end
end

function Net:_on_message(args)
  if type(args) ~= "table" then return end
  local kind = args.kind
  if kind == "client_ready" or kind == "resync" then
    self.log("%s 到达，发全量快照（nodes=%d）", kind, #self.host.eui.order)
    self:send_full()
  elseif kind == "input" then
    self:_on_intent(args)
  end
end

function Net:_on_intent(args)
  local host, log, root = self.host, self.log, self.root()
  local itype = args.itype
  if itype == "start" then
    -- GDD 01 R2：玩家主动开始对局（Pregame 外无效，业务侧守卫）
    if root.game_state.mode:now() == "Pregame" then
      root.game_state:start_game()
      log("输入 start → Playing")
    end
  elseif itype == "tap" then
    local x, z = finite_number(args.x), finite_number(args.z)
    if x and z then
      log("输入 tap → (%.2f, %.2f)", x, z)
      host.input.intent_tap(x, z)
    end
  elseif itype == "hover" then
    local x, z = finite_number(args.x), finite_number(args.z)
    if x and z then
      host.input.intent_hover(x, z)
    elseif args.x == nil then
      host.input.intent_hover(nil, nil) -- 抬指/出界
    end
  elseif itype == "cancel" then
    log("输入 cancel")
    host.input.intent_cancel()
  elseif itype == "place" then
    local key = args.key
    if type(key) == "string" and #key <= 16 then
      local ok, why = BuildPanel.place(self.panel(), key)
      log("输入 place(%s) → %s", key, ok and "placing 置位" or tostring(why))
    end
  elseif itype == "restart" then
    -- 只在终局受理（按钮也只在终局可见）；Playing 中的误发/重放一律忽略
    if BuildPanel.restart_allowed(self.panel()) then
      self.restart("client")
    else
      log("输入 restart 被拒（mode=%s）", tostring(root.game_state.mode:now()))
    end
  end
end

return M
