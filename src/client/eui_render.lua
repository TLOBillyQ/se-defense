-- src/client/eui_render.lua — 客户端哑镜像渲染器（CONTEXT.md「哑镜像」）。
-- v1 形态：零 spoke 树，订阅服务端快照并差分应用。本票只立接缝：
-- 记录最近一次快照内容，真 EUI 节点应用随后续表现层票落地。
local M = { applied = {} }

-- 应用一份快照：节点路径 → {text, visible, color, fill}。
function M.apply(snapshot)
  if type(snapshot) ~= "table" then return end
  for path, state in pairs(snapshot) do
    M.applied[path] = state
  end
end

-- 订阅 RemoteEvent 通道的客户端事件。信封 {seq, nodes, full}：
-- full 替换整树（握手/重同步），否则按节点增量合并；裸快照表直接应用。
function M.connect(channel)
  channel.OnClientEvent:Connect(function(msg)
    if type(msg) ~= "table" then return end
    if msg.nodes then
      if msg.full then M.applied = {} end
      M.apply(msg.nodes)
    else
      M.apply(msg)
    end
  end)
end

return M
