-- tools/acceptance/steps_support.lua — gameplay/presentation 步骤共用的前置
-- 包装与校验。不是步骤表；各 steps_<系统>.lua 从这里取 needs_session /
-- expect_yes_no / known_kind / find_building / find_site，steps.lua 只做汇总分发。
local headless = require("tools.acceptance.headless")

local M = { headless = headless, EPS = 1e-6, NEAR = 0.05 }

-- GDD 实体总表（docs/gdd/00-world.md）：步骤里的类型名必须来自此表，
-- 拒绝拼写变体。Site 在 feature 里以「矿点」出现，不出现在 (%w+) 捕获中。
M.KINDS = { Core = true, Relay = true, Radar = true, Turret = true, Repair = true, Site = true }

-- 前置包装：handler 需要一局已启动的对局（背景步骤「一局新对局」）。
function M.needs_session(fn)
  return function(w, ...)
    if not w.game then return nil, "尚未启动对局（背景缺「一局新对局」）" end
    return fn(w, w.game, ...)
  end
end

function M.expect_yes_no(value)
  if value ~= "是" and value ~= "否" then
    return nil, "在场期望只能是 是/否，实际 " .. tostring(value)
  end
  return value == "是"
end

function M.known_kind(kind)
  if M.KINDS[kind] then return true end
  return nil, "未知实体: " .. tostring(kind)
end

-- 按类型与坐标（步骤捕获的字符串）取在场建筑组件；类型未知或该处无建筑时给出原因。
function M.find_building(s, kind, x, z)
  local _, bad = M.known_kind(kind)
  if bad then return nil, bad end
  local b = headless.building_at(s, kind, tonumber(x), tonumber(z))
  if not b then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
  return b
end

function M.find_site(s, x, z)
  local site = headless.site_at(s, tonumber(x), tonumber(z))
  if not site then return nil, string.format("(%s,%s) 处没有矿点", x, z) end
  return site
end

-- 数值比较：exact（EPS）用于整数断言，near（0.05）用于 feature 约定的血量/位置。
function M.eq_num(actual, expect, label)
  if math.abs(actual - tonumber(expect)) <= M.EPS then return true end
  return nil, string.format("%s 期望 %s，实际 %s", label, tostring(expect), tostring(actual))
end

function M.near_num(actual, expect, label)
  if math.abs(actual - tonumber(expect)) <= M.NEAR then return true end
  return nil, string.format("%s 期望 %s，实际 %s", label, tostring(expect), tostring(actual))
end

-- GDD 命名色板（11 H8 / 15 F1 / 13 O3；与 rewrite presenter.colors 同值）。
-- 颜色比较允许 ±0.01（feature 约定）。
M.COLORS = {
  ["淡蓝"] = { 0.6, 0.8, 1 }, ["琥珀"] = { 1, 0.737, 0 }, ["危险红"] = { 1, 0.3, 0.3 },
  ["绿"] = { 0.2, 0.8, 0.2 }, ["黄"] = { 1, 0.85, 0 }, ["红"] = { 1, 0.25, 0.25 },
}
M.COLOR_TOL = 0.01

function M.expect_color(actual, name, label)
  local want = M.COLORS[name]
  if not want then return nil, "未知颜色: " .. tostring(name) end
  if not actual then return nil, label .. "没有颜色可读" end
  for i = 1, 3 do
    if math.abs(actual[i] - want[i]) > M.COLOR_TOL then
      return nil, string.format("%s期望 %s (%s)，实际 (%s)", label, name,
        table.concat(want, ","), table.concat(actual, ","))
    end
  end
  return true
end

function M.expect_visible(actual, expect, label)
  local want, bad = M.expect_yes_no(expect)
  if bad then return nil, bad end
  if actual == want then return true end
  return nil, string.format("%s期望 %s，实际 %s", label, expect, actual and "是" or "否")
end

function M.expect_text(actual, expect, label)
  if actual == expect then return true end
  return nil, string.format("%s期望「%s」，实际「%s」", label, expect, tostring(actual))
end

return M
