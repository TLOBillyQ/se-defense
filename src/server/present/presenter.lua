-- src/server/present/presenter.lua — 表现层显示状态（规则真源 docs/gdd/11-hud.md
-- H1–H8、12-announcer.md A1–A4、14-hover.md V1–V4、15-health-fx.md F1–F5、
-- 16-board-input.md I5/I6 目的地文案）。
-- 只读规则层对局（GDD 11 依赖只读），持自己的显示侧状态：播报计时、受击红闪、
-- 悬停目标。每拍由宿主适配层在 match:advance 之后驱动；面板/文本行/按钮等
-- 直接从对局现况算出，不缓存。纯 Lua、无宿主依赖；快照路由归
-- server.adapter.eui，渲染归 client.eui_render。
local world = require("server.game.world")
local waves = require("server.game.waves")

local M = {}

-- H8 颜色常量 + F1 血条颜色（绿/黄/红 GDD 只给名字，此处定为色板）。
M.colors = {
  light_blue = { 0.6, 0.8, 1 },   -- 淡蓝
  amber = { 1, 0.737, 0 },        -- 琥珀
  danger = { 1, 0.3, 0.3 },       -- 危险红
  green = { 0.2, 0.8, 0.2 },      -- 绿（血条 > 70%）
  yellow = { 1, 0.85, 0 },        -- 黄（血条 > 30%）
  red = { 1, 0.25, 0.25 },        -- 红（血条其余）
}

M.announce_seconds = 4  -- A1/A2 播报停留
M.blink_period = 0.5    -- A3 边缘警示闪烁周期
M.flash_seconds = 0.15  -- F2 受击红闪
M.tint_dim = 0.35       -- F4 未通电变暗

-- 方向的英文显示名（HUD/播报用）。
local DIRECTION_EN = { ["东"] = "East", ["南"] = "South", ["西"] = "West", ["北"] = "North" }

-- V3 悬停描述（英文原文，首行为建筑名大写）；矿点单独拼（含剩余量）。
local HOVER_TEXT = {
  Core = { "CORE",
    "Seeds the power grid, all buildings must trace a path to it for receiving power.",
    "Game is over if this building is destroyed." },
  Relay = { "RELAY",
    "Extends the power grid, relaying power to any building inside its coverage.",
    "Buildings lose power when their path to the Core is broken." },
  Radar = { "RADAR",
    "Reveals enemies inside its coverage to turrets.",
    "Turrets cannot fire at enemies that no radar has revealed." },
  Turret = { "TURRET",
    "Fires at enemies inside its coverage that radar has revealed.",
    "Pair with radar coverage — a turret alone sees nothing." },
  Repair = { "REPAIR",
    "Repairs the most damaged building inside its coverage, one at a time.",
    "Repair buildings can mend each other, but never themselves." },
}

local Presenter = {}
Presenter.__index = Presenter

function M.new(match)
  return setmetatable({
    match = match,
    entities_ref = match.entities, -- 重开后登记表换对象，据此复位显示侧状态
    fx = {},                       -- 实体 id → { hits_seen, flash_left }
    hover = nil,                   -- 悬停目标实体（引用）
    announce = { line1 = "", line2 = "", left = 0 },
    prev_assault = false,
    prev_wave = match.wave.number,
  }, Presenter)
end

-- ── 节拍（显示侧状态） ─────────────────────────────────────────────────────

function Presenter:say(line1, line2)
  self.announce = { line1 = line1, line2 = line2, left = M.announce_seconds }
end

function Presenter:tick(dt)
  local m = self.match
  if self.entities_ref ~= m.entities then -- 重开：复位显示侧状态
    self.entities_ref = m.entities
    self.fx = {}
    self.hover = nil
    self.announce = { line1 = "", line2 = "", left = 0 }
    self.prev_assault = false
    self.prev_wave = m.wave.number
  end
  -- A1/A2/A4：只在 Playing 播报；新播报覆盖旧播报并重新计时。
  if m.mode == "Playing" then
    if m.wave.assault and not self.prev_assault then
      self:say("Wave " .. m.wave.number .. " Incoming", "Harvesters Paused")
    elseif m.wave.number ~= self.prev_wave then
      self:say("Wave " .. self.prev_wave .. " Defeated", "")
    end
  end
  self.prev_assault = m.wave.assault
  self.prev_wave = m.wave.number
  if self.announce.left > 0 then self.announce.left = self.announce.left - dt end
  -- F2：受击计数增加即红闪 0.15 秒（规则层只读，按 hits 差分）。
  for _, e in ipairs(m.entities.list) do
    local fx = self.fx[e.id]
    if not fx then -- 首次看到即从 0 起算：建好当拍就挨的打也要闪
      fx = { flash_left = 0, hits_seen = 0 }
      self.fx[e.id] = fx
    end
    if (e.hits or 0) > fx.hits_seen then
      fx.hits_seen = e.hits
      fx.flash_left = M.flash_seconds
    end
    if fx.flash_left > 0 then fx.flash_left = fx.flash_left - dt end
  end
  -- 悬停目标离场（采空/拆除/碎裂完毕）即消失。
  if self.hover and not m.entities:has(self.hover) then self.hover = nil end
