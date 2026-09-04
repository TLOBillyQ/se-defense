-- host.eui 域真实现（服务端半）：快照出口 + 形状双路由。
--
-- 依据 #18 决议：
--   - 混合快照协议：text/fill/color/visible 四字段浅比较，节点级增量（dirty），
--     握手/序号缺口时全量重同步；本模块只维护状态与脏集，seq 与发送归
--     server/main.lua（每 tick 派发结束 dirty 即发，#18 决策 2）。
--   - 双路由（决策 3）：set_ring/set_line 不进快照，在服务端就地渲为
--     EffectUnit（#9 D2），随 Unit 复制对客户端可见；节点销毁时一并回收。
--   - 契约补录：业务直读 host.eui.nodes 内部表做存在性检查
--     （link_display/coverage_display/render_util/sidebar），本模块复刻
--     mock 注册表语义：nodes[path] → 节点，destroy 后移除。
--
-- 节点字段与 e1dadeee eui_mock 对齐：text / visible / color{r,g,b,a} / fill，
-- 业务侧也直读 node.visible（announcer 闪烁）。

local World = game:GetService("World")

local eui = {
  nodes = {},
  order = {},
  generation = 0, -- reset_scene 代数；客户端 reset 消息携带以便丢弃过期快照
}

-- 脏集：path → { field=true }；新节点记 full（发全字段）；销毁记 removed。
local dirty = {}
local new_nodes = {}
local removed = {}
local removed_set = {}

local function copy_color(c)
  if type(c) == "table" then
    return { r = c.r or c[1] or 1, g = c.g or c[2] or 1, b = c.b or c[3] or 1, a = c.a or c[4] or 1 }
  end
  return { r = 1, g = 1, b = 1, a = 1 }
end

local function copy_vec3(v)
  if type(v) == "table" then
    return { x = v.x or v[1] or 0, y = v.y or v[2] or 0, z = v.z or v[3] or 0 }
  end
  return { x = 0, y = 0, z = 0 }
end

local function mark_dirty(node, field)
  if removed_set[node.path] then return end
  local d = dirty[node.path]
  if not d then
    d = {}
    dirty[node.path] = d
  end
  d[field] = true
end

-- ── 形状双路由：ring/line → 服务端 EffectUnit（#9 D2）────────────────
-- 垂直切片内放置/雷达/炮塔不激活，本路径是合约完整性的保底实现；
-- 特效原生半径未经探针，RING_NATIVE_RADIUS 为可调常量。

local RING_EFFECT = "official://effect/6079"   -- 地面圆形充能环（#4 事实 §3.2）
local LINE_EFFECT = "official://effect/4506"   -- 连线-激光射线
local RING_NATIVE_RADIUS = 2                   -- 假设：Scale=1 时特效半径≈2（探针待定）

local shape_warned = {}

-- 上色（#21 真机实测）：EffectUnit 的 DiffuseColor/ColorStrength/BlendFactor 无论
-- 哪端写、写什么值，引擎都记一条 "Internal Error" 告警且**肉眼不变色**（环恒为
-- 特效原色黄）；WorldUnit 的 ModelColor1 能显色（#10）。故需要随状态变色的环
--（放置 footprint 红/绿、悬停高亮）改渲为扁圆柱 WorldUnit 圆盘；其余覆盖圈保持
-- 特效环原色，不写颜色属性。
local DISC_MESH = "official://mesh/59273"        -- 圆柱（#4 事实）
local DISC_NATIVE_RADIUS = 0.5                    -- 假设：Scale=1 时圆柱半径≈0.5（待标定）
local DISC_HEIGHT = 0.05
local DISC_PATHS = {                              -- 需变色的环 → 圆盘
  ["board/placement_footprint"] = true,
  ["board/hover_ring"] = true,
}

local function fx_name(path)
  return "fx_" .. path:gsub("[^%w]", "_")
end

local function to_color(c)
  return Color.New(
    math.floor((c.r or 1) * 255 + 0.5),
    math.floor((c.g or 1) * 255 + 0.5),
    math.floor((c.b or 1) * 255 + 0.5), 255)
end

local function disc_scale(radius)
  local s = radius / DISC_NATIVE_RADIUS
  return Vector3.New(s, DISC_HEIGHT, s)
end

