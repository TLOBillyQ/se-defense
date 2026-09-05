-- 05_BaseDefence EUI 渲染辅助（CoverageDisplay / LinkDisplay 共用）。
--
-- 颜色：EUI 颜色接受 {r=,g=,b=,a=} 具名表或 {r,g,b,a} 数字数组，缺省通道补 1，
-- 非表回退为白色（与 server.adapter.eui 的 copy_color 归一化语义一致）；read_colour
-- 额外支持把颜色做成响应式信号（s:d 读当前值）。
-- 节点：渲染循环把本轮创建的节点登记进 created 表，effect 卸载时统一销毁。

local render_util = {}

--- 归一化颜色表 → {r,g,b,a}。
function render_util.copy_colour(c)
  if type(c) == "table" then
    return {
      r = c.r or c[1] or 1,
      g = c.g or c[2] or 1,
      b = c.b or c[3] or 1,
      a = c.a or c[4] or 1,
    }
  end
  return { r = 1, g = 1, b = 1, a = 1 }
end

--- 取颜色当前值：颜色信号用 s:d 读，普通表原样返回。
function render_util.read_colour(s, colour)
  if type(colour) == "table" and type(colour.now) == "function" then
    return s:d(colour)
  end
  return colour
end

--- read_colour + copy_colour 的组合：s:d 后归一化为 {r,g,b,a}。
function render_util.colour_value(s, value)
  return render_util.copy_colour(render_util.read_colour(s, value))
end

--- effect 卸载时销毁 created 里登记的所有 EUI 节点（已销毁的跳过）。
function render_util.destroy_created(s, host, created)
  s:on_cleanup(function()
    for node_path in pairs(created) do
      local node = host.eui.nodes[node_path]
      if node then
        host.eui.destroy(node)
      end
    end
  end)
end

return render_util