end

-- ── H1 面板 ────────────────────────────────────────────────────────────────

function Presenter:panel_visible(panel)
  local mode = self.match.mode
  return (panel == "pregame" and mode == "Pregame")
    or (panel == "playing" and mode == "Playing")
    or (panel == "victory" and mode == "Victory")
    or (panel == "gameover" and mode == "GameOver")
end

-- H1：结束面板含重开按钮。
function Presenter:restart_visible()
  return self.match.mode == "Victory" or self.match.mode == "GameOver"
end

-- ── Playing 面板文本行 ─────────────────────────────────────────────────────

-- H2：速率保留 1 位小数并去尾零。
local function fmt_rate(r)
  return (string.format("%.1f", r):gsub("%.0$", ""))
end

function Presenter:money_text()
  return string.format("$%d (+%s)", self.match.money, fmt_rate(self.match.economy:rate()))
end

function Presenter:pause_visible() return self.match.wave.assault end
function Presenter:pause_text() return "harvesting paused" end
function Presenter:pause_color() return M.colors.amber end

-- H3
function Presenter:sites_text()
  return "Resource Sites: " .. self.match.entities:count_sites()
end

-- H4：首行波次；倒计时行三形态：attacking / <方向> in Ns / in Ns（向上取整）。
function Presenter:wave_text()
  return "Wave " .. self.match.wave.number
end

local function direction_en(match)
  local d = waves.revealed_direction(match)
  return d and DIRECTION_EN[d] or nil
end

function Presenter:countdown_text()
  local m = self.match
  local dir = direction_en(m)
  if m.wave.assault then return (dir or "") .. " attacking" end
  local secs = math.ceil(m.wave.countdown)
  if dir then return string.format("%s in %ds", dir, secs) end
  return string.format("in %ds", secs)
end

-- H5：接近度 c = 1 − 剩余/30；c < 0.5 淡蓝→琥珀，否则琥珀→危险红。
function Presenter:countdown_color()
  local c = 1 - self.match.wave.countdown / world.wave.calm
  local a, b, t
  if c < 0.5 then
    a, b, t = M.colors.light_blue, M.colors.amber, c / 0.5
  else
    a, b, t = M.colors.amber, M.colors.danger, (c - 0.5) / 0.5
  end
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- ── H7 + 16 I5/I6 建造按钮 ─────────────────────────────────────────────────

function Presenter:button(kind)
  local m = self.match
  local price = world.specs[kind].price
  local current = m.placing_kind == kind
  local enabled = m.money >= price and (m.placing_kind == nil or current)
  return { text = current and "Cancel" or string.format("%s - $%d", kind, price),
    enabled = enabled }
end

-- H6 + 16 I6：放置提示 > 悬停描述 > 空。
function Presenter:message_text()
  local m = self.match
  if m.placing_kind then
    return "Placing " .. m.placing_kind .. " — tap its button to cancel"
  end
  local lines = self:hover_lines()
  if lines then return table.concat(lines, "\n") end
  return ""
end

-- ── A 播报与边缘警示 ───────────────────────────────────────────────────────

-- A4：只在 Playing 时播报（结束面板接管屏幕，残留计时立即失效）。
function Presenter:announce_visible()
  return self.match.mode == "Playing" and self.announce.left > 0
end
function Presenter:announce_line1() return self.announce.line1 end
function Presenter:announce_line2() return self.announce.line2 end

-- A3：方向公布后至进攻期开始前，公布方向的一边显示。
function Presenter:edge_visible(edge)
  local m = self.match
  if m.mode ~= "Playing" or m.wave.assault then return false end
  return waves.revealed_direction(m) == edge
end

function Presenter:blink_period() return M.blink_period end

-- ── V 悬停 ─────────────────────────────────────────────────────────────────

-- V1：落点（半径 0）与足迹圆相交的单位中取最近者；V2：放置态中不悬停。
function Presenter:hover_at(x, z)
  if self.match.placing_kind then
    self.hover = nil
    return nil
  end
  self.hover = self.match.entities:pick(x, z)
  return self.hover
