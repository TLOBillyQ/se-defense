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

local ring_geometry = require("client.ring_geometry")
local unit_name = require("common.unit_name")

local M = {}

-- 字体随 EUI 画布高度缩放（以 1080 高度为基准，上限 1.6 倍）：不同分辨率下
-- 文字都保持可读，不再因画布分辨率偏大而显得过小。
local function ui_font(res, base)
  local Y = res.Y or 1080
  local fy = math.min(1.6, Y / 1080)
  return math.max(24, math.floor(base * fy + 0.5))
end

-- ── recipe 表 ───────────────────────────────────────────────────────
-- kind:
--   label     屏幕文本（column 分组内按到达序排槽位）
--   banner    居中大字（静态标题在 recipe；visible 由快照驱动）
--   healthbar 世界锚定血条（path 解析实体 id）
--   button    EUIButton（#21 放置面板 panel/*）：text→ButtonText、color→文字色、
--             visible；点击经 deps.on_click(path) 回流（渲染器不知意图语义）；
--             panel/restart（#28）居中放在终局 banner 下方
--   ring      世界锚定圆环（ADR 0006）：快照只带圆心与半径，几何在这里按
--             client/ring_geometry 的换算生成；白模不吃颜色，故为单色
--   none      只跟踪状态（容器 / 就地渲染的 line 节点，无屏幕表现）

local WARNING_TEXT = {
  north = "! NORTH !", east = "! EAST !", south = "! SOUTH !", west = "! WEST !",
}

local BUILD_SLOT = { relay = 0, radar = 1, turret = 2, repair = 3 }

local function recipe_for(path, st)
  -- 形状先于路径：带 shape 的快照节点一律是世界锚定圆环，路径千变万化
  -- （board/hover_coverage_7、board/placement_footprint …），按状态判更稳。
  if st and type(st.shape) == "table" and st.shape.kind == "ring" then
    return { kind = "ring" }
  end
  local build_key = path:match("^panel/build/(%a+)$")
  if build_key then
    return { kind = "button", slot = BUILD_SLOT[build_key] or 4, font = 32 }
  end
  if path == "panel/start" then
    return { kind = "button", center_y = 0.45, font = 46, size = { 320, 88 }, color = { 255, 255, 255 } }
  end
  if path == "panel/cancel" then
    return { kind = "button", slot = 5, font = 32, color = { 255, 120, 120 } }
  end
  if path == "panel/restart" then
    return { kind = "button", center_y = 0.58, font = 46, size = { 460, 96 }, color = { 255, 255, 255 } }
  end
  if path:match("_hp$") then
    return { kind = "healthbar" }
  end
  -- 实时操作日志：左下角独立列（先于通用 ^hud/ 匹配）。
  if path:match("^hud/log/") then
    return { kind = "label", column = "log", font = 34 }
  end
  if path:match("^hud/") then
    return { kind = "label", column = "hud", font = 38 }
  end
  if path == "announce/onscreen" then
    return { kind = "label", column = "announce", font = 48, color = { 255, 220, 60 } }
  end
  local warning = path:match("^announce/warning/(%a+)$")
  if warning then
    return { kind = "label", column = "warning_" .. warning, font = 40,
      color = { 255, 60, 60 }, static_text = WARNING_TEXT[warning] }
  end
  if path == "sidebar/pregame" then
    return { kind = "banner", text = "BASE DEFENCE", color = { 255, 255, 255 }, font = 70, y = 0.30 }
  end
  if path == "sidebar/gameover" then
    return { kind = "banner", text = "GAME OVER", color = { 255, 60, 60 }, font = 86, y = 0.40 }
  end
  if path == "sidebar/victory" then
    return { kind = "banner", text = "VICTORY", color = { 80, 255, 120 }, font = 86, y = 0.40 }
  end
  -- 放置提示行：横贯屏幕下缘的醒目大行（先于通用 ^sidebar/gameplay/）。
  if path == "sidebar/gameplay/message" then
    return { kind = "label", column = "message", font = 32 }
  end
  if path:match("^sidebar/gameplay/") then
    return { kind = "label", column = "side", font = 32 }
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
    ring_failed = {}, -- path → true（CreateUnit 失败，不再重试也不再刷日志）
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

