-- src/server/adapter/eui.lua — 快照路由适配器（CONTEXT.md「快照」「双路由」）。
-- 表现层产出的快照（节点路径 → {text, visible, color, fill}）经 RemoteEvent
-- 推向客户端：平时节点级增量（带单调 seq），握手（client_ready）时全量重
-- 同步。ring/line 形状不走这里（就地渲为 EffectUnit，本票不含）。
-- 只依赖通道对象（FireAllClients），无头与真宿主同路径运行。
local M = {}

local Router = {}
Router.__index = Router

function M.new(channel)
  return setmetatable({ channel = channel, seq = 0, sent = {} }, Router)
end

-- 状态值按内容比较（color 等数组逐元素）。
local function state_equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not state_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function copy(state)
  local out = {}
  for k, v in pairs(state) do
    if type(v) == "table" then out[k] = copy(v) else out[k] = v end
  end
  return out
end

-- 推一帧：diff 非空才发；full 为真时全量重同步。
function Router:push(snapshot, full)
  local diff = {}
  for path, state in pairs(snapshot or {}) do
    if full or not state_equal(self.sent[path], state) then
      diff[path] = state
      self.sent[path] = copy(state)
    end
  end
  for path in pairs(self.sent) do
    if not snapshot or snapshot[path] == nil then -- 节点消失按隐藏通知
      self.sent[path] = nil
      diff[path] = { visible = false }
    end
  end
  if not full and not next(diff) then return nil end
  self.seq = self.seq + 1
  local msg = { seq = self.seq, nodes = diff }
  if full then msg.full = true end
  self.channel:FireAllClients(msg)
  return msg
end

-- 握手：客户端上线或发现序号缺口 → 全量重同步。
function Router:client_ready()
  local full = {}
  for path, state in pairs(self.sent) do full[path] = copy(state) end
  self.seq = self.seq + 1
  local msg = { seq = self.seq, nodes = full, full = true }
  self.channel:FireAllClients(msg)
  return msg
end

return M
