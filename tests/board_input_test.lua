-- Unit tests for board input semantics (docs/gdd/16-board-input.md I1–I8):
-- button clicks (start/restart/build select/cancel), board clicks gated by
-- mode and board bounds, placing confirm on legal spots only, non-placing
-- clicks drive hover, drag updates the preview point.
local lu = require("luaunit")
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local board_input = require("server.present.board_input")

TestBoardInput = {}

local function new_playing()
  local g = match_flow.new()
  g:start()
  return g, presenter.new(g)
end

-- I5/I4：点 Relay 按钮进入放置态；再点当前类型取消；点合法落点确认。
function TestBoardInput.test_button_select_then_click_board_confirms()
  local g, p = new_playing()
  board_input.click_button(g, p, "Relay")
  lu.assertTrue(g:placing())
  board_input.click_board(g, p, 0, 3)
  lu.assertFalse(g:placing())
  lu.assertTrue(g.entities:present("Relay"))
  lu.assertEquals(g.money, 90)
end

function TestBoardInput.test_current_kind_button_cancels()
  local g, p = new_playing()
  board_input.click_button(g, p, "Relay")
  board_input.click_button(g, p, "Relay")
  lu.assertFalse(g:placing())
  lu.assertEquals(g.money, 100)
end

-- I2：棋盘外点击无效。
function TestBoardInput.test_click_outside_board_ignored()
  local g, p = new_playing()
  board_input.click_button(g, p, "Relay")
  board_input.click_board(g, p, 21, 0)
  board_input.click_board(g, p, 0, -21)
  lu.assertTrue(g:placing())
  lu.assertFalse(g.entities:present("Relay"))
  lu.assertEquals(g.money, 100)
end

-- I3：非放置态点击单位产生悬停，点击空地清除。
function TestBoardInput.test_click_toggles_hover()
  local g, p = new_playing()
  board_input.click_board(g, p, 0, 0)
  lu.assertTrue(p:hover_exists())
  board_input.click_board(g, p, 5, 5)
  lu.assertFalse(p:hover_exists())
end

-- I8：Pregame 棋盘与建筑按钮无效；开始按钮进入 Playing；终局只有重开有效。
function TestBoardInput.test_mode_gating()
  local g = match_flow.new()
  local p = presenter.new(g)
  board_input.click_board(g, p, 0, 0)
  board_input.click_button(g, p, "Relay")
  lu.assertFalse(p:hover_exists())
  lu.assertFalse(g:placing())
  board_input.click_button(g, p, "开始")
  lu.assertEquals(g.mode, "Playing")
  g.entities:kill("Core")
  for _ = 1, 90 do g:advance(1 / 30); p:tick(1 / 30) end
  lu.assertEquals(g.mode, "GameOver")
  board_input.click_board(g, p, 1.71, 0.06)
  lu.assertFalse(p:hover_exists())
  board_input.click_button(g, p, "重开")
  lu.assertEquals(g.mode, "Pregame")
end

-- I4：拖动更新预览；非法落点点击不确认、保持放置态。
function TestBoardInput.test_drag_preview_and_illegal_click_keeps_placing()
  local g, p = new_playing()
  board_input.click_button(g, p, "Turret")
  board_input.drag_board(g, p, 0.9, 0)
  lu.assertEquals({ p.preview.x, p.preview.z }, { 0.9, 0 })
  board_input.click_board(g, p, 0.9, 0)
  lu.assertTrue(g:placing())
  lu.assertEquals(g.money, 100)
  board_input.drag_board(g, p, 0, 2)
  board_input.click_board(g, p, 0, 2)
  lu.assertFalse(g:placing())
  lu.assertTrue(g.entities:present("Turret"))
  lu.assertEquals(g.money, 50)
end