-- 列布局（Position 为节点中心，像素坐标，原点在屏幕左上；#10 烟测同款用法）。
-- 尺寸/坐标随 EUI 画布分辨率成比例：不同设备不再出现"文字太小、面板过窄"。
function R:_slot_position(column, slot)
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  local X, Y = res.X or 1920, res.Y or 1080
  if column == "hud" then
    return Vector2.New(X * 0.135, Y * (0.025 + slot * 0.06)), Vector2.New(X * 0.28, Y * 0.045)
  elseif column == "side" then
    -- 右上：右缘留 1.5% 边距，行高随画布高度缩放
    local w = X * 0.30
    return Vector2.New(X - w / 2 - X * 0.015, Y * (0.03 + slot * 0.055)), Vector2.New(w, Y * 0.045)
  elseif column == "message" then
    -- 居中放置提示：右缘止于按钮列左缘之前，避免与右侧建造按钮重叠
    return Vector2.New(X / 2, Y * 0.54), Vector2.New(X * 0.44, Y * 0.06)
  elseif column == "log" then
    -- 左下角日志：slot 0 最新、位于最下方，向上堆叠
    local w = X * 0.32
    return Vector2.New(X * 0.02 + w / 2, Y * (0.94 - slot * 0.042)), Vector2.New(w, Y * 0.042)
  elseif column == "announce" then
    return Vector2.New(X / 2, Y * 0.19), Vector2.New(X * 0.58, Y * 0.115)
  elseif column == "warning_north" then
    return Vector2.New(X / 2, Y * 0.03), Vector2.New(X * 0.38, Y * 0.055)
  elseif column == "warning_south" then
    return Vector2.New(X / 2, Y * 0.97), Vector2.New(X * 0.38, Y * 0.055)
  elseif column == "warning_east" then
    return Vector2.New(X * 0.96, Y / 2), Vector2.New(X * 0.20, Y * 0.055)
  elseif column == "warning_west" then
    return Vector2.New(X * 0.04, Y / 2), Vector2.New(X * 0.20, Y * 0.055)
  end
  return Vector2.New(X / 2, Y / 2), Vector2.New(X * 0.40, Y * 0.05)
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
      FontSize = ui_font(res, recipe.font or 28),
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
      Size = Vector2.New(res.X * 0.62, res.Y * 0.14),
      FontSize = ui_font(res, recipe.font or 64),
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
  local X, Y = res.X or 1920, res.Y or 1080
  local x, y, w, h
  if recipe.center_y then
    x, y = X / 2, Y * recipe.center_y
    local bw, bh = (recipe.size or {})[1] or 460, (recipe.size or {})[2] or 96
    w, h = bw * (X / 1920), bh * (Y / 1080)
  else
    -- 右侧竖排：宽高随画布缩放，右缘留 0.8% 边距
    w, h = X * 0.26, Y * 0.07
    x = X - w / 2 - X * 0.008
    y = Y * (0.5 + ((recipe.slot or 0) - 2.5) * 0.075)
  end
  return Vector2.New(x, y), Vector2.New(w, h), x, y
end

