-- 适配层共享换算/拷贝：业务侧表示 → SE 宿主表示。
--
-- rgb01 是表示决策（业务只知道 0..1 浮点 RGB，宿主只认 0..255 整数 Color），
-- 两处适配器都要做同一次换算：entity.lua 的实体染色（tint × 底色）与
-- scene.lua 的静态装饰染色。抄第二份就会在取整口径上悄悄分叉，所以留在这里
-- 一份。#43 把 eui / entity 各自的 copy_vec3、copy_color 也收进来：业务传入
-- 的坐标/颜色可能是 {x,y,z} / {r,g,b,a} 具名表或数字数组，缺省通道的补值
-- 语义同样只应有一份。
local convert = {}

-- r,g,b,a 均为 0..1；a 省略即不透明。四舍五入到 0..255。
function convert.rgb01(r, g, b, a)
  local function ch(v) return math.floor(v * 255 + 0.5) end
  return Color.New(ch(r), ch(g), ch(b), ch(a or 1))
end

-- 坐标归一化拷贝：具名表 / 数字数组 → {x,y,z}，非表回退原点。
function convert.copy_vec3(v)
  if type(v) == "table" then
    return { x = v.x or v[1] or 0, y = v.y or v[2] or 0, z = v.z or v[3] or 0 }
  end
  return { x = 0, y = 0, z = 0 }
end

-- 颜色归一化拷贝：具名表 / 数字数组 → {r,g,b,a}，缺省通道补 1（白色）。
-- 已知重复：`server.ui.render_util.copy_colour` 是逐字相同的一份，理由见那边的注释
-- （#44 分层后 kernel/ 与接缝两条路都堵着，真正的位置多半是 common/，要新开路径）。
-- 改这里必须同步改那边；tests/colour_normalisation_parity_test.lua 会在漂移时失败。
function convert.copy_color(c)
  if type(c) == "table" then
    return { r = c.r or c[1] or 1, g = c.g or c[2] or 1, b = c.b or c[3] or 1, a = c.a or c[4] or 1 }
  end
  return { r = 1, g = 1, b = 1, a = 1 }
end

return convert
