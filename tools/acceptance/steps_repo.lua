-- tools/acceptance/steps_repo.lua — step handlers that inspect the repository
-- itself (features/source-layout.feature, features/deploy-mirror.feature).
--
-- These steps run from the repository root and never boot a game; they are
-- kept apart from the game-session steps in steps.lua so each file has one
-- job. steps.lua appends `patterns` to its own dispatch table; the entry
-- shape is identical: { lua-pattern, handler(w, captures...) }.
local M = {}

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

local function workspace(w)
  if not w.workspace then return nil, "尚未创建临时工作区" end
  return w.workspace
end

M.patterns = {
  -- ── 源码树布局（source-layout.feature，不启动对局）──
  { "^仓库根目录(%S+)是否存在为(%S+)$", function(w, dir, expect)
      if expect ~= "是" and expect ~= "否" then
        return nil, "存在性期望只能是 是/否，实际 " .. expect
      end
      local exists = dir_exists(dir)
      if exists == (expect == "是") then return true end
      return nil, string.format("%s 存在性期望 %s，实际 %s",
        dir, expect, exists and "是" or "否") end },
  { "^部署白名单为(.+)$", function(w, list)
      local want = {}
      for name in list:gmatch("%S+") do want[#want + 1] = name end
      local deploy = require("tools.deploy")
      if table.concat(deploy.REALMS, " ") == table.concat(want, " ") then return true end
      return nil, "部署白名单实际为 " .. table.concat(deploy.REALMS, " ") end },
  { "^源码树中存在文件(%S+)$", function(w, path)
      if read_file(path) then return true end
      return nil, path .. " 不存在" end },
  { "^源码文件(%S+)引用模块(%S+)$", function(w, file, mod)
      local body = read_file(file)
      if not body then return nil, file .. " 不存在" end
      if body:find('"' .. mod .. '"', 1, true) or body:find("'" .. mod .. "'", 1, true) then
        return true
      end
      return nil, string.format("%s 未引用模块 %s", file, mod) end },
  { "^部署树下没有文件引用以src%.开头的模块$", function(w)
      local bad = {}
      local pipe = io.popen("find client common server -name '*.lua'")
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
      local ws, err = workspace(w)
      if not ws then return nil, err end
      local full = ws .. "/" .. path
      local parent = full:match("^(.*)/[^/]+$")
      if parent then os.execute("mkdir -p " .. q(parent)) end
      local f = io.open(full, "w")
      if not f then return nil, "无法写入 " .. full end
      f:write("-- preset\n")
      f:close()
      return true end },
  { "^执行部署到临时工作区$", function(w)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      local cmd = "EGGY_WORKSPACE=" .. q(ws)
        .. " " .. lua_bin() .. " tools/deploy.lua > /dev/null"
      local ok, _, code = os.execute(cmd)
      if ok and code == 0 then return true end
      return nil, "deploy 失败 exit=" .. tostring(code) end },
  { "^临时工作区存在文件(%S+)$", function(w, path)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      if read_file(ws .. "/" .. path) then return true end
      return nil, "临时工作区缺文件 " .. path end },
  { "^临时工作区不存在目录(%S+)$", function(w, path)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      if not dir_exists(ws .. "/" .. path) then return true end
      return nil, "临时工作区仍存在目录 " .. path end },
}

return M
