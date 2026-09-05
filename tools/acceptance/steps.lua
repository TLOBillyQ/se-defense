-- tools/acceptance/steps.lua — Gherkin step handlers for features/*.feature.
--
-- acceptance4lua looks handlers up by exact step text (placeholders such as
-- <建筑> are kept in the key). Literal sentences that only differ by a number
-- ("游戏推进100个tick" / "游戏推进4个tick") share one implementation, so the
-- table resolves unknown keys through Lua patterns against the step text.
-- Handlers receive (world, example, step, resolved_text) and return true or
-- nil plus a message. Error messages avoid the phrase "not found": the runner
-- treats it as an infrastructure error.
local headless = require("tools.acceptance.headless")

local M = {}

-- Repo-layout steps (source-layout / deploy-mirror features) run from the
-- repository root and do not boot a game; helpers below serve them.
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function dir_exists(path)
  local ok, _, code = os.execute("test -d '" .. path .. "'")
  return ok ~= nil and code == 0
end

local function q(path)
  return "'" .. path .. "'"
end

-- Lua 5.4 binary that runs this spec (for subprocess steps such as deploy).
local function lua_bin()
  if arg and type(arg[-1]) == "string" and arg[-1]:match("lua") then
    return q(arg[-1])
  end
  return "lua5.4"
end

local function session(w)
  if not w.game then error("对局尚未启动（缺少背景步骤「一局全新的无头游戏」）") end
  return w.game
end

local function eq(actual, expected, label)
  if actual == expected then return true end
  return nil, string.format("%s 期望 %s，实际 %s", label, tostring(expected), tostring(actual))
end

local function num(v) return tonumber(v) or v end

-- Each entry: Lua pattern on the resolved step text -> handler(w, captures...).
local PATTERNS = {
  { "^一局全新的无头游戏$", function(w) w.game = headless.boot() return true end },
  { "^客户端已就绪$", function(w) headless.send(session(w), { kind = "client_ready" }) return true end },
  { "^游戏推进(%d+)个tick$", function(w, n) headless.steps(session(w), tonumber(n)) return true end },
  { "^客户端发送放置意图(%S+)$", function(w, key)
      headless.send(session(w), { kind = "input", itype = "place", key = key }) return true end },
  { "^客户端点击棋盘(%S+) (%S+)$", function(w, x, z)
      w.money_before = headless.money(session(w))
      headless.send(session(w), { kind = "input", itype = "tap", x = num(x), z = num(z) }) return true end },
  { "^客户端重开对局$", function(w) headless.send(session(w), { kind = "input", itype = "restart" }) return true end },
  { "^GM把金钱设为(%d+)$", function(w, n) headless.gm(session(w), "money", tonumber(n)) return true end },
  { "^GM采空全部资源$", function(w) headless.gm(session(w), "mine_out") return true end },
  { "^GM摧毁核心$", function(w) headless.gm(session(w), "kill_core") return true end },
  { "^游戏处于(%S+)模式$", function(w, mode) return eq(headless.mode(session(w)), mode, "游戏模式") end },
  { "^没有建筑处于放置中$", function(w) return eq(headless.placing(session(w)), nil, "放置中的建筑") end },
  { "^金钱为(%d+)$", function(w, n) return eq(headless.money(session(w)), tonumber(n), "金钱") end },
  { "^金钱减少了(%d+)$", function(w, n)
      if w.money_before == nil then return nil, "尚未记录点击前的金钱" end
      return eq(w.money_before - headless.money(session(w)), tonumber(n), "金钱减少量") end },
  { "^棋盘上实体总数为(%d+)$", function(w, n) return eq(#headless.entities(session(w)), tonumber(n), "实体总数") end },
  { "^棋盘上(%S+)的数量为(%d+)$", function(w, prefab, n)
      return eq(#headless.entities(session(w), prefab), tonumber(n), prefab .. " 数量") end },
  { "^(%S+)已通电$", function(w, prefab)
      for _, e in ipairs(headless.entities(session(w), prefab)) do
        if headless.has_power(e) then return true end
      end
      return nil, prefab .. " 没有任何实体通电" end },
  { "^(%S+)横幅可见$", function(w, name)
      return eq(headless.node_visible(session(w), "sidebar/" .. name), true, name .. " 横幅可见") end },
  -- ── 源码树布局（source-layout.feature，不启动对局）──
  { "^src的一级目录(%S+)是否存在为(%S+)$", function(w, dir, expect)
      local exists = dir_exists("src/" .. dir)
      if exists == (expect == "是") then return true end
      return nil, string.format("src/%s 存在性期望 %s，实际 %s",
        dir, expect, exists and "是" or "否") end },
  { "^src的一级目录都属于(.+)$", function(w, list)
      local allowed = {}
      for name in list:gmatch("%S+") do allowed[name] = true end
      local bad = {}
      local pipe = io.popen("ls -A1 src")
      for entry in pipe:lines() do
        if not allowed[entry] then bad[#bad + 1] = entry end
      end
      pipe:close()
      if #bad == 0 then return true end
      return nil, "src 一级含非工作区根条目: " .. table.concat(bad, ",") end },
  { "^源码树中存在文件(%S+)$", function(w, path)
      if read_file("src/" .. path) then return true end
      return nil, "src/" .. path .. " 不存在" end },
  { "^源码文件(%S+)引用模块(%S+)$", function(w, file, mod)
      local body = read_file("src/" .. file)
      if not body then return nil, "src/" .. file .. " 不存在" end
      if body:find('"' .. mod .. '"', 1, true) or body:find("'" .. mod .. "'", 1, true) then
        return true
      end
      return nil, string.format("src/%s 未引用模块 %s", file, mod) end },
  { "^src下没有文件引用以src%.开头的模块$", function(w)
      local bad = {}
      local pipe = io.popen("find src -name '*.lua'")
      for f in pipe:lines() do
        local body = read_file(f) or ""
        if body:find("require[%s%(]*[\"']src%.")
          or body:find("package%.loaded%s*%[%s*[\"']src%.") then
          bad[#bad + 1] = f
        end
      end
      pipe:close()
      if #bad == 0 then return true end
      return nil, "仍引用 src. 前缀模块: " .. table.concat(bad, ",") end },
  -- ── 部署镜像（deploy-mirror.feature，临时工作区在 ./tmp 下）──
  { "^一个空的临时工作区$", function(w)
      w.workspace = "tmp/deploy-mirror-workspace"
      os.execute("rm -rf " .. q(w.workspace))
      os.execute("mkdir -p " .. q(w.workspace))
      return true end },
  { "^临时工作区预置文件(%S+)$", function(w, path)
      if not w.workspace then return nil, "尚未创建临时工作区" end
      local full = w.workspace .. "/" .. path
      local parent = full:match("^(.*)/[^/]+$")
      if parent then os.execute("mkdir -p " .. q(parent)) end
      local f = io.open(full, "w")
      if not f then return nil, "无法写入 " .. full end
      f:write("-- preset\n")
      f:close()
      return true end },
  { "^执行部署到临时工作区$", function(w)
      if not w.workspace then return nil, "尚未创建临时工作区" end
      local cmd = "EGGY_WORKSPACE=" .. q(w.workspace)
        .. " " .. lua_bin() .. " tools/deploy.lua > /dev/null"
      local ok, _, code = os.execute(cmd)
      if ok and code == 0 then return true end
      return nil, "deploy 失败 exit=" .. tostring(code) end },
  { "^临时工作区存在文件(%S+)$", function(w, path)
      if not w.workspace then return nil, "尚未创建临时工作区" end
      if read_file(w.workspace .. "/" .. path) then return true end
      return nil, "临时工作区缺文件 " .. path end },
  { "^临时工作区不存在目录(%S+)$", function(w, path)
      if not w.workspace then return nil, "尚未创建临时工作区" end
      if not dir_exists(w.workspace .. "/" .. path) then return true end
      return nil, "临时工作区仍存在目录 " .. path end },
}

local function dispatch(text)
  for _, entry in ipairs(PATTERNS) do
    local captures = { text:match(entry[1]) }
    if captures[1] ~= nil then return entry[2], captures end
  end
  return nil
end

-- Handler for a raw step text (with placeholders): resolve against the
-- example-substituted text at run time.
local function handler_for(key)
  if not dispatch((key:gsub("<[^<>]+>", "0"))) then return nil end
  return function(w, _, _, resolved_text)
    local fn, captures = dispatch(resolved_text)
    if not fn then return nil, "步骤无法匹配: " .. tostring(resolved_text) end
    return fn(w, table.unpack(captures))
  end
end

function M.handlers()
  return setmetatable({}, { __index = function(_, key)
    if type(key) ~= "string" then return nil end
    return handler_for(key)
  end })
end

M.patterns = PATTERNS
return M
