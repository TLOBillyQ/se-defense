-- 适配层共享换算/拷贝：业务侧表示 → SE 宿主表示。
--
-- rgb01 是表示决策（业务只知道 0..1 浮点 RGB，宿主只认 0..255 整数 Color），
-- 两处适配器都要做同一次换算：entity.lua 的实体染色（tint × 底色）与
-- scene.lua 的静态装饰染色。抄第二份就会在取整口径上悄悄分叉，所以留在这里
-- 一份。#43 把 eui / entity 各自的 copy_vec3、copy_color 也收进来；#44 后
-- 颜色归一化（copy_color）进一步收进 common/color_norm.lua（双端共用的事实），
-- 本文件只保留坐标拷贝并转发颜色归一化。
local color_norm = require("common.color_norm")

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

-- 颜色归一化拷贝：唯一实现住 common/color_norm.lua，这里只转发。
convert.copy_color = color_norm.copy_color

return convert
