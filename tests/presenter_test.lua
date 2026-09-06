-- Unit tests for the presentation layer (docs/gdd/11-hud.md H1–H8,
-- 12-announcer.md A1–A4, 14-hover.md V1–V4, 15-health-fx.md F1–F5):
-- panels per mode, HUD lines (money/sites/wave/countdown/message), countdown
-- color ramp, build buttons, announcer timing, edge warnings, hover text and
-- hit rules, healthbar/flash/tint/explosion/reveal-marker display state.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local waves = require("server.game.waves")
local enemies = require("server.game.enemies")
local presenter = require("server.present.presenter")

TestPresenter = {}

local function advance_seconds(g, p, n)
  for _ = 1, math.floor(n * 30 + 0.5) do
    g:advance(1 / 30)
    p:tick(1 / 30)
  end
end

local function new_presenter()
  local g = match_flow.new()
  g:start()
  return g, presenter.new(g)
end

-- H1：同一时刻只显示对局阶段对应的面板；结束面板含重开。
function TestPresenter.test_panels_follow_mode()
  local g = match_flow.new()
  local p = presenter.new(g)
  lu.assertTrue(p:panel_visible("pregame"))
  lu.assertFalse(p:panel_visible("playing"))
  lu.assertFalse(p:restart_visible())
  g:start()
  lu.assertTrue(p:panel_visible("playing"))
  lu.assertFalse(p:panel_visible("pregame"))
  g.entities:deplete_sites(27)
  g:advance(1)
  lu.assertTrue(p:panel_visible("victory"))
  lu.assertTrue(p:restart_visible())
  g:restart()
  lu.assertTrue(p:panel_visible("pregame"))
end

-- H2：资金行 $100 (+2.5)，进攻期附加琥珀色停采提示。
function TestPresenter.test_money_line_and_pause_hint()
  local g, p = new_presenter()
  local site = g.entities:find("Site", -1.99, -0.10)
  site.remaining = 0
  g.entities:remove(site)
  advance_seconds(g, p, 0.1)
  lu.assertEquals(p:money_text(), "$100 (+2.5)")
  lu.assertFalse(p:pause_visible())
  g.wave.assault = true
  lu.assertTrue(p:pause_visible())
  lu.assertEquals(p:pause_text(), "harvesting paused")
  lu.assertEquals(p:pause_color(), presenter.colors.amber)
end

-- H3：矿点行。
function TestPresenter.test_sites_line()
  local g, p = new_presenter()
  lu.assertEquals(p:sites_text(), "Resource Sites: 27")
  g.entities:deplete_sites(5)
  lu.assertEquals(p:sites_text(), "Resource Sites: 22")
end

-- H4：波次行与倒计时行三种形态（随机源固定最大值 → North）。
function TestPresenter.test_wave_and_countdown_lines()
  local g, p = new_presenter()
  g.rng01 = function() return 1 end
  waves.reroll_direction(g)
  lu.assertEquals(p:wave_text(), "Wave 1")
  advance_seconds(g, p, 10.5)
  lu.assertEquals(p:countdown_text(), "in 20s")
  advance_seconds(g, p, 16)
  lu.assertEquals(p:countdown_text(), "North in 4s")
  advance_seconds(g, p, 5.5)
  lu.assertEquals(p:countdown_text(), "North attacking")
end

-- H5：倒计时颜色 30/15/0 秒恰为淡蓝/琥珀/危险红。
local function assert_color(actual, expect)
  for i = 1, 3 do lu.assertAlmostEquals(actual[i], expect[i], 1e-9) end
end

function TestPresenter.test_countdown_color_ramp()
  local g, p = new_presenter()
  assert_color(p:countdown_color(), presenter.colors.light_blue)
  advance_seconds(g, p, 15)
  assert_color(p:countdown_color(), presenter.colors.amber)
  advance_seconds(g, p, 17)
  assert_color(p:countdown_color(), presenter.colors.danger)
end

-- H7 + 16 I5/I6：按钮文案/价格/禁用；放置态只有当前类型可用且文案为 Cancel。
function TestPresenter.test_build_buttons()
  local g, p = new_presenter()
  lu.assertEquals(p:button("Relay").text, "Relay - $10")
  lu.assertEquals(p:button("Repair").text, "Repair - $100")
  g.money = 99
  lu.assertFalse(p:button("Repair").enabled)
  lu.assertTrue(p:button("Relay").enabled)
  g:select("Relay")
  lu.assertEquals(p:button("Relay").text, "Cancel")
  lu.assertTrue(p:button("Relay").enabled)
  lu.assertFalse(p:button("Radar").enabled)
end

-- H6：消息行 = 放置提示 > 悬停描述 > 空。
function TestPresenter.test_message_line_priority()
  local g, p = new_presenter()
  g.entities:add_building("Relay", 0, 3)
  advance_seconds(g, p, 0.1)
  lu.assertEquals(p:message_text(), "")
  g:select("Relay")
  lu.assertEquals(p:message_text(), "Placing Relay — tap its button to cancel")
  g:cancel()
  p:hover_at(0, 3)
  lu.assertTrue(p:message_text():find("^RELAY") ~= nil)
end

-- A1：进攻期开始播报 Wave N Incoming / Harvesters Paused，4 秒后消失。
function TestPresenter.test_incoming_announcement_lasts_four_seconds()
  local g, p = new_presenter()
  advance_seconds(g, p, 30.5)
  lu.assertTrue(p:announce_visible())
  lu.assertEquals(p:announce_line1(), "Wave 1 Incoming")
  lu.assertEquals(p:announce_line2(), "Harvesters Paused")
  advance_seconds(g, p, 3)
  lu.assertTrue(p:announce_visible())
  advance_seconds(g, p, 1)
  lu.assertFalse(p:announce_visible())
