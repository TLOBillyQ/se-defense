-- 05_BaseDefence 电力连线显示（LinkDisplay 的宿主等价物）。
--
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/LinkDisplay.cs：
--   - draw_all：画出电网中每个节点的 parent 链段（全局生成树）；
--   - draw_chain：从给定节点沿 parent 一直画到根。
--
-- 上游用 line mesh 渲染线段列表；本端口按 #18 Q8 裁剪为“每段一条 EUI line
-- 节点”，host-mock 下只保留可断言状态，真机把 line 节点换成对应 EUI 线条。
-- 线段集合变化时重建本 effect 拥有的节点，并在 effect 卸载时全部销毁。

local PowerNode = require("server.game.power_node")
local render_util = require("server.game.render_util")

local LinkDisplay = {}

local function segment_key(node, index)
  return node._serial or tostring(node)
end

-- 在当前 effect block 中渲染 segments 并登记本轮的 cleanup。
local function render_segments(s, host, path_prefix, segments, colour_now)
  local created = {}
  for index, segment in ipairs(segments) do
    local node_path = ("%s_%s_%d"):format(path_prefix, segment_key(segment.node, index), index)
    local node = host.eui.nodes[node_path] or host.eui.node(node_path)
    node:set_visible(true)
    node:set_line(segment.from, segment.to)
    node:set_color(colour_now)
    created[node_path] = true
  end

  render_util.destroy_created(s, host, created)
end

--- 画出 PowerNode.all 里所有 parent 非空的链段。
function LinkDisplay.draw_all(s, opts)
  local host = opts.host or error("LinkDisplay.draw_all requires host", 2)
  local path = opts.path or error("LinkDisplay.draw_all requires path", 2)

  s:effect("LinkDisplay.All:" .. path, function(sb)
    local segments = {}
    for _, node in ipairs(sb:d(PowerNode.all)) do
      local parent = sb:d(node.parent)
      if parent ~= nil then
        segments[#segments + 1] = {
          node = node,
          from = node:position(),
          to = parent:position(),
        }
      end
    end
    render_segments(sb, host, path, segments, render_util.colour_value(sb, opts.colour))
  end)
end

--- 从 start 节点沿 parent 链画到根。
function LinkDisplay.draw_chain(s, opts)
  local host = opts.host or error("LinkDisplay.draw_chain requires host", 2)
  local path = opts.path or error("LinkDisplay.draw_chain requires path", 2)
  local start = opts.start

  s:effect("LinkDisplay.Chain:" .. path, function(sb)
    local segments = {}
    local visited = {}
    local node = start
    while node and not visited[node] do
      visited[node] = true
      local parent = sb:d(node.parent)
      if parent == nil then
        break
      end
      segments[#segments + 1] = {
        node = node,
        from = node:position(),
        to = parent:position(),
      }
      node = parent
    end
    render_segments(sb, host, path, segments, render_util.colour_value(sb, opts.colour))
  end)
end

return LinkDisplay
