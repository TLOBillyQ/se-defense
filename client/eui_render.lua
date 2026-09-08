-- 客户端渲染器（哑镜像，#7 决策 3 / #18 决策 5/6）：快照差分 → 真 EUI/SceneGui 节点。
--
-- 职责：
--   - recipe 表：快照节点 path → 真节点配方（EUI 类型、布局、样式、锚定方式）；
--     快照只携状态（text/visible/color/fill），表现知识全在本表（#18 决策 5）。
--   - live-nodes 生命周期：delta 应用、removed 回收、full/reset 整树替换。
--   - 血条世界锚定（#18 决策 4）：*_hp path 解析实体 id → FindFirstChild
--     复制 WorldUnit（Name = 实体 id）→ SceneGui:CreateSceneNodeAttachUnit
--     （官方血条配方：EUIImage 30008 底 + EUILoadingBar 30007，1v1 demo）。
--     单位尚未复制到时进 pending，每帧重试。
--
-- 零 spoke 树（#7-A6）：本模块是纯命令式差分器。

local World = game:GetService("World")
local SceneGui = game:GetService("SceneGui")

local M = {}

-- ── recipe 表 ───────────────────────────────────────────────────────
-- kind:
--   label     屏幕文本（column 分组内按到达序排槽位）
--   banner    居中大字（静态标题在 recipe；visible 由快照驱动）
--   healthbar 世界锚定血条（path 解析实体 id）
--   button    EUIButton（#21 放置面板 panel/*）：text→ButtonText、color→文字色、
--             visible；点击经 deps.on_click(path) 回流（渲染器不知意图语义）；
--             panel/restart（#28）居中放在终局 banner 下方
--   none      只跟踪状态（容器/双路由形状节点，无屏幕表现）

local WARNING_TEXT = {
  north = "! NORTH !", east = "! EAST !", south = "! SOUTH !", west = "! WEST !",
}

local BUILD_SLOT = { relay = 0, radar = 1, turret = 2, repair = 3 }

