-- RemoteEvent 通道 bd_game 的客户端半（#18）：快照下行 → 渲染器；意图/握手上行。
--
--   - 先挂 OnClientEvent 再发 client_ready 握手，重试至首快照（F11 文档范式）；
--   - seq 缺口 → resync 请求全量重同步（#18 决策 1），1s 冷却防风暴；
--   - full / reset 整树替换（#28：reset 后 gen+1，渲染器按 "<id>g<gen>" 寻单位）。

local M = {}
local Ch = {}
Ch.__index = Ch

-- deps: log、renderer（client.eui_render 实例）、now() → 客户端已运行秒数
function M.new(deps)
  local self = setmetatable({
    log = deps.log,
    renderer = deps.renderer,
    now = deps.now,
    re = RemoteEvent.New("bd_game"),
    last_seq = 0,
    got_first = false,
    resync_cooldown = 0,
    ready_retry_acc = 0,
  }, Ch)
  self.re.OnClientEvent:Connect(function(msg) self:_on_message(msg) end)
  self:send({ kind = "client_ready" })
  self.log("client_ready 已发送（先监听后握手）")
  return self
end

function Ch:send(msg)
  self.re:FireServer(msg)
end

function Ch:_on_message(msg)
  if type(msg) ~= "table" then return end
  local kind = msg.kind
  local renderer = self.renderer
  renderer:set_generation(msg.gen)
  if kind == "full" or kind == "reset" then
    self.last_seq = msg.seq or self.last_seq
    self.got_first = true
    renderer:replace_all(msg.nodes)
    self.log("全量快照应用 kind=%s seq=%s gen=%s", kind, tostring(msg.seq), tostring(msg.gen))
  elseif kind == "delta" then
    self.got_first = true
    if type(msg.seq) == "number" and self.last_seq > 0 and msg.seq ~= self.last_seq + 1 then
      local t = self.now()
      if t >= self.resync_cooldown then
        self.resync_cooldown = t + 1
        self.log("快照缺口 %d → %d，请求 resync", self.last_seq, msg.seq)
        self:send({ kind = "resync" })
      end
    end
    if type(msg.seq) == "number" then self.last_seq = msg.seq end
    renderer:apply(msg.nodes, msg.removed)
  end
end

-- 每帧调用：首快照到达前每 2s 重发 client_ready
function Ch:tick(dt)
  if self.got_first then return end
  self.ready_retry_acc = self.ready_retry_acc + dt
  if self.ready_retry_acc >= 2 then
    self.ready_retry_acc = 0
    self:send({ kind = "client_ready" })
  end
end

return M
