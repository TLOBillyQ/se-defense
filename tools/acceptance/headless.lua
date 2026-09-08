-- tools/acceptance/headless.lua — boots the headless game (SE stub + real
-- host layer + server/main.lua) inside the current process and exposes the
-- query surface the step handlers need. Same boot sequence as
-- tools/headless/run_server.lua.
--
-- Fresh game per scenario: every module under server./client./common. (spoke included)
-- and the SE stub are dropped from package.loaded and required again, so
-- module-level state (host registries, stub signal lists, _G.bd) starts
-- from scratch.
local Roster = require("server.match.roster")

local M = {}

local real_print = print
local verbose = os.getenv("VERBOSE") == "1"

local function add_search_paths()
  local paths = { "./?.lua", "./?/init.lua" }
  package.path = table.concat(paths, ";") .. ";" .. package.path
end

local function reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^server%.") or name:match("^client%.") or name:match("^common%.")
      or name == "tools.headless.se_stub" then
      package.loaded[name] = nil
    end
  end
  _G.bd = nil
end

-- Boots a fresh game; returns a session table {stub, host}.
function M.boot()
  add_search_paths()
  reset_modules()
  local stub = require("tools.headless.se_stub")
  print = function(...) if verbose then real_print(...) end end
  local ok, err = pcall(function() assert(loadfile("server/main.lua"))() end)
  print = real_print
  if not ok then error(err, 0) end
  return { stub = stub, host = require("server.host") }
end

local function quiet(fn, ...)
  print = function(...) if verbose then real_print(...) end end
  local results = table.pack(pcall(fn, ...))
  print = real_print
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

function M.send(s, msg) quiet(s.stub.client_send, msg) end
function M.steps(s, n) quiet(s.stub.steps, n) end

-- 推进 seconds 秒：宿主固定步长 1/30 秒（秒数取整到步）。
function M.advance(s, seconds)
  quiet(s.stub.steps, math.floor(seconds * 30 + 0.5), 1 / 30)
end

function M.gm(s, fn, ...)
  local f = _G.bd and _G.bd[fn]
  if type(f) ~= "function" then error("GM 命令不存在: " .. tostring(fn)) end
  return quiet(f, ...)
end

local function root()
  local r = _G.bd and _G.bd.root
  if not r then error("_G.bd.root 未就绪") end
  return r
end

function M.mode(_) return root().game_state.mode:now() end
function M.money(_) return root().game_state.money:now() end
function M.placing(_)
  local p = root().board_interactions.placing:now()
  return p and p.key or nil
end

