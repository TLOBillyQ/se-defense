-- tests/properties/input_prop.lua — server.present.board_input 的性质测试。
-- 覆盖维度：守卫/负需求（非 Playing 或棋盘外的棋盘点击与拖动完全无副作用）、
-- 宽输入范围（随机坐标、随机阶段）。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local board_input = require("server.present.board_input")
local world = require("server.game.world")

prop.seed(41)

-- I-P1：非 Playing 或棋盘外，click_board / drag_board 不改变任何状态。
prop.check("I-P1 棋盘输入守卫无副作用", 150, function()
  local g = match_flow.new()
  local pres = presenter.new(g)
  g.mode = prop.pick({ "Pregame", "Playing", "Victory", "GameOver" })
  local b = world.board
  local inside = prop.int(1, 2) == 1
  local x = inside and prop.number(b.min, b.max)
    or (prop.int(1, 2) == 1 and prop.number(b.max + 0.01, b.max + 5)
      or prop.number(b.min - 5, b.min - 0.01))
  local z = prop.number(b.min - 5, b.max + 5)
  local before = { mode = g.mode, money = g.money, n = #g.entities.list,
    hover = pres.hover, preview = pres.preview, placing = g.placing_kind }
  local guarded = g.mode ~= "Playing" or x < b.min or x > b.max
    or z < b.min or z > b.max
  board_input.click_board(g, pres, x, z)
  board_input.drag_board(g, pres, x, z)
  if guarded then
    if g.mode ~= before.mode or g.money ~= before.money
      or #g.entities.list ~= before.n or pres.hover ~= before.hover
      or pres.preview ~= before.preview or g.placing_kind ~= before.placing then
      return nil, string.format("守卫内状态被改（mode=%s, x=%.2f, z=%.2f）", before.mode, x, z)
    end
  else
    -- 受理路径：Playing 且棋盘内；非放置态点空地即清除悬停或命中悬停
    if not g.placing_kind and pres.hover == nil and before.hover ~= nil then
      -- 允许：空地清除
      return true
    end
    if g.mode ~= "Playing" then return nil, "受理路径阶段漂移" end
  end
  return true
end)
