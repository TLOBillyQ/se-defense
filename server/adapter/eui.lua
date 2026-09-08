-- host.eui 域真实现（服务端半）：快照出口 + 形状双路由。
--
-- 依据 #18 决议：
--   - 混合快照协议：text/fill/color/visible 四字段浅比较，节点级增量（dirty），
--     握手/序号缺口时全量重同步；本模块只维护状态与脏集，seq 与发送归
--     server/main.lua（每 tick 派发结束 dirty 即发，#18 决策 2）。
--   - 形状路由（决策 3，#42 修订）：set_ring 进快照（只传圆心与半径，客户端按
--     配方生成几何，形状因此也能 resync）；set_line 仍在服务端就地渲为
--     EffectUnit（#9 D2），随 Unit 复制对客户端可见，节点销毁时一并回收。
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

-- ── 形状：ring 进快照，line 就地渲 EffectUnit（ADR 0003 经 #42 修订）─────
--
-- ring 的几何知识（网格、缩放常数）落在 client/ring_geometry.lua，由客户端
-- 渲染器消费；本模块只把圆心与半径放进快照。
--
-- 特效不吃颜色（#21 实测），所以「颜色语义」只能靠选不同特效表达（#23）：
--   电力连线 / 炮塔光束 / 维修光束 → 4506 连线-激光射线（黄色光束）
-- 表按 path 前缀匹配，首个命中生效；无命中走 LINE_DEFAULT。
local LINE_EFFECTS = {
  { prefix = "board/power_links", id = "official://effect/4506", y = 0.3 },
  { prefix = "board/hover_link",  id = "official://effect/4506", y = 0.3 },
  { prefix = "turret_",           id = "official://effect/4506", y = 0.8 },
  { prefix = "repair_",           id = "official://effect/4506", y = 0.8 },
}
local LINE_DEFAULT = { id = "official://effect/4506", y = 0.3 }

local function line_style_for(path)
  for _, e in ipairs(LINE_EFFECTS) do
    if path:sub(1, #e.prefix) == e.prefix then return e end
  end
  return LINE_DEFAULT
end

local shape_warned = {}

-- 连线：两端隐形锚点 WorldUnit + 连线特效 Attach（#10 探针 P4 已验证 Attach）。
-- 光束/连线离地高度按种类（电力线贴地 0.3、建筑间光束 0.8 = 建筑半高）。
-- 业务在 set_line 之前可能已 set_visible(false)（repair/turret 光束节点建后即隐），
-- 生成时必须继承节点显隐，否则光束会在首帧闪现。
local function spawn_line(node, from, to)
  local style = line_style_for(node.path)
  local ok, err = pcall(function()
    local function anchor(p, tag)
      return World:CreateUnit("WorldUnit", {
        Name = "fx_anchor_" .. tag .. "_" .. node.path:gsub("[^%w]", "_"),
        RenderMeshId = "official://mesh/59268",
        BodyType = Enums.BodyType.Static,
        CanCollide = false,
        Scale = Vector3.New(0.05, 0.05, 0.05),
        Position = Vector3.New(p.x, style.y + p.y, p.z),
      })
    end
    local a = anchor(from, "a")
    local b = anchor(to, "b")
    pcall(function() a.ModelAlpha = 0 end)
    pcall(function() b.ModelAlpha = 0 end)
    local fx = World:CreateUnit("EffectUnit", {
      Name = "fx_" .. node.path:gsub("[^%w]", "_"),
      EffectId = style.id,
      Duration = -1,
      Position = Vector3.New(from.x, style.y + from.y, from.z),
    })
    fx:StartposAttach(a, "", Vector3.New(0, 0, 0))
    fx:EndposAttach(b, "", Vector3.New(0, 0, 0))
    if not node.visible then
      fx.Visible = false
      a.ModelVisible = false
      b.ModelVisible = false
    end
    return { a = a, b = b, fx = fx, y = style.y }
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
    enabled = true, -- 按钮可用态（GDD 11 H7：资金不足/放置态禁用）
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

  function n:set_enabled(v)
    v = v and true or false
    if self.enabled == v then return end
    self.enabled = v
    mark_dirty(self, "enabled")
  end

  function n:set_visible(v)
    v = v and true or false
    if self.visible == v then return end
    self.visible = v
    mark_dirty(self, "visible")
    -- line 不进快照，显隐就地作用于 EffectUnit；ring 的显隐随快照走。
    local sh = self._shape
    if sh and sh.line then
      pcall(function() sh.line.fx.Visible = v end)
      pcall(function() sh.line.a.ModelVisible = v end)
      pcall(function() sh.line.b.ModelVisible = v end)
    end
  end

  function n:set_color(c)
    self.color = copy_color(c)
    mark_dirty(self, "color")
  end

  -- 覆盖圈：只把圆心与半径放进快照，几何由客户端按配方生成（ADR 0006）。
  -- 同值重复写入不脏，避免 footprint 每帧跟随鼠标时刷出无意义增量。
  function n:set_ring(center, radius)
    local c = copy_vec3(center)
    local sh = self.shape
    if sh and sh.kind == "ring" and sh.radius == radius
      and sh.center.x == c.x and sh.center.y == c.y and sh.center.z == c.z then
      return
    end
    self.shape = { kind = "ring", center = c, radius = radius }
    mark_dirty(self, "shape")
  end

  -- 连线：电力线 / 炮塔光束 / 维修光束。同形状重复写入只挪锚点。
  function n:set_line(from, to)
    self._shape_only = true
    local f, t = copy_vec3(from), copy_vec3(to)
    local sh = self._shape
    if sh and sh.kind == "line" and sh.line then
      local y = sh.line.y or 0.3
      pcall(function()
        sh.line.a.Position = Vector3.New(f.x, y + f.y, f.z)
        sh.line.b.Position = Vector3.New(t.x, y + t.y, t.z)
      end)
      sh.from = f
      sh.to = t
      return
    end
    destroy_shape(self)
    self._shape = { kind = "line", line = spawn_line(self, f, t), from = f, to = t }
  end

  eui.nodes[path] = n
  eui.order[#eui.order + 1] = path
  dirty[path] = { text = true, visible = true, color = true, fill = true, enabled = true }
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
    elseif field == "shape" then
      local sh = n.shape
      out.shape = sh and { kind = sh.kind, center = copy_vec3(sh.center), radius = sh.radius } or false
    else
      out[field] = n[field]
    end
  end
  return out
end

-- 取走本帧增量；无脏返回 nil。line 节点就地渲染、不跨网络，跳过；ring 走快照。
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
      local fields = { text = true, visible = true, color = true, fill = true, enabled = true }
      if n.shape then fields.shape = true end
      nodes[path] = snapshot_state(n, fields)
    end
  end
  return nodes
end

-- 形状清单（GM dump_shapes / 集成测试）：ring 读快照状态，line 读就地单位。
function eui.shapes()
  local out = {}
  for _, path in ipairs(eui.order) do
    local n = eui.nodes[path]
    if n and n.shape then
      out[#out + 1] = {
        path = path, kind = n.shape.kind, route = "snapshot",
        visible = n.visible, radius = n.shape.radius, center = n.shape.center,
      }
    end
    local sh = n and n._shape
    if sh then
      local u = sh.line and sh.line.fx
      out[#out + 1] = {
        path = path, kind = sh.kind,
        effect = u and u.EffectId or "nil",
        visible = n.visible, from = sh.from, to = sh.to,
      }
    end
  end
  return out
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
