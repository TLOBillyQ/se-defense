-- 建筑放置面板（服务端半，#21）：四个放置按钮 + 取消按钮的快照节点。
--
-- 业务侧没有按钮（sidebar.lua 明示 BuildItem 按钮已由鼠标放置流取代），
-- 所以按钮归 UI 层：本模块用 host.eui 节点把「可放置项 + 造价 + 余额可否 +
-- 当前选中」投影成快照状态，客户端 recipe 表把 panel/* 渲成 EUIButton；
-- 点击回流为 place/cancel 意图（server/main.lua 收）。快照零表现知识（#18）。
--
-- 节点：
--   panel/build/<key>  text="Turret $100"  color: 选中=黄 / 可买=白 / 买不起=灰
--                      visible: Playing 时可见
--   panel/cancel       visible: placing ~= nil
--   panel/restart      visible: 终局（GameOver / Victory）；点击回流 restart 意图（#28）
--
-- 每帧 update() 读 .now() 投影一次；set_* 自带去重，无脏不发。

local ORDER = { "relay", "radar", "turret", "repair" }

local COLOR_AFFORD = { r = 1, g = 1, b = 1, a = 1 }
local COLOR_POOR = { r = 0.45, g = 0.45, b = 0.45, a = 1 }
local COLOR_SELECTED = { r = 1, g = 0.9, b = 0.2, a = 1 }

local M = {}
M.ORDER = ORDER

-- 建筑显示名：spec 无 display_name 时用 key 首字母大写（与 sidebar_gameplay 同口径）。
local function spec_label(spec)
  return spec.display_name
    or (spec.key and (spec.key:gsub("^%l", string.upper)) or "建筑")
end

-- host: 宿主接缝表；root: GameRootFull 实例（spawn 后，building_specs 已就位）。
function M.create(host, root, op_log)
  local panel = { host = host, root = root, op_log = op_log, buttons = {} }
  for _, key in ipairs(ORDER) do
    local spec = root.building_specs and root.building_specs[key]
    if spec then
      local node = host.eui.node("panel/build/" .. key)
      node:set_visible(false)
      -- H7：文案 `<建筑名> - $<价格>`（spec 上没有 display_name，首字母大写即可）。
      local label = key:gsub("^%l", string.upper)
      local base_text = string.format("%s - $%d", label, spec.cost or 0)
      node:set_text(base_text)
      panel.buttons[#panel.buttons + 1] = {
        key = key, spec = spec, node = node, base_text = base_text,
      }
    end
  end
  panel.start = host.eui.node("panel/start")
  panel.start:set_visible(false)
  panel.start:set_text("Start")
  panel.cancel = host.eui.node("panel/cancel")
  panel.cancel:set_visible(false)
  panel.cancel:set_text("Cancel")
  panel.restart = host.eui.node("panel/restart")
  panel.restart:set_visible(false)
  panel.restart:set_text("Restart")
  return panel
end

-- 终局判定：Restart 按钮只在 GameOver / Victory 可见、意图只在此时受理。
function M.restart_allowed(panel)
  local mode = panel.root.game_state.mode:now()
  return mode == "GameOver" or mode == "Victory"
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
    local enabled
    local text = b.base_text
    if placing == b.spec then
      -- H7：放置态中只有当前类型按钮可用，文案变为 Cancel。
      c = COLOR_SELECTED
      enabled = true
      text = "Cancel"
    elseif placing ~= nil then
      c = COLOR_POOR
      enabled = false
    elseif money >= (b.spec.cost or 0) then
      c = COLOR_AFFORD
      enabled = true
    else
      c = COLOR_POOR
      enabled = false
    end
    b.node:set_enabled(playing and enabled)
    if b.node.text ~= text then
      b.node:set_text(text)
    end
    local cur = b.node.color
    if cur.r ~= c.r or cur.g ~= c.g or cur.b ~= c.b then
      b.node:set_color(c)
    end
  end
  panel.cancel:set_visible(playing and placing ~= nil)
  panel.start:set_visible(gs.mode:now() == "Pregame")
  panel.restart:set_visible(M.restart_allowed(panel))
end

-- 放置意图入口（RemoteEvent / GM 共用）：Playing 中、key 合法且资金可负担
-- （GDD 04 R1 资金不足不可选）时置位；放置态中再点当前类型按钮 = 取消
-- （GDD 16 I4）。返回 true 表示已置位。
function M.place(panel, key)
  local spec = panel.root.building_specs and panel.root.building_specs[key]
  local oplog = panel.op_log
  if not spec then
    if oplog then oplog:push("error", ("未知建筑 %s"):format(tostring(key))) end
    return false, "unknown"
  end
  if panel.root.game_state.mode:now() ~= "Playing" then
    if oplog then oplog:push("warn", "非对局中，无法放置") end
    return false, "not_playing"
  end
  if panel.root.board_interactions.placing:now() == spec then
    panel.root.board_interactions.placing:set(nil)
    if oplog then oplog:push("info", ("已取消放置 %s"):format(spec_label(spec))) end
    return false, "cancelled"
  end
  if (panel.root.game_state.money:now() or 0) < (spec.cost or 0) then
    if oplog then oplog:push("warn", ("余额不足：%s 需 $%d"):format(spec_label(spec), spec.cost or 0)) end
    return false, "unaffordable"
  end
  panel.root.board_interactions.placing:set(spec)
  if oplog then oplog:push("info", ("选择放置 %s（$%d）"):format(spec_label(spec), spec.cost or 0)) end
  return true
end

return M
