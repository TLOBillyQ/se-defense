-- src/client/eui_render.lua — 客户端哑镜像渲染器（CONTEXT.md「哑镜像」）。
-- v1 形态：零 spoke 树，订阅服务端快照并差分应用。本票只立接缝：
-- 记录最近一次快照内容，真 EUI 节点应用随后续表现层票落地。
-- 混合快照协议（CONTEXT.md「快照」）：信封 {seq, nodes, full}；上线握手
-- 与序号缺口都向服务端发 client_ready 索取全量重同步。
local M = { applied = {}, seq = 0 }

-- 应用一份快照：节点路径 → {text, visible, color, fill}。
function M.apply(snapshot)
  if type(snapshot) ~= "table" then return end
  for path, state in pairs(snapshot) do
    M.applied[path] = state
  end
end

local function request_full(channel)
  if channel.FireServer then channel:FireServer({ action = "client_ready" }) end
end

-- 处理一封信封：full 替换整树；增量要求 seq 恰好 +1，缺口则丢弃并索取全量；
-- 裸快照表（无 seq）直接应用。
function M.receive(channel, msg)
  if type(msg) ~= "table" then return end
  if not msg.nodes then
    M.apply(msg)
    return
  end
  if msg.full then
    M.applied = {}
    M.apply(msg.nodes)
    M.seq = msg.seq or M.seq
    return
  end
  if msg.seq ~= M.seq + 1 then
    request_full(channel)
    return
  end
  M.seq = msg.seq
  M.apply(msg.nodes)
end

-- 订阅 RemoteEvent 通道的客户端事件；订阅即握手索取全量。
function M.connect(channel)
  channel.OnClientEvent:Connect(function(msg) M.receive(channel, msg) end)
  request_full(channel)
end

return M
