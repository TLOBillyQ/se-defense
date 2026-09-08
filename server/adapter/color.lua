-- 适配层颜色换算：业务/配置侧的 0..1 浮点 RGB → SE 的 0..255 整数 Color。
--
-- 单独成模块是因为这是一个表示决策（业务只知道 0..1，宿主只认 0..255），
-- 两处适配器都要做同一次换算：entity.lua 的实体染色（tint × 底色）与
-- scene.lua 的静态装饰染色。抄第二份就会在取整口径上悄悄分叉。
local color = {}

-- r,g,b,a 均为 0..1；a 省略即不透明。四舍五入到 0..255。
function color.rgb01(r, g, b, a)
  local function ch(v) return math.floor(v * 255 + 0.5) end
  return Color.New(ch(r), ch(g), ch(b), ch(a or 1))
end

return color