local function spawn_disc(node, center, radius)
  local ok, unit = pcall(function()
    local u = World:CreateUnit("WorldUnit", {
      Name = fx_name(node.path),
      RenderMeshId = DISC_MESH,
      Scale = disc_scale(radius),
      Position = Vector3.New(center.x, 0.03 + center.y, center.z),
    })
    u.ModelColor1 = to_color(node.color)
    return u
  end)
  if not ok then
    if not shape_warned.disc then
      shape_warned.disc = true
      print("[bd][eui] 圆盘 WorldUnit 创建失败: " .. tostring(unit))
    end
    return nil
  end
  return unit
end

local function spawn_ring(node, center, radius)
  if DISC_PATHS[node.path] then return spawn_disc(node, center, radius), true end
  local s = radius / RING_NATIVE_RADIUS
  local ok, unit = pcall(function()
    return World:CreateUnit("EffectUnit", {
      Name = fx_name(node.path),
      EffectId = RING_EFFECT,
      Duration = -1,
      Scale = Vector3.New(s, s, s),
      Position = Vector3.New(center.x, 0.05 + center.y, center.z),
    })
  end)
  if not ok then
    if not shape_warned.ring then
      shape_warned.ring = true
      print("[bd][eui] ring EffectUnit 创建失败: " .. tostring(unit))
    end
    return nil
  end
  return unit, false
end

-- 连线：两端隐形锚点 WorldUnit + 连线特效 Attach（#10 探针 P4 已验证 Attach）。
local function spawn_line(node, from, to)
  local ok, err = pcall(function()
    local function anchor(p, tag)
      return World:CreateUnit("WorldUnit", {
        Name = "fx_anchor_" .. tag .. "_" .. node.path:gsub("[^%w]", "_"),
        RenderMeshId = "official://mesh/59268",
        BodyType = Enums.BodyType.Static,
        CanCollide = false,
        Scale = Vector3.New(0.05, 0.05, 0.05),
        Position = Vector3.New(p.x, 0.1 + p.y, p.z),
      })
    end
    local a = anchor(from, "a")
    local b = anchor(to, "b")
    pcall(function() a.ModelAlpha = 0 end)
    pcall(function() b.ModelAlpha = 0 end)
    local fx = World:CreateUnit("EffectUnit", {
      Name = "fx_" .. node.path:gsub("[^%w]", "_"),
      EffectId = LINE_EFFECT,
      Duration = -1,
      Position = Vector3.New(from.x, 0.1 + from.y, from.z),
    })
    fx:StartposAttach(a, "", Vector3.New(0, 0, 0))
    fx:EndposAttach(b, "", Vector3.New(0, 0, 0))
    return { a = a, b = b, fx = fx }
  end)
  if not ok then
    if not shape_warned.line then
      shape_warned.line = true
      print("[bd][eui] line 单位创建失败: " .. tostring(err))
    end
    return nil
  end
  return err
end

local function destroy_shape(node)
  local sh = node._shape
  if not sh then return end
  node._shape = nil
  pcall(function() if sh.unit then sh.unit:Destroy() end end)
  if sh.line then
    pcall(function() sh.line.a:Destroy() end)
    pcall(function() sh.line.b:Destroy() end)
    pcall(function() sh.line.fx:Destroy() end)
  end
end

-- ── 节点 ────────────────────────────────────────────────────────────

