-- tools/acceptance/steps_present.lua — 表现层步骤（presentation 各 feature，
-- GDD 11/12/14/15 + 16 I5/I6）：面板/文本行/按钮/消息行/播报/边缘警示/
-- 悬停/血条/红闪/碎裂/爆炸/着色/揭示标记的读取与编排（悬停、清除悬停、
-- 资金设定、选择待建、取消放置）。显示状态从 server.present.presenter 读取；
-- 颜色以名字断言（值见 feature 约定与 GDD H8），比较允许 ±0.01。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, needs_match, expect_yes_no, known_kind, find_at, EPS =
  S.headless, S.needs_session, S.needs_match, S.expect_yes_no, S.known_kind, S.find_at, S.EPS

local COLOR_TOL = 0.01 -- feature 约定：颜色比较允许 ±0.01
local COLORS = {
  ["淡蓝"] = { 0.6, 0.8, 1 }, ["琥珀"] = { 1, 0.737, 0 }, ["危险红"] = { 1, 0.3, 0.3 },
  ["绿"] = { 0.2, 0.8, 0.2 }, ["黄"] = { 1, 0.85, 0 }, ["红"] = { 1, 0.25, 0.25 },
}

local PANELS = { ["开始"] = "pregame", ["玩法"] = "playing",
  ["胜利"] = "victory", ["失败"] = "gameover" }
local EDGES = { ["东"] = true, ["南"] = true, ["西"] = true, ["北"] = true }
local LINES = { ["首行"] = 1, ["第二行"] = 2, ["第三行"] = 3 }

-- 需要显示状态的步骤：注入 session 与 presenter。
local function needs_pres(fn)
  return needs_session(function(w, s, ...)
    return fn(w, s, s.presenter, ...)
  end)
end

local function expect_visible(actual, expect, what)
  local want, bad = expect_yes_no(expect)
  if bad then return nil, bad end
  if actual == want then return true end
  return nil, string.format("%s期望 %s，实际 %s", what, expect, actual and "是" or "否")
end

local function expect_text(actual, expect, what)
  if actual == expect then return true end
  return nil, string.format("%s期望「%s」，实际「%s」", what, expect, tostring(actual))
end

local function expect_color(actual, name, what)
  local want = COLORS[name]
  if not want then return nil, "未知颜色: " .. tostring(name) end
  for i = 1, 3 do
    if math.abs(actual[i] - want[i]) > COLOR_TOL then
      return nil, string.format("%s期望 %s (%s)，实际 (%s)", what, name,
        table.concat(want, ","), table.concat(actual, ","))
    end
  end
  return true
end

