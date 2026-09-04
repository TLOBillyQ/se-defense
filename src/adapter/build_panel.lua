-- 建筑放置面板（服务端半，#21）：四个放置按钮 + 取消按钮的快照节点。
--
-- 业务侧没有按钮（sidebar.lua 明示 BuildItem 按钮已由鼠标放置流取代），
-- 所以按钮归适配层：本模块用 host.eui 节点把「可放置项 + 造价 + 余额可否 +
-- 当前选中」投影成快照状态，客户端 recipe 表把 panel/* 渲成 EUIButton；
-- 点击回流为 place/cancel 意图（server/main.lua 收）。快照零表现知识（#18）。
--
-- 节点：
--   panel/build/<key>  text="Turret $100"  color: 选中=黄 / 可买=白 / 买不起=灰
--                      visible: Playing 时可见
--   panel/cancel       visible: placing ~= nil
--
-- 每帧 update() 读 .now() 投影一次；set_* 自带去重，无脏不发。

local ORDER = { "relay", "radar", "turret", "repair" }

local COLOR_AFFORD = { r = 1, g = 1, b = 1, a = 1 }
local COLOR_POOR = { r = 0.45, g = 0.45, b = 0.45, a = 1 }
local COLOR_SELECTED = { r = 1, g = 0.9, b = 0.2, a = 1 }

local M = {}
M.ORDER = ORDER

-- host: 适配层 host 表；root: GameRootFull 实例（spawn 后，building_specs 已就位）。
function M.create(host, root)
  local panel = { host = host, root = root, buttons = {} }
  for _, key in ipairs(ORDER) do
    local spec = root.building_specs and root.building_specs[key]
    if spec then
      local node = host.eui.node("panel/build/" .. key)
      node:set_visible(false)
      -- spec 上没有 display_name（在 spec.building 里），首字母大写即可
      node:set_text(string.format("%s $%d", key:gsub("^%l", string.upper), spec.cost or 0))
      panel.buttons[#panel.buttons + 1] = { key = key, spec = spec, node = node }
    end
  end
  panel.cancel = host.eui.node("panel/cancel")
  panel.cancel:set_visible(false)
  panel.cancel:set_text("Cancel")
  return panel
end

function M.update(panel)
  local gs = panel.root.game_state
  local bi = panel.root.board_interactions
  if not gs or not bi then return end
  local playing = gs.mode:now() == "Playing"
  local money = gs.money:now() or 0
  local placing = bi.placing:now()
  for _, b in ipairs(panel.buttons) do
    b.node:set_visible(playing)
    local c
    if placing == b.spec then
      c = COLOR_SELECTED
    elseif money >= (b.spec.cost or 0) then
      c = COLOR_AFFORD
    else
      c = COLOR_POOR
    end
    local cur = b.node.color
    if cur.r ~= c.r or cur.g ~= c.g or cur.b ~= c.b then
      b.node:set_color(c)
    end
  end
  panel.cancel:set_visible(playing and placing ~= nil)
end

-- 放置意图入口（RemoteEvent / GM 共用）：只在 Playing 且 key 合法时置位。
-- 返回 true 表示已置位。
function M.place(panel, key)
  local spec = panel.root.building_specs and panel.root.building_specs[key]
  if not spec then return false, "unknown" end
  if panel.root.game_state.mode:now() ~= "Playing" then return false, "not_playing" end
  panel.root.board_interactions.placing:set(spec)
  return true
end

return M
