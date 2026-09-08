-- 双端共用：颜色归一化。
--
-- 表示约定：EUI / 适配层颜色接受 {r=,g=,b=,a=} 具名表或 {r,g,b,a} 数字数组，
-- 缺省通道补 1（白色）；非表回退为不透明白色。这是双端共用的表示事实，
-- 不碰任何 SE 全局，所以住 common/ 而不是 server/host/ 或 server/ui/。
local color_norm = {}

function color_norm.copy_color(c)
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

return color_norm