function eui.node(path)
  assert(not eui.nodes[path], "节点已存在: " .. path)
  local n = {
    path = path,
    text = "",
    visible = true,
    color = { r = 1, g = 1, b = 1, a = 1 },
    fill = 1,
  }

  function n:set_text(t)
    if self.text == t then return end
    self.text = t
    mark_dirty(self, "text")
  end

  function n:set_fill(f)
    if self.fill == f then return end
    self.fill = f
    mark_dirty(self, "fill")
  end

  function n:set_visible(v)
    v = v and true or false
    if self.visible == v then return end
    self.visible = v
    mark_dirty(self, "visible")
    -- 形状节点（ring/line）的显隐就地作用于 EffectUnit（不进快照）
    local sh = self._shape
    if sh then
      if sh.unit then
        pcall(function()
          if sh.disc then sh.unit.ModelVisible = v else sh.unit.Visible = v end
        end)
      end
      if sh.line then
        pcall(function() sh.line.fx.Visible = v end)
        pcall(function() sh.line.a.ModelVisible = v end)
        pcall(function() sh.line.b.ModelVisible = v end)
      end
    end
  end

  function n:set_color(c)
    self.color = copy_color(c)
    mark_dirty(self, "color")
    local sh = self._shape
    if sh and sh.disc and sh.unit then
      pcall(function() sh.unit.ModelColor1 = to_color(self.color) end)
    end
  end

  -- 覆盖圈：就地 EffectUnit / 圆盘 WorldUnit，不进快照（#18 决策 3）。同形状重复写入就地更新。
  function n:set_ring(center, radius)
    self._shape_only = true
    local c = copy_vec3(center)
    local sh = self._shape
    if sh and sh.kind == "ring" and sh.unit then
      pcall(function()
        if sh.disc then
          sh.unit.Position = Vector3.New(c.x, 0.03 + c.y, c.z)
          sh.unit.Scale = disc_scale(radius)
        else
          local s = radius / RING_NATIVE_RADIUS
          sh.unit.Position = Vector3.New(c.x, 0.05 + c.y, c.z)
          sh.unit.Scale = Vector3.New(s, s, s)
        end
      end)
      sh.center = c
      sh.radius = radius
      return
    end
    destroy_shape(self)
    local unit, disc = spawn_ring(self, c, radius)
    self._shape = { kind = "ring", center = c, radius = radius, unit = unit, disc = disc }
  end

  -- 连线：电力线 / 炮塔光束 / 维修光束。同形状重复写入只挪锚点。
  function n:set_line(from, to)
    self._shape_only = true
    local f, t = copy_vec3(from), copy_vec3(to)
    local sh = self._shape
    if sh and sh.kind == "line" and sh.line then
      pcall(function()
        sh.line.a.Position = Vector3.New(f.x, 0.1 + f.y, f.z)
        sh.line.b.Position = Vector3.New(t.x, 0.1 + t.y, t.z)
      end)
      return
    end
    destroy_shape(self)
    self._shape = { kind = "line", line = spawn_line(self, f, t) }
  end

  eui.nodes[path] = n
  eui.order[#eui.order + 1] = path
  dirty[path] = { text = true, visible = true, color = true, fill = true }
  new_nodes[path] = true
  return n
end

function eui.destroy(node)
  if not node or not node.path then return end
  if eui.nodes[node.path] ~= node then return end
  destroy_shape(node)
  eui.nodes[node.path] = nil
  for i, p in ipairs(eui.order) do
    if p == node.path then
      table.remove(eui.order, i)
      break
    end
  end
  dirty[node.path] = nil
  new_nodes[node.path] = nil
  if not removed_set[node.path] then
    removed[#removed + 1] = node.path
    removed_set[node.path] = true
  end
end

-- ── 快照出口（server/main.lua 驱动）──────────────────────────────────

local function snapshot_state(n, fields)
  local out = {}
  for field in pairs(fields) do
    if field == "color" then
      out.color = copy_color(n.color)
    else
      out[field] = n[field]
    end
  end
  return out
end

-- 取走本帧增量；无脏返回 nil。形状节点（ring/line）双路由不跨网络，跳过。
function eui.drain()
  local nodes
  for path, fields in pairs(dirty) do
    local n = eui.nodes[path]
    if n and not removed_set[path] and not n._shape_only then
      nodes = nodes or {}
      nodes[path] = snapshot_state(n, fields)
    end
  end
  local rem
  if #removed > 0 then
    rem = removed
  end
  dirty = {}
  new_nodes = {}
  removed = {}
  removed_set = {}
  if not nodes and not rem then return nil end
  return { nodes = nodes, removed = rem }
end

-- 全量快照（client_ready 握手 / resync 缺口重同步共用）。
function eui.full()
  local nodes = {}
  for _, path in ipairs(eui.order) do
    local n = eui.nodes[path]
    if n and not n._shape_only then
      nodes[path] = snapshot_state(n, { text = true, visible = true, color = true, fill = true })
    end
  end
  return nodes
end

-- reset_scene 用：清空注册表 + 形状单位 + 脏集，代数 +1。
function eui.reset()
  for _, path in ipairs(eui.order) do
    local n = eui.nodes[path]
    if n then destroy_shape(n) end
  end
  eui.nodes = {}
  eui.order = {}
  dirty = {}
  new_nodes = {}
  removed = {}
  removed_set = {}
  eui.generation = eui.generation + 1
end

return eui