function R:_create_button(path, recipe)
  if not self.root then return nil end
  local res = self.get_res and self.get_res() or { X = 1920, Y = 1080 }
  local pos, size, px, py = self:_button_layout(recipe)
  local color = recipe.color or { 255, 255, 255 }
  local ok, btn = pcall(function()
    local b = World:CreateUnit("EUIButton", {
      Parent = self.root,
      Name = "r_" .. path:gsub("[^%w]", "_"),
      Position = pos,
      Size = size,
      ButtonText = "",
      ButtonTextFontSize = ui_font(res, recipe.font or 30),
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

-- 环的位姿：建单位时与之后跟随落点时都要算，抽一份免得两处漂移。
-- 半径非正时无位姿（调用方据此不建/不更新）。
local function ring_pose(sh)
  local scale = ring_geometry.scale_for_radius(sh.radius)
  if not scale then return nil end
  return Vector3.New(scale, ring_geometry.RING_FLATTEN, scale),
    Vector3.New(sh.center.x, ring_geometry.RING_Y + sh.center.y, sh.center.z)
end

-- 圆环：快照给逻辑半径，这里换算成白模 Scale（换算与实测出处见 client/ring_geometry）。
function R:_create_ring(path, st)
  if self.ring_failed[path] then return nil end
  local scale, pos = ring_pose(st.shape)
  if not scale then return nil end
  local ok, unit = pcall(function()
    return World:CreateUnit("WorldUnit", {
      Name = "r_" .. path:gsub("[^%w]", "_"),
      RenderMeshId = ring_geometry.RING_MESH,
      BodyType = Enums.BodyType.Static,
      CanCollide = false,
      Scale = scale,
      Position = pos,
    })
  end)
  if not ok then
    self.ring_failed[path] = true
    self.log("创建 ring 失败 %s: %s", path, tostring(unit))
    return nil
  end
  return unit
end

-- 血条：path 形如 enemy_3_hp / building_1_hp / resource_2_hp（#18 决策 4）。
local function parse_entity_id(path)
  local id = path:match("^enemy_(%d+)_hp$")
    or path:match("^building_(%d+)_hp$")
    or path:match("^resource_(%d+)_hp$")
  return id
end

function R:_try_create_healthbar(path)
  local id = parse_entity_id(path)
  if not id then return "none" end
  local unit = World:FindFirstChild(unit_name.format(id, self.generation), true)
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
  local recipe = recipe_for(path, st)
  local live = { recipe = recipe }
  if recipe.kind == "ring" then
    -- 建不出来也保留 ring 配方：降级成 none 会让之后每条 shape 增量都判成
    -- 「配方要升级」而 teardown→重建，预览圆逐帧重试 CreateUnit 并刷日志。
    -- 半径还非正时先空着，等下一条 shape 增量到 _apply_state 里补建。
    live.unit = self:_create_ring(path, st)
  elseif recipe.kind == "label" then
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
  if live.recipe.kind == "ring" and not live.unit then
    live.unit = self:_create_ring(path, st)
  end
  if live.unit then
    local sh = st.shape
    pcall(function()
      if type(sh) == "table" then
        local scale, pos = ring_pose(sh)
        if scale then
          live.unit.Scale = scale
          live.unit.Position = pos
        end
      end
      live.unit.ModelVisible = visible
    end)
  end
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

-- 拆掉真节点但保留快照状态：形状迟到时要用原状态重建（见 apply）。
function R:_teardown(path)
  local live = self.live[path]
  if not live then return end
  self.live[path] = nil
  self.pending_hp[path] = nil
  if live.slot and live.column then self:_free_slot(live.column) end
  pcall(function() if live.label then live.label:Destroy() end end)
  pcall(function() if live.button then live.button:Destroy() end end)
  pcall(function() if live.scene_node then live.scene_node:Destroy() end end)
  pcall(function() if live.unit then live.unit:Destroy() end end)
end

function R:_destroy(path)
  self:_teardown(path)
  self.state[path] = nil
  -- 节点真没了才清失败记号：同名节点重建（reset_scene 后）值得再试一次。
  self.ring_failed[path] = nil
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
      local live = self.live[path]
      -- 节点先建、set_ring 后到时首帧会按 none 配方落地，收到 shape 再升级为 ring。
      if live and delta.shape ~= nil and live.recipe.kind ~= "ring" then
        self:_teardown(path)
        live = nil
      end
      if not live then
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
    if live.unit then live.unit.ModelVisible = visible end
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
    if live.label or live.button or live.scene_node or live.unit then
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
  local labels, bars, none, buttons, rings = 0, 0, 0, 0, 0
  for _, l in pairs(self.live) do
    if l.label then labels = labels + 1 end
    if l.button then buttons = buttons + 1 end
    if l.scene_node then bars = bars + 1 end
    if l.unit then rings = rings + 1 end
    if l.recipe and l.recipe.kind == "none" then none = none + 1 end
  end
  local pend = 0
  for _ in pairs(self.pending_hp) do pend = pend + 1 end
  local state_n = 0
  for _ in pairs(self.state) do state_n = state_n + 1 end
  return { state = state_n, labels = labels, bars = bars, none = none, pending = pend,
    buttons = buttons, rings = rings }
end

return M
