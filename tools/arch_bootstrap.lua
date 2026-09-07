-- tools/arch/bootstrap.lua — puts the arch_view rock on package.path,
-- installing it into .toolcache/luarocks first when the tree is missing.
-- Mirrors tools/acceptance/bootstrap.lua. Run from the repository root.
-- Override the tree with SE_DEFENSE_LUA_TOOLS.
local M = {}

M.tree = os.getenv("SE_DEFENSE_LUA_TOOLS") or ".toolcache/luarocks"
M.src_dir = ".toolcache/src/arch_view"
-- Follows upstream main: bootstrap clones HEAD (no version pin) and runs
-- `luarocks make`. Delete .toolcache/src/arch_view to reinstall.
M.repo_url = "http://lzxsvn:3000/eggy/arch-view"

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function exists(path)
  local ok = os.execute("test -e " .. quote(path))
  return ok == true or ok == 0
end

local function run(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

function M.lua_path()
  return table.concat({
    M.tree .. "/share/lua/5.4/?.lua",
    M.tree .. "/share/lua/5.4/?/init.lua",
    "./?.lua",
    "./?/init.lua",
    "",
  }, ";")
end

function M.install()
  local url = M.repo_url
  io.stderr:write("[arch] installing arch_view from " .. url .. " into " .. M.tree .. "\n")
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
  if not exists(M.tree .. "/share/lua/5.4/arch_view/init.lua") then
    local ok, err = M.install()
    if not ok then return nil, "error: " .. err end
  end
  package.path = M.lua_path() .. ";" .. package.path
  return true
end

return M