function M.entities(s, prefab)
  local items = {}
  for _, e in ipairs(s.host.entity.all()) do
    if prefab == nil or e.prefab == prefab then items[#items + 1] = e end
  end
  return items
end

function M.has_power(e)
  local pool = root().pool
  local rec = pool and pool:live_record(e.id)
  return M.building_power(rec and rec.epoch and rec.epoch.building)
end

function M.node_visible(s, path)
  local n = s.host.eui.nodes and s.host.eui.nodes[path]
  return n ~= nil and n.visible == true
end

function M.node(s, path)
  return s.host.eui.nodes and s.host.eui.nodes[path] or nil
end

-- ── 规则层读取面（GDD 词汇 → 本地游戏结构）────────────────────────────
-- 「谁在场」类问题全部转发 server/match/roster.lua（GM 面同源），这里不重做。

-- 矿点：按坐标取 Resource 组件。
function M.site_at(_, x, z)
  return Roster.site_at(root(), x, z)
end

function M.sites_remaining(_)
  return root().game_state.resources_remaining:now()
end

-- 建筑：Core 走 game_state.core，其余走 pool live 记录。
-- 返回 building 组件（.power/.health/.departed）与 pool 记录（非 Core）。
function M.building_at(_, kind, x, z)
  local b, rec = Roster.building_at(root(), kind, x, z)
  if kind == "Core" and b then return b.building, nil end
  return b, rec
end

-- 某类型建筑是否在场（未离场即在场，碎裂中算在场）。
function M.building_present(_, kind)
  return Roster.building_present(root(), kind)
end

-- 场上建筑数：Core（在场时）+ pool live 建筑数。
function M.building_count(_)
  return Roster.building_count(root())
end

function M.building_power(b)
  local p = b and b.power and b.power.has_power
  return p ~= nil and p:now() == true
end

-- 绝对血量 = 占比 × 上限（读取误差由步骤层 ±0.05 容差吸收）。
function M.building_hp(b)
  return b.health.hp_fraction:now() * b.health.max_hp:now()
end

-- 供电者位置：PowerNode.parent 的当前位置；无供电者返回 nil。
function M.provider_pos(b)
  local parent = b and b.power and b.power.parent and b.power.parent:now()
  if not parent then return nil end
  local p = parent:position()
  return { x = p.x, z = p.z }
end

-- 建筑是否可选（GDD 04：资金不低于价格）。类型未知返回 nil + 原因。
function M.selectable(_, kind)
  local key = string.lower(tostring(kind))
  local spec = root().building_specs and root().building_specs[key]
  if not spec then return nil, "未知建筑类型: " .. tostring(kind) end
  return (root().game_state.money:now() or 0) >= (spec.cost or 0)
end

-- 采集速率 = 正在采集的矿点数 × 1.25（GDD 02 R6）。
function M.collect_rate(_)
  return root().game_state.collect_rate:now()
end

-- 波次状态（wave_director.wave:now() 快照表）。
function M.wave(_)
  return root().wave_director.wave:now()
end

-- 来袭方向（中文名）：倒计时 ≤ 5 才公布，否则 nil（GDD 07 W2）。
function M.wave_direction(_)
  return root().wave_director:revealed_direction()
end

function M.site_list(_)
  return root().resources or {}
end

function M.enemy_list(_)
  return root().enemies or {}
end

-- 敌人：root.enemies 全序列（含死亡，保「第 N 个敌人」序号）。
function M.enemy_nth(_, n)
  return root().enemies[n]
end

function M.enemy_hp(e)
  return e.health.hp_fraction:now() * e.health.max_hp:now()
end

function M.enemy_pos(e)
  local p = e.entity:get_position()
  return { x = p.x, z = p.z }
end

function M.enemy_alive(e)
  return e.health.is_alive:now()
end

function M.enemy_tracked(e)
  return e.is_tracked and e.is_tracked:now() == true
end

-- ── 表现层读取面（GDD 11–16）───────────────────────────────────────

-- 节点文本/可见/颜色/填充/可用：node 为 eui 节点表（nil 表示未创建）。
function M.node_text(s, path)
  local n = M.node(s, path)
  return n and n.text or nil
end

function M.node_enabled(s, path)
  local n = M.node(s, path)
  return n and n.enabled == true or false
end

function M.node_color(s, path)
  local n = M.node(s, path)
  return n and { n.color.r, n.color.g, n.color.b } or nil
end

function M.node_fill(s, path)
  local n = M.node(s, path)
  return n and n.fill or nil
end

-- 悬停：当前 hovering 单位组件（无则 nil）。
function M.hover_target(_)
  local bi = root().board_interactions
  return bi and bi.hovering:now() or nil
end

-- 悬停描述三行（V3：首行建筑名大写 + 两行英文原文；按空行切分）。
function M.hover_lines(s)
  local h = M.hover_target(s)
  local info = h and h.hover_info and h.hover_info:now()
  if not info or not info.description then return nil end
  local lines = {}
  for part in string.gmatch(info.description, "([^\n]+)") do
    lines[#lines + 1] = part
  end
  return lines
end

-- 建筑实体着色（断电变暗 0.35 / 受击红闪 (1,0,0) / 正常 1，GDD 15 F2/F4）。
-- 返回实体当前颜色 {r,g,b}；建筑不在场返回 nil。
function M.building_tint(s, kind, x, z)
  local b, rec = M.building_at(s, kind, x, z)
  local entity
  if kind == "Core" then
    entity = root().game_state.core and root().game_state.core.entity
  else
    entity = rec and rec.entity
  end
  if not entity then return nil end
  local c = entity:get_color()
  return c and { c.r or c[1], c.g or c[2], c.b or c[3] } or nil
end

-- 碎裂中：该类型有「已死亡但未离场」的建筑（GDD 15 F3）。
function M.crumbling(_, kind)
  return Roster.crumbling(root(), kind)
end

-- 边缘警示是否激活（GDD 12 A3：闪烁中即显示，与瞬时亮灭无关）。
function M.warning_active(_, front_eng)
  local ann = root().announcer
  local st = ann and ann.warning_active and ann.warning_active[front_eng]
  return st ~= nil and st:now() == true
end

-- 边缘警示闪烁周期（= Announcer 配置的 wave_warning_blink_time）。
function M.blink_period(_)
  local ann = root().announcer
  return ann and ann.wave_warning_blink_time or nil
end

-- 敌人揭示标记（GDD 15 F5）。
function M.enemy_marked(s, e)
  return M.node_visible(s, "enemy_" .. e.entity.id .. "_mark")
end

-- 形状（覆盖圈/连线/光束等就地渲染的 EffectUnit 记录）。
function M.shapes(s, prefix)
  local out = {}
  for _, sh in ipairs(s.host.eui.shapes()) do
    if prefix == nil or sh.path:sub(1, #prefix) == prefix then out[#out + 1] = sh end
  end
  return out
end

return M
