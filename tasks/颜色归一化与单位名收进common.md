# 颜色归一化与单位名收进common

把两处双端共用的事实从 host/ 与 ui/client 的重复实现收敛到 common/。

两条重复，现在靠测试和注释兜着，不是靠结构：

1. 颜色归一化
   server/host/convert.lua:29 copy_color
   server/ui/render_util.lua:22 copy_colour
   两份逐字相同，tests/colour_normalisation_parity_test.lua 守着它们不漂移。

2. 单位名约定
   server/host/entity.lua:56 entity.unit_name
   client/eui_render.lua:337 R:_unit_name
   双端契约（首局裸 id，重开后 "<id>g<gen>"，#28），靠注释对齐。

#43/#44 对这两条都明写「本单只记录，不改」，现在来还。

收敛不掉的旧理由在 game目录重构 之后失效了，新的约束是：
host/ 现在是第 9 层、最底层，不能依赖 kernel/(8)；从缝里绕会把一个
非宿主关注点塞进 host 表。所以出口不是 kernel/ 而是 common/——
归一化语义和双端命名约定本来就是双端共用的事实，common/ 是它们的正确归宿。

做完后：两处重复各自消失，平价测试要么删掉要么改成守 common/ 的单一实现；
arch 门禁不得出现新的上行边。
