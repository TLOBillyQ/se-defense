-- tools/acceptance/bootstrap.lua — puts the acceptance4lua rock on package.path,
-- installing it into .toolcache/luarocks first when the tree is missing.
-- Run from the repository root. Override the tree with SE_DEFENSE_LUA_TOOLS.
local M = {}

M.tree = os.getenv("SE_DEFENSE_LUA_TOOLS") or ".toolcache/luarocks"
M.src_dir = ".toolcache/src/acceptance4lua"
M.lock_file = "tools/tools.lock"

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function exists(path)
  local ok = os.execute("test -e " .. quote(path))
  return ok == true or ok == 0
end

local function run(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local function repo_url()
  local f = io.open(M.lock_file, "r")
  if not f then return nil, "missing " .. M.lock_file end
  for line in f:lines() do
    local name, url = line:match("^(%S+)%s+(%S+)")
    if name == "acceptance4lua" then f:close() return url end
  end
  f:close()
  return nil, "acceptance4lua is not listed in " .. M.lock_file
end

-- LUA_PATH for subprocesses (generated specs, runner worker): tool tree first,
-- then the repository and the business-module tree used by tools/acceptance/headless.lua.
function M.lua_path()
  local parts = {
    M.tree .. "/share/lua/5.4/?.lua",
    M.tree .. "/share/lua/5.4/?/init.lua",
    "./?.lua",
    "./?/init.lua",
  }
  local business = os.getenv("SE_DEFENSE_BUSINESS_DIR")
  if business and business ~= "" then
    parts[#parts + 1] = business .. "/?.lua"
    parts[#parts + 1] = business .. "/?/init.lua"
  end
  parts[#parts + 1] = ""
  parts[#parts + 1] = ""
  return table.concat(parts, ";")
end

function M.install()
  local url, err = repo_url()
  if not url then return nil, err end
  io.stderr:write("[acceptance] installing acceptance4lua from " .. url .. " into " .. M.tree .. "\n")
  if not exists(M.src_dir .. "/.git") then
    if not run("git clone --depth 1 " .. quote(url) .. " " .. quote(M.src_dir)) then
      return nil, "git clone failed for " .. url
    end
  end
  local lua_dir = os.getenv("SE_DEFENSE_LUA_DIR")
  local lua_dir_flag = lua_dir and (" --lua-dir " .. quote(lua_dir)) or ""
  local tree = M.tree
  if tree:sub(1, 1) ~= "/" then tree = "$(pwd)/" .. tree end
  local cmd = "tree=\"" .. tree .. "\" && cd " .. quote(M.src_dir)
    .. " && luarocks --tree \"$tree\" --lua-version 5.4" .. lua_dir_flag .. " make >&2"
  if not run(cmd) then return nil, "luarocks make failed (is luarocks installed?)" end
  return true
end

function M.ensure()
  if not exists(M.tree .. "/share/lua/5.4/acceptance4lua/init.lua") then
    local ok, err = M.install()
    if not ok then return nil, "error: " .. err end
  end
  package.path = M.lua_path() .. ";" .. package.path
  return true
end

return M
