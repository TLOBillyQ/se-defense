-- tools/acceptance/steps_present.lua — 表现层步骤（hud/announcer/hover/
-- health-fx 各 feature，GDD 11/12/14/15）：面板/文本行/按钮/播报/边缘警示/
-- 悬停/血条/红闪/碎裂/爆炸/着色/揭示标记的读取，悬停编排。
-- 显示状态从 EUI 节点与业务组件读取（headless 表现层读取面）；
-- 颜色以名字断言（steps_support.COLORS），比较允许 ±0.01。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, known_kind =
  S.headless, S.needs_session, S.known_kind

local PANELS = {
  ["开始"] = "sidebar/pregame", ["玩法"] = "sidebar/gameplay",
  ["胜利"] = "sidebar/victory", ["失败"] = "sidebar/gameover",
}
local EDGES = { ["东"] = "East", ["南"] = "South", ["西"] = "West", ["北"] = "North" }
local LINES = { ["首行"] = 1, ["第二行"] = 2, ["第三行"] = 3 }

-- 血条节点路径：建筑一律 building_<entity id>_hp（Building 组件统一命名）。
local function health_bar_path(s, kind, x, z)
  local b = headless.building_at(s, kind, tonumber(x), tonumber(z))
  if not b then return nil end
  return "building_" .. b.entity.id .. "_hp"
end

-- 播报行：onscreen 文本按行切分（首行/次行；无次行时次行为空）。
local function announce_lines(s)
  local text = headless.node_text(s, "announce/onscreen") or ""
  local first, second = text:match("^([^\n]*)\n?([^\n]*)$")
  return first or "", second or ""
end

