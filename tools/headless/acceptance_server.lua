-- 无头验收服务器：SE 桩 + 真适配层 + 服务端 main.lua，每场景执行一个进程。
-- 协议：stdin/stdout 各一行一个 JSON（NDJSON）；stdout 仅协议，诊断走 stderr（VERBOSE=1 开业务日志）。
-- 与 tools/headless/run_server.lua 相同的 mock 同路径替换与启动序列。
package.path = "./?.lua;./?/init.lua;" .. package.path

package.preload["examples.base_defence.host_mock"] = function() return require("src.adapter.host") end
package.preload["examples.base_defence.eui_mock"] = function() return require("src.adapter.eui") end
package.preload["examples.base_defence.input_mock"] = function() return require("src.adapter.input") end
package.preload["examples.host_mock"] = function() return require("src.adapter.host_base") end

local stub = require("tools.headless.se_stub")
local real_print = print
local verbose = os.getenv("VERBOSE") == "1"
print = function(...) if verbose then real_print(...) end end

assert(loadfile("src/server/main.lua"))()
local host = require("src.adapter.host")

-- 最小 JSON 编解码（ASCII 域，无第三方依赖；桩环境无 cjson）
local json = {}
local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encode_value(v, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = '"' .. (v:gsub('[%z\1-\31"\\]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end)) .. '"'
  elseif t == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.10g", v) end
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    local n, other = 0, 0
    for k in pairs(v) do
      if type(k) == "number" and k >= 1 and k == math.floor(k) then n = n + 1 else other = other + 1 end
    end
    if other == 0 and n == #v then
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        encode_value(v[i], out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        if type(k) == "string" then
          if not first then out[#out + 1] = "," end
          first = false
          encode_value(k, out)
          out[#out + 1] = ":"
          encode_value(val, out)
        end
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function json.encode(v)
  local out = {}
  encode_value(v, out)
  return table.concat(out)
end

local function skip_ws(s, i)
  while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end
  return i
end

local decode_value
decode_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    local out, j = {}, i + 1
    while j <= #s do
      local ch = s:sub(j, j)
      if ch == '"' then return table.concat(out), j + 1 end
      if ch == '\\' then
        local nxt = s:sub(j + 1, j + 1)
        if nxt == 'n' then out[#out + 1] = '\n' elseif nxt == 't' then out[#out + 1] = '\t'
        elseif nxt == 'r' then out[#out + 1] = '\r' elseif nxt == 'u' then
          out[#out + 1] = string.char(tonumber(s:sub(j + 2, j + 5), 16) or 63)
          j = j + 4
        else out[#out + 1] = nxt end
        j = j + 2
      else
        out[#out + 1] = ch
        j = j + 1
      end
    end
    error("unterminated string")
  elseif c == '{' then
    local t, j = {}, i + 1
    j = skip_ws(s, j)
    if s:sub(j, j) == '}' then return t, j + 1 end
    while true do
      j = skip_ws(s, j)
      local key
      key, j = decode_value(s, j)
      j = skip_ws(s, j)
      if s:sub(j, j) ~= ':' then error("expected :") end
      local val
      val, j = decode_value(s, j + 1)
      t[key] = val
      j = skip_ws(s, j)
      local sep = s:sub(j, j)
      j = j + 1
      if sep == '}' then return t, j end
      if sep ~= ',' then error("expected , or }") end
    end
  elseif c == '[' then
    local t, j = {}, i + 1
    j = skip_ws(s, j)
    if s:sub(j, j) == ']' then return t, j + 1 end
    local n = 0
    while true do
      n = n + 1
      local val
      val, j = decode_value(s, j)
      t[n] = val
      j = skip_ws(s, j)
      local sep = s:sub(j, j)
      j = j + 1
      if sep == ']' then return t, j end
      if sep ~= ',' then error("expected , or ]") end
    end
  elseif c == 't' then return true, i + 4
  elseif c == 'f' then return false, i + 5
  elseif c == 'n' then return nil, i + 4
  else
    local num = s:sub(i):match("^-?%d+%.?%d*[eE]?[+-]?%d*")
    if num and num ~= "" and tonumber(num) then return tonumber(num), i + #num end
    error("unexpected token at " .. i)
  end
end

function json.decode(s)
  local v, j = decode_value(s, 1)
  return v, j
end

-- 响应/诊断
local function reply(t)
  io.write(json.encode(t) .. "\n")
  io.flush()
end
local function fail(msg)
  reply({ ok = false, error = tostring(msg) })
end
local function ok(data)
  if not data then data = {} end
  data.ok = true
  reply(data)
end

-- 状态快照（懒加载 root —— gm restart 后重建）
local function sync_root()
  local r = _G.bd and _G.bd.root or nil
  if not r then error("_G.bd.root 未就绪") end
  return r, r.game_state, r.board_interactions, r.wave_director
end

local function last_sent_node(path)
  for i = #stub.sent, 1, -1 do
    local m = stub.sent[i]
    if m.nodes and m.nodes[path] then return m.nodes[path] end
  end
  return nil
end

local function entity_item(e)
  local u = e._unit
  local rec = _G.bd.root.pool and _G.bd.root.pool._live_by_entity_id and _G.bd.root.pool._live_by_entity_id[e.id]
  local b = rec and rec.epoch and rec.epoch.building
  local h = e.health or (b and b.health)
  local pos = e.position or { x = 0, y = 0, z = 0 }
  local sc = u and u.Scale or nil
  local mc = u and u.ModelColor1 or nil
  local alive = h and h.is_alive or nil
  local frac = h and h.hp_fraction or nil
  local item = {
    id = e.id,
    prefab = e.prefab,
    active = e.active,
    name = u and u.Name or nil,
    position = { x = pos.x, y = pos.y, z = pos.z },
    scale = sc and { x = sc.x, y = sc.y, z = sc.z } or nil,
    model_color = mc and { r = mc.r, g = mc.g, b = mc.b } or nil,
    max_hp = e.max_hp,
    hp_fraction = frac and frac:now() or nil,
    is_alive = alive and alive:now() or nil,
    has_power = b and b.power and b.power.has_power and b.power.has_power:now() or nil,
  }
  return item
end

local handlers_cmd = {
  ping = function()
    ok({})
  end,
  send = function(cmd)
    stub.client_send(cmd.msg or {})
    ok({})
  end,
  steps = function(cmd)
    stub.steps(tonumber(cmd.n) or 0)
    ok({})
  end,
  state = function()
    local root, gs, bi, wd = sync_root()
    local w = wd.wave:now()
    local placing = bi.placing:now()
    ok({
      state = {
        mode = gs.mode:now(),
        money = gs.money:now(),
        resources_remaining = gs.resources_remaining:now(),
        collect_rate = gs.collect_rate:now(),
        wave = { number = w.number, starts_in = w.starts_in },
        placing = placing and placing.key or nil,
        entities = #host.entity.all(),
        eui_nodes = #host.eui.order,
      },
    })
  end,
  node = function(cmd)
    local path = cmd.path
    local n = host.eui.nodes and host.eui.nodes[path]
    local item = nil
    if n then
      local c = n.color
      item = {
        visible = n.visible,
        text = n.text,
        fill = n.fill,
        color = c and { r = c.r, g = c.g, b = c.b } or nil,
      }
    end
    ok({ node = item, sent = last_sent_node(path) })
  end,
  entities = function(cmd)
    local want = cmd.prefab or "__all__"
    local items, count = {}, 0
    for _, e in ipairs(host.entity.all()) do
      if want == "__all__" or e.prefab == want then
        count = count + 1
        items[#items + 1] = entity_item(e)
      end
    end
    ok({ entities = { count = count, items = items } })
  end,
  gm = function(cmd)
    local fn = _G.bd and _G.bd[cmd.fn]
    if type(fn) ~= "function" then fail("GM fn not found: " .. tostring(cmd.fn)) return end
    local args = cmd.args or {}
    local running = { pcall(fn, table.unpack(args)) }
    if not running[1] then fail(running[2]) return end
    sync_root() -- gm restart 等会换 root；顺带验证当前 root
    ok({})
  end,
  quit = function()
    os.exit(0)
  end,
}

for raw in io.lines() do
  local line = raw:gsub("^%s+", "")
  if line ~= "" then
    local cmd = nil
    local good, err = pcall(function() cmd = json.decode(line) end)
    if not good or type(cmd) ~= "table" then
      fail("bad command: " .. tostring(err))
    else
      local h = handlers_cmd[cmd.cmd]
      if not h then fail("unknown cmd: " .. tostring(cmd.cmd)) else
        local okk, e = pcall(h, cmd)
        if not okk then fail(e) end
      end
    end
  end
end