end

function Presenter:clear_hover() self.hover = nil end
function Presenter:hover_exists() return self.hover ~= nil end

-- V3：三行描述；矿点第三行为剩余量。
function Presenter:hover_lines()
  local e = self.hover
  if not e then return nil end
  if e.kind == "Site" then
    return { "RESOURCE",
      "Generates $1.25/s while powered. Harvesting pauses during an attack.",
      string.format("%d remaining.", e.remaining) }
  end
  return HOVER_TEXT[e.kind]
end

-- ── F 血条与特效 ───────────────────────────────────────────────────────────

-- F1：血量 < 100% 才显示；比例填充；> 70% 绿、> 30% 黄、否则红。
function Presenter:healthbar(e)
  local cap = e.health and world.specs[e.kind].health
  if not cap or e.health >= cap then return { visible = false, fill = 1, color = M.colors.green } end
  local ratio = e.health / cap
  local color = ratio > 0.7 and M.colors.green or ratio > 0.3 and M.colors.yellow or M.colors.red
  return { visible = true, fill = ratio, color = color }
end

-- F2
function Presenter:flashing(e)
  local fx = self.fx[e.id]
  return fx ~= nil and fx.flash_left > 0
end

-- F3：Core 碎裂期间额外播放爆炸。
function Presenter:explosion_active()
  local core = self.match.entities:find("Core", world.core.x, world.core.z)
  return core ~= nil and core.state == "crumbling"
end

-- F4：未通电建筑变暗 0.35，通电恢复 1（矿点中性不变暗）。
function Presenter:tint(e)
  if e.kind == "Site" then return 1 end
  return self.match.grid:powered(e) and 1 or M.tint_dim
end

-- F5：已揭示的存活敌人带揭示标记。
function Presenter:enemy_marked(e)
  return e.alive and not e.gone and e.revealed
end

-- ── 快照产出（CONTEXT.md「快照」：节点路径 → {text, visible, color, fill}） ──
-- 快照只携状态；布局与样式归客户端 recipe 表。

local BUTTON_KINDS = { "Relay", "Radar", "Turret", "Repair" }
local EDGES = { { key = "east", name = "东" }, { key = "south", name = "南" },
  { key = "west", name = "西" }, { key = "north", name = "北" } }

function Presenter:snapshot()
  local snap = {
    ["hud.panel.pregame"] = { visible = self:panel_visible("pregame") },
    ["hud.panel.playing"] = { visible = self:panel_visible("playing") },
    ["hud.panel.victory"] = { visible = self:panel_visible("victory") },
    ["hud.panel.gameover"] = { visible = self:panel_visible("gameover") },
    ["hud.restart"] = { visible = self:restart_visible() },
    ["hud.money"] = { text = self:money_text() },
    ["hud.pause"] = { visible = self:pause_visible(), text = self:pause_text(),
      color = self:pause_color() },
    ["hud.sites"] = { text = self:sites_text() },
    ["hud.wave"] = { text = self:wave_text() },
    ["hud.countdown"] = { text = self:countdown_text(), color = self:countdown_color() },
    ["hud.message"] = { text = self:message_text() },
    ["announce.line1"] = { visible = self:announce_visible(), text = self:announce_line1() },
    ["announce.line2"] = { visible = self:announce_visible(), text = self:announce_line2() },
  }
  for _, kind in ipairs(BUTTON_KINDS) do
    local b = self:button(kind)
    snap["hud.button." .. kind:lower()] = { text = b.text, enabled = b.enabled }
  end
  for _, edge in ipairs(EDGES) do
    snap["edge." .. edge.key] = { visible = self:edge_visible(edge.name) }
  end
  local hover = self:hover_lines() or { "", "", "" }
  for i = 1, 3 do
    snap["hover.line" .. i] = { visible = self.hover ~= nil, text = hover[i] }
  end
  for _, e in ipairs(self.match.entities.list) do
    if e.kind ~= "Site" then
      local bar = self:healthbar(e)
      snap["unit." .. e.id .. ".healthbar"] = { visible = bar.visible, fill = bar.fill,
        color = bar.color }
      snap["unit." .. e.id .. ".flash"] = { visible = self:flashing(e) }
      snap["unit." .. e.id .. ".tint"] = { fill = self:tint(e) }
    end
  end
  snap["world.core.explosion"] = { visible = self:explosion_active() }
  for _, e in ipairs(self.match.enemies.list) do
    if not e.gone then
      snap["enemy." .. e.id .. ".marker"] = { visible = self:enemy_marked(e) }
    end
  end
  return snap
end

return M