return { patterns = {
  -- ── 编排动作 ────────────────────────────────────────────────────────────
  { "^资金设为(%d+)$", needs_match(function(w, m, n)
      m.money = tonumber(n)
      return true end) },
  { "^玩家选择待建(%w+)$", needs_session(function(w, s, kind)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      headless.send(s, { action = "select", kind = kind })
      return true end) },
  { "^玩家取消放置$", needs_session(function(w, s)
      headless.send(s, { action = "cancel" })
      return true end) },
  -- 悬停/清除悬停是编排动作（V4：目的地悬停 = 触摸按住/点击）；命中判定归
  -- presenter（V1 最近足迹圆、V2 放置态不悬停），X 名由后续断言验证。
  { "^悬停位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%S+)$", needs_pres(function(w, s, p, x, z)
      p:hover_at(tonumber(x), tonumber(z))
      return true end) },
  { "^清除悬停$", needs_pres(function(w, s, p)
      p:clear_hover()
      return true end) },

  -- ── H1 面板 ────────────────────────────────────────────────────────────
  { "^(%S+)面板是否显示为(%S+)$", needs_pres(function(w, s, p, name, expect)
      local key = PANELS[name]
      if not key then return nil, "未知面板: " .. name end
      return expect_visible(p:panel_visible(key), expect, name .. "面板显示") end) },
  { "^重开按钮是否显示为(%S+)$", needs_pres(function(w, s, p, expect)
      return expect_visible(p:restart_visible(), expect, "重开按钮显示") end) },

  -- ── Playing 面板文本行 ──────────────────────────────────────────────────
  { "^资金行的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:money_text(), expect, "资金行") end) },
  { "^停采提示是否显示为(%S+)$", needs_pres(function(w, s, p, expect)
      return expect_visible(p:pause_visible(), expect, "停采提示显示") end) },
  { "^停采提示的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:pause_text(), expect, "停采提示") end) },
  { "^停采提示的颜色为(%S+)$", needs_pres(function(w, s, p, name)
      return expect_color(p:pause_color(), name, "停采提示颜色") end) },
  { "^矿点行的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:sites_text(), expect, "矿点行") end) },
  { "^波次行的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:wave_text(), expect, "波次行") end) },
  { "^倒计时行的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:countdown_text(), expect, "倒计时行") end) },
  { "^倒计时行的颜色为(%S+)$", needs_pres(function(w, s, p, name)
      return expect_color(p:countdown_color(), name, "倒计时行颜色") end) },
  { "^消息行的文本为空$", needs_pres(function(w, s, p)
      return expect_text(p:message_text(), "", "消息行") end) },
  { "^消息行的文本以(%S+)开头$", needs_pres(function(w, s, p, prefix)
      if p:message_text():sub(1, #prefix) == prefix then return true end
      return nil, string.format("消息行期望以「%s」开头，实际「%s」", prefix, p:message_text()) end) },
  { "^消息行的文本为(.+)$", needs_pres(function(w, s, p, expect)
      return expect_text(p:message_text(), expect, "消息行") end) },

  -- ── H7 建造按钮 ─────────────────────────────────────────────────────────
  { "^(%w+)按钮的文本为(.+)$", needs_pres(function(w, s, p, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      return expect_text(p:button(kind).text, expect, kind .. "按钮") end) },
  { "^(%w+)按钮是否可用为(%S+)$", needs_pres(function(w, s, p, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      local want, bad_want = expect_yes_no(expect)
      if bad_want then return nil, bad_want end
      if p:button(kind).enabled == want then return true end
      return nil, string.format("%s按钮可用期望 %s，实际 %s",
        kind, expect, p:button(kind).enabled and "是" or "否") end) },

  -- ── A 播报与边缘警示 ────────────────────────────────────────────────────
  { "^播报是否显示为(%S+)$", needs_pres(function(w, s, p, expect)
      return expect_visible(p:announce_visible(), expect, "播报显示") end) },
  { "^播报次行的文本为空$", needs_pres(function(w, s, p)
      return expect_text(p:announce_line2(), "", "播报次行") end) },
  { "^播报(首行)的文本为(.+)$", needs_pres(function(w, s, p, _, expect)
      return expect_text(p:announce_line1(), expect, "播报首行") end) },
  { "^播报(次行)的文本为(.+)$", needs_pres(function(w, s, p, _, expect)
      return expect_text(p:announce_line2(), expect, "播报次行") end) },
  { "^(%S+)边缘警示是否显示为(%S+)$", needs_pres(function(w, s, p, edge, expect)
      if not EDGES[edge] then return nil, "未知边缘: " .. edge end
      return expect_visible(p:edge_visible(edge), expect, edge .. "边缘警示显示") end) },
  { "^(%S+)边缘警示的闪烁周期为([%d.]+)秒$", needs_pres(function(w, s, p, edge, expect)
      if not EDGES[edge] then return nil, "未知边缘: " .. edge end
      if math.abs(p:blink_period() - tonumber(expect)) <= EPS then return true end
      return nil, string.format("%s边缘警示闪烁周期期望 %s，实际 %s",
        edge, expect, p:blink_period()) end) },

  -- ── V 悬停 ─────────────────────────────────────────────────────────────
  { "^悬停是否存在为(%S+)$", needs_pres(function(w, s, p, expect)
      return expect_visible(p:hover_exists(), expect, "悬停存在") end) },
  { "^悬停描述(%S+)的文本为(.+)$", needs_pres(function(w, s, p, which, expect)
      local index = LINES[which]
      if not index then return nil, "未知描述行: " .. which end
      local lines = p:hover_lines()
      if not lines then return nil, "当前没有悬停" end
      return expect_text(lines[index], expect, "悬停描述" .. which) end) },

  -- ── F 血条与特效 ────────────────────────────────────────────────────────
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条是否显示为(%S+)$",
    needs_pres(function(w, s, p, x, z, kind, expect)
      local e, bad = find_at(s.match, kind, x, z)
      if not e then return nil, bad end
      return expect_visible(p:healthbar(e).visible, expect, kind .. "血条显示") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条比例为([%d.]+)$",
    needs_pres(function(w, s, p, x, z, kind, expect)
      local e, bad = find_at(s.match, kind, x, z)
      if not e then return nil, bad end
      if math.abs(p:healthbar(e).fill - tonumber(expect)) <= COLOR_TOL then return true end
      return nil, string.format("位于(%s,%s)的%s血条比例期望 %s，实际 %s",
        x, z, kind, expect, p:healthbar(e).fill) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血条颜色为(%S+)$",
    needs_pres(function(w, s, p, x, z, kind, name)
      local e, bad = find_at(s.match, kind, x, z)
      if not e then return nil, bad end
      return expect_color(p:healthbar(e).color, name, kind .. "血条颜色") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)是否红闪为(%S+)$",
    needs_pres(function(w, s, p, x, z, kind, expect)
      local e, bad = find_at(s.match, kind, x, z)
      if not e then return nil, bad end
      return expect_visible(p:flashing(e), expect, kind .. "红闪") end) },
  { "^(%w+)是否碎裂中为(%S+)$", needs_match(function(w, m, kind, expect)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      local crumbling = false
      for _, e in ipairs(m.entities.list) do
        if e.kind == kind and e.state == "crumbling" then crumbling = true end
      end
      return expect_visible(crumbling, expect, kind .. "碎裂中") end) },
  { "^Core是否播放爆炸为(%S+)$", needs_pres(function(w, s, p, expect)
      return expect_visible(p:explosion_active(), expect, "Core 爆炸") end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)的着色为([%d.]+)$",
    needs_pres(function(w, s, p, x, z, kind, expect)
      local e, bad = find_at(s.match, kind, x, z)
      if not e then return nil, bad end
      if math.abs(p:tint(e) - tonumber(expect)) <= EPS then return true end
      return nil, string.format("位于(%s,%s)的%s着色期望 %s，实际 %s",
        x, z, kind, expect, p:tint(e)) end) },
  { "^第(%d+)个敌人是否带揭示标记为(%S+)$", needs_pres(function(w, s, p, n, expect)
      local e = s.match.enemies.list[tonumber(n)]
      if not e then return nil, "还没有第 " .. n .. " 个敌人" end
      return expect_visible(p:enemy_marked(e), expect, "第 " .. n .. " 个敌人揭示标记") end) },
} }