local function recipe_for(path)
  local build_key = path:match("^panel/build/(%a+)$")
  if build_key then
    return { kind = "button", slot = BUILD_SLOT[build_key] or 4, font = 30 }
  end
  if path == "panel/start" then
    return { kind = "button", center_y = 0.45, font = 40, size = { 320, 88 }, color = { 255, 255, 255 } }
  end
  if path == "panel/cancel" then
    return { kind = "button", slot = 5, font = 30, color = { 255, 120, 120 } }
  end
  if path == "panel/restart" then
    return { kind = "button", center_y = 0.58, font = 40, size = { 460, 96 }, color = { 255, 255, 255 } }
  end
  if path:match("_hp$") then
    return { kind = "healthbar" }
  end
  if path:match("^hud/") then
    return { kind = "label", column = "hud", font = 30 }
  end
  if path == "announce/onscreen" then
    return { kind = "label", column = "announce", font = 44, color = { 255, 220, 60 } }
  end
  local warning = path:match("^announce/warning/(%a+)$")
  if warning then
    return { kind = "label", column = "warning_" .. warning, font = 34,
      color = { 255, 60, 60 }, static_text = WARNING_TEXT[warning] }
  end
  if path == "sidebar/pregame" then
    return { kind = "banner", text = "BASE DEFENCE", color = { 255, 255, 255 }, font = 60, y = 0.30 }
  end
  if path == "sidebar/gameover" then
    return { kind = "banner", text = "GAME OVER", color = { 255, 60, 60 }, font = 72, y = 0.40 }
  end
  if path == "sidebar/victory" then
    return { kind = "banner", text = "VICTORY", color = { 80, 255, 120 }, font = 72, y = 0.40 }
  end
  if path:match("^sidebar/gameplay/") then
    return { kind = "label", column = "side", font = 26 }
  end
  -- sidebar/gameplay（面板容器）、*_beam、board/* 等：无双屏表现
  return { kind = "none" }
end

-- ── 渲染器 ──────────────────────────────────────────────────────────

local R = {}
R.__index = R

-- log: function(fmt, ...)；get_res: function() → {X=, Y=} 设备分辨率；
-- on_click: function(path) 按钮点击回流。
function M.new(deps)
  return setmetatable({
    log = deps.log or function() end,
    get_res = deps.get_res,
    on_click = deps.on_click or function() end,
    live = {},     -- path → { recipe=, label=/scene_node=/bar=, slot= }
    state = {},    -- path → 最新快照状态（祖先可见性合成用）
    generation = 0, -- 快照 gen（服务端 reset_scene 代数）；血条寻单位名用（#28）
    pending_hp = {}, -- path → true（单位未复制到，逐帧重试）
    column_slots = {}, -- column → 已分配槽位数
  }, R)
end

local function to_color(c, fallback)
  if type(c) == "table" then
    return Color.New(
      math.floor((c.r or 1) * 255 + 0.5),
      math.floor((c.g or 1) * 255 + 0.5),
      math.floor((c.b or 1) * 255 + 0.5),
      math.floor((c.a or 1) * 255 + 0.5))
  end
  return Color.New(fallback[1], fallback[2], fallback[3], 255)
end

-- 祖先可见性合成：sidebar/gameplay/money 的父面板 sidebar/gameplay 隐藏时，
-- 子节点业务侧不逐个置 hidden，渲染器按 path 前缀合成（recipe 表语义的一部分）。
function R:_effective_visible(path)
  local p = path
  while true do
    local st = self.state[p]
    if st and st.visible == false then return false end
    local i = p:match("^.*()/")
    if not i then return true end
    p = p:sub(1, i - 1)
  end
end

function R:_alloc_slot(column)
  local n = (self.column_slots[column] or 0)
  self.column_slots[column] = n + 1
  return n
end

function R:_free_slot(column)
  self.column_slots[column] = math.max(0, (self.column_slots[column] or 1) - 1)
end

-- 列布局（Position 为节点中心，像素坐标，原点在屏幕左上；#10 烟测同款用法）
function R:_slot_position(column, slot)
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  if column == "hud" then
    return Vector2.New(260, 40 + slot * 42), Vector2.New(480, 36)
  elseif column == "side" then
    return Vector2.New(res.X - 300, 60 + slot * 40), Vector2.New(560, 34)
  elseif column == "announce" then
    return Vector2.New(res.X / 2, res.Y * 0.22), Vector2.New(1100, 110)
  elseif column == "warning_north" then
    return Vector2.New(res.X / 2, 28), Vector2.New(600, 44)
  elseif column == "warning_south" then
    return Vector2.New(res.X / 2, res.Y - 28), Vector2.New(600, 44)
  elseif column == "warning_east" then
    return Vector2.New(res.X - 160, res.Y / 2), Vector2.New(280, 44)
  elseif column == "warning_west" then
    return Vector2.New(160, res.Y / 2), Vector2.New(280, 44)
  end
  return Vector2.New(res.X / 2, res.Y / 2), Vector2.New(600, 40)
end

function R:_create_label(path, recipe)
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  local root = self.root
  if not root then return nil end
  local slot = self:_alloc_slot(recipe.column or "hud")
  local pos, size = self:_slot_position(recipe.column or "hud", slot)
  local color = recipe.color or { 255, 255, 255 }
  local ok, label = pcall(function()
    return World:CreateUnit("EUITextLabel", {
      Parent = root,
      Name = "r_" .. path:gsub("[^%w]", "_"),
      Position = pos,
      Size = size,
      FontSize = recipe.font or 28,
      Text = recipe.static_text or "",
      TextColor = Color.New(color[1], color[2], color[3], 255),
      OutlineEnabled = true,
      OutlineColor = Color.New(0, 0, 0, 255),
      OutlineWidth = 3,
    })
  end)
  if not ok then
    self.log("创建 label 失败 %s: %s", path, tostring(label))
    self:_free_slot(recipe.column or "hud")
    return nil
  end
  return { label = label, slot = slot, column = recipe.column or "hud" }
end

function R:_create_banner(path, recipe)
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  if not self.root then return nil end
  local color = recipe.color or { 255, 255, 255 }
  local ok, label = pcall(function()
    return World:CreateUnit("EUITextLabel", {
      Parent = self.root,
      Name = "r_" .. path:gsub("[^%w]", "_"),
      Position = Vector2.New(res.X / 2, res.Y * (recipe.y or 0.4)),
      Size = Vector2.New(1200, 120),
      FontSize = recipe.font or 64,
      Text = recipe.text or "",
      TextColor = Color.New(color[1], color[2], color[3], 255),
      OutlineEnabled = true,
      OutlineColor = Color.New(0, 0, 0, 255),
      OutlineWidth = 4,
    })
  end)
  if not ok then
    self.log("创建 banner 失败 %s: %s", path, tostring(label))
    return nil
  end
  return { label = label }
end

-- 放置面板按钮：右侧竖排，围绕屏幕垂直中线布置（与 EUI 画布 y 轴朝向无关），
-- slot 0..3 四建筑、slot 5 取消（隔一格）。SwallowTouch + 高 ZOrder，不漏给捕获层。
-- recipe.center_y：横向居中、纵向按比例（终局 Restart）；否则右侧竖排槽位。
function R:_button_layout(recipe)
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  local x, y, w, h
  if recipe.center_y then
    x, y = res.X / 2, res.Y * recipe.center_y
    w, h = (recipe.size or {})[1] or 460, (recipe.size or {})[2] or 96
  else
    x, y = res.X - 300, res.Y / 2 + ((recipe.slot or 0) - 2.5) * 90
    w, h = 380, 72
  end
  return Vector2.New(x, y), Vector2.New(w, h), x, y
end

function R:_create_button(path, recipe)
  if not self.root then return nil end
  local pos, size, px, py = self:_button_layout(recipe)
  local color = recipe.color or { 255, 255, 255 }
  local ok, btn = pcall(function()
    local b = World:CreateUnit("EUIButton", {
      Parent = self.root,
      Name = "r_" .. path:gsub("[^%w]", "_"),
      Position = pos,
      Size = size,
      ButtonText = "",
      ButtonTextFontSize = recipe.font or 30,
      ButtonTextColor = Color.New(color[1], color[2], color[3], 255),
      TouchEnabled = true,
      SwallowTouchEnabled = true,
      LocalZOrder = 50,
    })
    b.OnClicked:Connect(function()
      self.log("按钮点击 %s", path)
      self.on_click(path)
    end)
    return b
  end)
  if not ok then
    self.log("创建 button 失败 %s: %s", path, tostring(btn))
    return nil
  end
  return { button = btn, pos = { x = px, y = py } }
end

-- 血条：path 形如 enemy_3_hp / building_1_hp / resource_2_hp（#18 决策 4）。
local function parse_entity_id(path)
  local id = path:match("^enemy_(%d+)_hp$")
    or path:match("^building_(%d+)_hp$")
    or path:match("^resource_(%d+)_hp$")
  return id
end

-- 单位名约定与服务端 entity.unit_name 一致：首局裸 id，重开后 "<id>g<gen>"（#28）。
function R:_unit_name(id)
  if (self.generation or 0) == 0 then return id end
  return id .. "g" .. tostring(self.generation)
end

function R:_try_create_healthbar(path)
  local id = parse_entity_id(path)
  if not id then return "none" end
  local unit = World:FindFirstChild(self:_unit_name(id), true)
  if not unit then return nil end -- 单位未复制到，进 pending
  local ok, controls = pcall(function()
    local node = SceneGui:CreateSceneNodeAttachUnit(unit, "", Vector3.New(0, 2.5, 0), true)
    local bg = World:CreateUnit("EUIImage", {
      Parent = node,
      Name = "hp_bg",
      Image = "official://image/30008",
      Position = Vector2.New(0, 0),
      Size = Vector2.New(120, 12),
    })
    local bar = World:CreateUnit("EUILoadingBar", {
      Parent = node,
      Name = "hp_bar",
      Image = "official://image/30007",
      Position = Vector2.New(0, 0),
      Size = Vector2.New(120, 12),
      Percent = 100,
      Direction = 0,
    })
    return { scene_node = node, bg = bg, bar = bar }
  end)
  if not ok then
    self.log("创建血条失败 %s: %s", path, tostring(controls))
    return "none" -- 不重试（API 级失败），降级为无表现
  end
  return controls
end

function R:_create(path, st)
  local recipe = recipe_for(path)
  local live = { recipe = recipe }
  if recipe.kind == "label" then
    local c = self:_create_label(path, recipe)
    if not c then return nil end
    live.label = c.label
    live.slot = c.slot
    live.column = c.column
  elseif recipe.kind == "banner" then
    local c = self:_create_banner(path, recipe)
    if not c then return nil end
    live.label = c.label
  elseif recipe.kind == "button" then
    local c = self:_create_button(path, recipe)
    if not c then return nil end
    live.button = c.button
    live.pos = c.pos
  elseif recipe.kind == "healthbar" then
    local controls = self:_try_create_healthbar(path)
    if controls == nil then
      self.pending_hp[path] = true
      live.deferred = true
    elseif controls ~= "none" then
      live.scene_node = controls.scene_node
      live.bar = controls.bar
      live.bg = controls.bg
    else
      live.recipe = { kind = "none" }
    end
  end
  return live
end

function R:_apply_state(path, st)
  local live = self.live[path]
  if not live then return end
  local visible = self:_effective_visible(path)
  if live.label then
    pcall(function()
      if st.text ~= nil and live.recipe.static_text == nil and live.recipe.kind ~= "banner" then
        live.label.Text = st.text
      end
      if st.color ~= nil and live.recipe.color == nil then
        live.label.TextColor = to_color(st.color, { 255, 255, 255 })
      end
      live.label.Visible = visible
    end)
  end
  if live.button then
    pcall(function()
      if st.text ~= nil then live.button.ButtonText = st.text end
      if st.color ~= nil and live.recipe.color == nil then
        live.button.ButtonTextColor = to_color(st.color, { 255, 255, 255 })
      end
      live.button.Visible = visible
    end)
  end
  if live.scene_node then
    pcall(function()
      live.scene_node.Visible = visible
      if st.fill ~= nil and live.bar then
        live.bar.Percent = math.floor(st.fill * 100 + 0.5)
      end
      if st.color ~= nil and live.bar then
        live.bar.Color = to_color(st.color, { 0, 255, 0 })
      end
    end)
  end
end

function R:_destroy(path)
  local live = self.live[path]
  if not live then return end
  self.live[path] = nil
  self.pending_hp[path] = nil
  self.state[path] = nil
  if live.slot and live.column then self:_free_slot(live.column) end
  pcall(function() if live.label then live.label:Destroy() end end)
  pcall(function() if live.button then live.button:Destroy() end end)
  pcall(function() if live.scene_node then live.scene_node:Destroy() end end)
end

-- ── 快照入口 ────────────────────────────────────────────────────────

local function merge_state(old, delta)
  local st = old or {}
  for k, v in pairs(delta) do
    st[k] = v
  end
  return st
end

-- 增量应用（removed 为 path 数组）。
function R:apply(nodes, removed)
  if removed then
    for _, path in ipairs(removed) do
      self:_destroy(path)
    end
  end
  if nodes then
    for path, delta in pairs(nodes) do
      self.state[path] = merge_state(self.state[path], delta)
      if not self.live[path] then
        self.live[path] = self:_create(path, self.state[path])
      end
    end
    -- 第二遍统一刷可见性/字段（祖先可能同帧到达）
    for path, _ in pairs(nodes) do
      self:_apply_state(path, self.state[path])
      -- 祖先可见性变化会牵连后代：朴素起见，每帧 tick 里全量刷可见性
    end
  end
end

-- 全量替换（full/reset）。
function R:replace_all(nodes)
  local paths = {}
  for path in pairs(self.live) do paths[#paths + 1] = path end
  for _, path in ipairs(paths) do self:_destroy(path) end
  self.state = {}
  self:apply(nodes or {})
end

function R:_apply_visible(path)
  local live = self.live[path]
  if not live then return end
  local visible = self:_effective_visible(path)
  pcall(function()
    if live.label then live.label.Visible = visible end
    if live.button then live.button.Visible = visible end
    if live.scene_node then live.scene_node.Visible = visible end
  end)
end

-- 每帧：pending 血条重试 + 全量可见性刷新（祖先合成）。
function R:tick(_dt)
  for path in pairs(self.pending_hp) do
    local live = self.live[path]
    if live and live.deferred then
      local controls = self:_try_create_healthbar(path)
      if controls == nil then
        -- 继续等
      elseif controls ~= "none" then
        live.scene_node = controls.scene_node
        live.bar = controls.bar
        live.bg = controls.bg
        live.deferred = nil
        self.pending_hp[path] = nil
        self:_apply_state(path, self.state[path])
      else
        live.deferred = nil
        live.recipe = { kind = "none" }
        self.pending_hp[path] = nil
      end
    else
      self.pending_hp[path] = nil
    end
  end
  for path, live in pairs(self.live) do
    if live.label or live.button or live.scene_node then
      self:_apply_visible(path)
    end
  end
end

-- 按钮在 EUI 画布上的中心坐标（集成测试用 SimulateTap 打真触摸链路）。
function R:node_position(path)
  local live = self.live[path]
  if live and live.pos then return live.pos.x, live.pos.y end
  return nil
end

-- 由 client/main.lua 在 PlayerGui 就绪后注入根节点。
function R:set_root(root)
  self.root = root
end

-- 每条快照消息携带 gen；变化即说明服务端已 reset_scene（随后必有 reset 全量）。
function R:set_generation(gen)
  if type(gen) == "number" then self.generation = gen end
end

-- GM/验证用统计。
function R:stats()
  local labels, bars, none, buttons = 0, 0, 0, 0
  for _, l in pairs(self.live) do
    if l.label then labels = labels + 1 end
    if l.button then buttons = buttons + 1 end
    if l.scene_node then bars = bars + 1 end
    if l.recipe and l.recipe.kind == "none" then none = none + 1 end
  end
  local pend = 0
  for _ in pairs(self.pending_hp) do pend = pend + 1 end
  local state_n = 0
  for _ in pairs(self.state) do state_n = state_n + 1 end
  return { state = state_n, labels = labels, bars = bars, none = none, pending = pend, buttons = buttons }
end

return M