end

-- A2：全灭播报 Wave N Defeated（无次行），覆盖旧播报并重新计时。
function TestPresenter.test_defeated_announcement_overrides()
  local g, p = new_presenter()
  advance_seconds(g, p, 32)
  for _, e in ipairs(g.enemies.list) do enemies.kill(e) end
  advance_seconds(g, p, 0.1)
  lu.assertEquals(p:announce_line1(), "Wave 1 Defeated")
  lu.assertEquals(p:announce_line2(), "")
  advance_seconds(g, p, 3.5)
  lu.assertTrue(p:announce_visible())
  advance_seconds(g, p, 1)
  lu.assertFalse(p:announce_visible())
end

-- A3：公布方向的一边闪烁（周期 0.5 秒），进攻开始后消失。
function TestPresenter.test_edge_warning()
  local g, p = new_presenter()
  g.rng01 = function() return 1 end
  waves.reroll_direction(g)
  advance_seconds(g, p, 24)
  lu.assertFalse(p:edge_visible("北"))
  advance_seconds(g, p, 2)
  lu.assertTrue(p:edge_visible("北"))
  lu.assertFalse(p:edge_visible("东"))
  lu.assertEquals(p:blink_period(), 0.5)
  advance_seconds(g, p, 5)
  lu.assertFalse(p:edge_visible("北"))
end

-- V1/V3：悬停命中取足迹圆内最近者；建筑三行英文描述。
function TestPresenter.test_hover_building_description()
  local g, p = new_presenter()
  g.entities:add_building("Relay", 0, 3)
  p:hover_at(0.2, 3)
  lu.assertTrue(p:hover_exists())
  lu.assertEquals(p:hover_lines(),
    { "RELAY",
      "Extends the power grid, relaying power to any building inside its coverage.",
      "Buildings lose power when their path to the Core is broken." })
  p:clear_hover()
  lu.assertFalse(p:hover_exists())
end

-- V3：矿点悬停显示剩余量并随采集变化；采空后悬停消失。
function TestPresenter.test_hover_site_remaining_updates_and_vanishes()
  local g, p = new_presenter()
  p:hover_at(1.71, 0.06)
  lu.assertEquals(p:hover_lines()[1], "RESOURCE")
  lu.assertEquals(p:hover_lines()[3], "300 remaining.")
  advance_seconds(g, p, 0.8)
  lu.assertEquals(p:hover_lines()[3], "299 remaining.")
  local site = g.entities:find("Site", 1.71, 0.06)
  site.remaining = 0
  g.entities:remove(site)
  advance_seconds(g, p, 0.1)
  lu.assertFalse(p:hover_exists())
end

-- V2：放置态中不产生悬停。
function TestPresenter.test_no_hover_while_placing()
  local g, p = new_presenter()
  g.entities:add_building("Relay", 0, 3)
  g:select("Radar")
  p:hover_at(0, 3)
  lu.assertFalse(p:hover_exists())
end

-- F1：满血无血条；比例与颜色阈值（>70% 绿、>30% 黄、否则红）。
function TestPresenter.test_healthbar()
  local g, p = new_presenter()
  local t = g.entities:add_building("Turret", 0, 3)
  lu.assertFalse(p:healthbar(t).visible)
  g.entities:hurt(t, 1)
  local bar = p:healthbar(t)
  lu.assertTrue(bar.visible)
  lu.assertAlmostEquals(bar.fill, 0.8, 1e-9)
  lu.assertEquals(bar.color, presenter.colors.green)
  g.entities:hurt(t, 1)
  lu.assertEquals(p:healthbar(t).color, presenter.colors.yellow)
  g.entities:hurt(t, 2)
  lu.assertEquals(p:healthbar(t).color, presenter.colors.red)
end

-- F2：受击红闪 0.15 秒。
function TestPresenter.test_hit_flash()
  local g, p = new_presenter()
  local t = g.entities:add_building("Turret", 0, 3)
  advance_seconds(g, p, 0.1)
  g.entities:hurt(t, 0.5)
  advance_seconds(g, p, 0.1)
  lu.assertTrue(p:flashing(t))
  advance_seconds(g, p, 0.2)
  lu.assertFalse(p:flashing(t))
end

-- F3：Core 碎裂期间播放爆炸。
function TestPresenter.test_core_explosion_while_crumbling()
  local g, p = new_presenter()
  lu.assertFalse(p:explosion_active())
  g.entities:kill("Core")
  advance_seconds(g, p, 0.1)
  lu.assertTrue(p:explosion_active())
  advance_seconds(g, p, 3)
  lu.assertFalse(p:explosion_active())
end

-- F4：未通电建筑着色 0.35，通电恢复 1。
function TestPresenter.test_tint_follows_power()
  local g, p = new_presenter()
  local r = g.entities:add_building("Relay", 0, 6)
  advance_seconds(g, p, 1)
  lu.assertEquals(p:tint(r), 0.35)
  g.entities:add_building("Relay", 0, 3.5)
  advance_seconds(g, p, 1)
  lu.assertEquals(p:tint(r), 1)
end

-- F5：已揭示敌人带揭示标记，未揭示不带。
function TestPresenter.test_enemy_reveal_marker()
  local g, p = new_presenter()
  g.entities:add_building("Radar", 0, 3.5)
  advance_seconds(g, p, 1)
  enemies.spawn(g, { x = 0, z = 11.6, tier = 1, heading = { x = 0, z = -1 } })
  enemies.spawn(g, { x = 0, z = 12.2, tier = 1, heading = { x = 0, z = -1 } })
  advance_seconds(g, p, 0.1)
  lu.assertTrue(p:enemy_marked(g.enemies.list[1]))
  lu.assertFalse(p:enemy_marked(g.enemies.list[2]))
end
