-- server.host.convert.copy_color 与 server.ui.render_util.copy_colour 是同一条
-- 表示约定的两份实现（具名表 / 数字数组 → {r,g,b,a}，缺省通道补 1）。收不掉的理由见
-- render_util.lua 的注释：业务侧只经 host 依赖适配层，收敛需要新路径，#43 不动路径。
--
-- 在那之前，这条测试替代「靠注释保持一致」：两份实现在同一批输入上必须给出相同结果，
-- 任何一侧单独改口径都会在这里转红。
local lu = require("luaunit")
local convert = require("server.host.convert")
local render_util = require("server.ui.render_util")

TestColourNormalisationParity = {}

local CASES = {
  { r = 0.2, g = 0.4, b = 0.6, a = 0.8 },
  { r = 0.2, g = 0.4, b = 0.6 },
  { 0.1, 0.2, 0.3, 0.4 },
  { 0.1, 0.2, 0.3 },
  { 0.1, 0.2 },
  { 0.1 },
  { r = 0, g = 0, b = 0, a = 0 },
  { b = 0.5 },
  {},
  "not a table",
  42,
  true,
}

function TestColourNormalisationParity:test_both_implementations_agree()
  for i = 1, #CASES do
    local input = CASES[i]
    lu.assertEquals(render_util.copy_colour(input), convert.copy_color(input),
      "第 " .. i .. " 个输入两侧归一化结果不一致")
  end
end

-- nil 单列：放进 CASES 会在数组里留洞，#CASES 就不可靠了。
function TestColourNormalisationParity:test_both_implementations_agree_on_nil()
  lu.assertEquals(render_util.copy_colour(nil), convert.copy_color(nil))
end

-- 具体口径也钉一下，免得两侧一起漂走还互相"一致"。
function TestColourNormalisationParity:test_missing_channels_default_to_white()
  lu.assertEquals(convert.copy_color({}), { r = 1, g = 1, b = 1, a = 1 })
  lu.assertEquals(convert.copy_color("nope"), { r = 1, g = 1, b = 1, a = 1 })
end

function TestColourNormalisationParity:test_named_table_wins_over_array_slot()
  lu.assertEquals(convert.copy_color({ 0.1, 0.2, 0.3, r = 0.9 }).r, 0.9)
end
