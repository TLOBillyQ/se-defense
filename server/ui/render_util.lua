-- 05_BaseDefence EUI 渲染辅助（CoverageDisplay / LinkDisplay 共用）。
--
-- 颜色：EUI 颜色接受 {r=,g=,b=,a=} 具名表或 {r,g,b,a} 数字数组，缺省通道补 1，
-- 非表回退为白色（与 server.host.convert 的 copy_color 归一化语义一致）；read_colour
-- 额外支持把颜色做成响应式信号（s:d 读当前值）。
-- 节点：渲染循环把本轮创建的节点登记进 created 表，effect 卸载时统一销毁。

local render_util = {}

--- 归一化颜色表 → {r,g,b,a}。
--
-- 已知重复：`server.host.convert.copy_color` 是逐字相同的一份。归一化本身不是宿主
-- 知识（不碰任何 SE 全局），两边都只是把「具名表 / 数字数组、缺省通道补 1」这条表示
-- 约定实现一遍，所以理应只有一份。#44 分层后仍收不掉，三条路都堵着：
--   - 放 kernel/（层 8）：host（层 9）不能反向依赖它，方向规则不允许；
--   - 让 ui/ 直接 require server.host.convert：层 4 → 9 门禁允许，但破掉
--     「业务只经 server.host 一个接缝」（server/README.md「宿主接缝」）；
--   - 挂到 host 表上经接缝取：不破接缝，但把一条与宿主无关的表示约定塞进宿主面，
--     接缝凭空多一个成员。
-- 真正的位置多半是 common/（两端共享的表示约定），那要新开路径。与
-- `entity.unit_name` 的双端契约完全同类，#44 对那条也明确「本单只记录」。
-- 改这里必须同步改 convert.copy_color；
-- tests/colour_normalisation_parity_test.lua 会在两份漂移时失败。
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