return { patterns = {
  -- ── H1 面板与重开按钮 ─────────────────────────────────────────────
  { "^(%S+)面板是否显示为(%S+)$", needs_session(function(w, s, name, expect)
      local path = PANELS[name]
      if not path then return nil, "未知面板: " .. name end
      return S.expect_visible(headless.node_visible(s, path), expect, name .. "面板显示") end) },
  { "^重开按钮是否显示为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(headless.node_visible(s, "panel/restart"), expect, "重开按钮显示") end) },

  -- ── Playing 面板文本行（H2–H6）─────────────────────────────────────
  { "^资金行的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/money"), expect, "资金行") end) },
  { "^停采提示是否显示为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(headless.node_visible(s, "sidebar/gameplay/pause"), expect, "停采提示显示") end) },
  { "^停采提示的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/pause"), expect, "停采提示") end) },
  { "^停采提示的颜色为(%S+)$", needs_session(function(w, s, name)
      return S.expect_color(headless.node_color(s, "sidebar/gameplay/pause"), name, "停采提示颜色") end) },
  { "^矿点行的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/resources"), expect, "矿点行") end) },
  { "^波次行的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/wave"), expect, "波次行") end) },
  { "^倒计时行的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/countdown"), expect, "倒计时行") end) },
  { "^倒计时行的颜色为(%S+)$", needs_session(function(w, s, name)
      return S.expect_color(headless.node_color(s, "sidebar/gameplay/countdown"), name, "倒计时行颜色") end) },
  { "^消息行的文本为空$", needs_session(function(w, s)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/message"), "", "消息行") end) },
  { "^消息行的文本为(.+)$", needs_session(function(w, s, expect)
      return S.expect_text(headless.node_text(s, "sidebar/gameplay/message"), expect, "消息行") end) },
  { "^消息行的文本以(%S+)开头$", needs_session(function(w, s, prefix)
      local text = headless.node_text(s, "sidebar/gameplay/message") or ""
      if text:sub(1, #prefix) == prefix then return true end
      return nil, string.format("消息行期望以「%s」开头，实际「%s」", prefix, text) end) },

  -- ── H7 建造按钮 ───────────────────────────────────────────────────
  { "^(%w+)按钮的文本为(.+)$", needs_session(function(w, s, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      return S.expect_text(headless.node_text(s, "panel/build/" .. string.lower(kind)),
        expect, kind .. "按钮文本") end) },
  { "^(%w+)按钮是否可用为(%S+)$", needs_session(function(w, s, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      return S.expect_visible(headless.node_enabled(s, "panel/build/" .. string.lower(kind)),
        expect, kind .. "按钮可用") end) },

  -- ── A 播报与边缘警示 ──────────────────────────────────────────────
  { "^播报是否显示为(%S+)$", needs_session(function(w, s, expect)
      local shown = (headless.node_text(s, "announce/onscreen") or "") ~= ""
      return S.expect_visible(shown, expect, "播报显示") end) },
  { "^播报次行的文本为空$", needs_session(function(w, s)
      local _, second = announce_lines(s)
      return S.expect_text(second, "", "播报次行") end) },
  { "^播报首行的文本为(.+)$", needs_session(function(w, s, expect)
      local first = announce_lines(s)
      return S.expect_text(first, expect, "播报首行") end) },
  { "^播报次行的文本为(.+)$", needs_session(function(w, s, expect)
      local _, second = announce_lines(s)
      return S.expect_text(second, expect, "播报次行") end) },
  { "^(%S+)边缘警示是否显示为(%S+)$", needs_session(function(w, s, edge, expect)
      local eng = EDGES[edge]
      if not eng then return nil, "未知边缘: " .. edge end
      return S.expect_visible(headless.warning_active(s, eng), expect, edge .. "边缘警示显示") end) },
  { "^(%S+)边缘警示的闪烁周期为([%d.]+)秒$", needs_session(function(w, s, edge, expect)
      if not EDGES[edge] then return nil, "未知边缘: " .. edge end
      return S.eq_num(headless.blink_period(s), expect, edge .. "边缘警示闪烁周期") end) },

  -- ── V 悬停（悬停/清除悬停是编排动作；命中判定归棋盘输入）────────────
  { "^悬停位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%S+)$", needs_session(function(w, s, x, z, what)
      if what ~= "矿点" then
        local _, bad = known_kind(what)
        if bad then return nil, bad end
      end
      headless.send(s, { kind = "input", itype = "hover", x = tonumber(x), z = tonumber(z) })
      return true end) },
  { "^清除悬停$", needs_session(function(w, s)
      headless.send(s, { kind = "input", itype = "hover" })
      return true end) },
  { "^悬停是否存在为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(headless.hover_target(s) ~= nil, expect, "悬停存在") end) },
  { "^悬停描述(%S+)的文本为(.+)$", needs_session(function(w, s, which, expect)
      local index = LINES[which]
      if not index then return nil, "未知描述行: " .. which end
      local lines = headless.hover_lines(s)
      if not lines then return nil, "当前没有悬停" end
      return S.expect_text(lines[index], expect, "悬停描述" .. which) end) },

  -- ── F 血条与特效 ──────────────────────────────────────────────────
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条是否显示为(%S+)$",
    needs_session(function(w, s, x, z, kind, expect)
      local path = health_bar_path(s, kind, x, z)
      if not path then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      return S.expect_visible(headless.node_visible(s, path), expect, kind .. "血条显示") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条比例为([%d.]+)$",
    needs_session(function(w, s, x, z, kind, expect)
      local path = health_bar_path(s, kind, x, z)
      if not path then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      local fill = headless.node_fill(s, path)
      if fill and math.abs(fill - tonumber(expect)) <= S.COLOR_TOL then return true end
      return nil, string.format("位于(%s,%s)的%s血条比例期望 %s，实际 %s",
        x, z, kind, expect, tostring(fill)) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条颜色为(%S+)$",
    needs_session(function(w, s, x, z, kind, name)
      local path = health_bar_path(s, kind, x, z)
      if not path then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      return S.expect_color(headless.node_color(s, path), name, kind .. "血条颜色") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)是否红闪为(%S+)$",
    needs_session(function(w, s, x, z, kind, expect)
      local tint = headless.building_tint(s, kind, tonumber(x), tonumber(z))
      if not tint then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      -- 受击红闪 = 实体纯红（1,0,0），见 Building.blink。
      local flashing = math.abs(tint[1] - 1) <= S.COLOR_TOL
        and math.abs(tint[2]) <= S.COLOR_TOL and math.abs(tint[3]) <= S.COLOR_TOL
      return S.expect_visible(flashing, expect, kind .. "红闪") end) },
  { "^(%w+)是否碎裂中为(%S+)$", needs_session(function(w, s, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      return S.expect_visible(headless.crumbling(s, kind), expect, kind .. "碎裂中") end) },
  { "^Core是否播放爆炸为(%S+)$", needs_session(function(w, s, expect)
      return S.expect_visible(headless.node_visible(s, "core_explosion"), expect, "Core 爆炸") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)的着色为([%d.]+)$",
    needs_session(function(w, s, x, z, kind, expect)
      local tint = headless.building_tint(s, kind, tonumber(x), tonumber(z))
      if not tint then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
      local v = tonumber(expect)
      if math.abs(tint[1] - v) <= S.EPS and math.abs(tint[2] - v) <= S.EPS
        and math.abs(tint[3] - v) <= S.EPS then
        return true
      end
      return nil, string.format("位于(%s,%s)的%s着色期望 %s，实际 (%s,%s,%s)",
        x, z, kind, expect, tint[1], tint[2], tint[3]) end) },
  { "^第(%d+)个敌人是否带揭示标记为(%S+)$", needs_session(function(w, s, n, expect)
      local e = headless.enemy_nth(s, tonumber(n))
      if not e then return nil, "还没有第 " .. n .. " 个敌人" end
      return S.expect_visible(headless.enemy_marked(s, e), expect, "第 " .. n .. " 个敌人揭示标记") end) },
} }
